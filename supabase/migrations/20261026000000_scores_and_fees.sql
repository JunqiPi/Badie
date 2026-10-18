-- 比分和 AA 付款（和 iOS 的 GameResult.score、paidPlayerIds 一致）：
-- - 报赛果时可以顺带填比分，只能是数字和分隔符（如 “21:18 19:21 21:15”），最多 40 个字
-- - 场地费付没付：自己标自己；房间开的局，房主可以替所有人标。只是记账，不涉及真实付款

alter table public.result_reports add column score text;
alter table public.game_players add column paid_at timestamptz;

drop function public.report_result(uuid, public.result_outcome);

-- 报赛果 / 改赛果：开赛后到结束 7 天内、确认之前都能改；outcome 为空 = 记不清了。返回最新状态
create function public.report_result(p_game uuid, p_outcome public.result_outcome, p_score text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  score text := nullif(btrim(coalesce(p_score, '')), '');
begin
  if not exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = auth.uid()
                 where g.id = p_game and g.status = 'scheduled' and now() between g.starts_at and g.ends_at + interval '7 days') then
    raise exception 'cannot_report' using errcode = 'P0002';
  end if;
  if score is not null and (char_length(score) > 40 or score !~ '^[0-9 :,/-]+$') then
    raise exception 'invalid_score' using errcode = '22023';
  end if;
  perform 1 from public.games where id = p_game for update;
  if (select r.status from public.game_result(p_game) r) = 'verified' then raise exception 'result_locked' using errcode = '22023'; end if;
  insert into public.result_reports (game_id, reporter_id, outcome, score)
    values (p_game, auth.uid(), p_outcome, case when p_outcome is null then null else score end)
    on conflict (game_id, reporter_id) do update set outcome = excluded.outcome, score = excluded.score, updated_at = now();
  return (select r.status from public.game_result(p_game) r);
end
$$;

-- 房间开的局，房主就是发起人；匹配和挑战的局没有发起人
create function public.game_host(p_game uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select owner_id from public.rooms where game_id = p_game limit 1
$$;

create function public.mark_paid(p_game uuid, p_user uuid, p_paid boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if not exists (select 1 from public.games g join public.game_players gp on gp.game_id = g.id and gp.user_id = me
                 where g.id = p_game and g.status = 'scheduled' and now() < g.ends_at + interval '30 days')
     or (p_user is distinct from me and public.game_host(p_game) is distinct from me) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  update public.game_players set paid_at = case when p_paid then coalesce(paid_at, now()) end
    where game_id = p_game and user_id = p_user;
end
$$;

-- 我的球局：加上发起人、每人付没付、比分
create or replace function public.my_games()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(item order by starts_at desc), '[]') from (
    select g.starts_at, jsonb_build_object(
      'id', g.id, 'mode', g.mode, 'starts_at', g.starts_at, 'ends_at', g.ends_at, 'status', g.status,
      'venue', jsonb_build_object('id', v.id, 'name', v.name, 'city', v.city, 'street', v.street, 'tz', v.time_zone_id,
                                  'lat', v.lat, 'lon', v.lon, 'pricing', v.pricing, 'country', v.country_code),
      'host_id', public.game_host(g.id),
      'my_team', me.team, 'checked_in', me.checked_in_at is not null,
      'my_report', (select jsonb_build_object('outcome', r.outcome, 'score', r.score) from public.result_reports r
                    where r.game_id = g.id and r.reporter_id = auth.uid()),
      'result', (select to_jsonb(gr) from public.game_result(g.id) gr),
      -- 最近一次填的比分（双方都填了以后来的为准）
      'score', (select r.score from public.result_reports r where r.game_id = g.id and r.score is not null
                order by r.updated_at desc limit 1),
      'review_until', g.ends_at + interval '48 hours',
      'players', (select jsonb_agg(jsonb_build_object('id', p.id, 'nickname', p.nickname, 'rating', gp.rating, 'team', gp.team,
                                                      'me', gp.user_id = auth.uid(), 'checked_in', gp.checked_in_at is not null,
                                                      'paid', gp.paid_at is not null,
                                                      'reviewed', exists (select 1 from public.game_reviews r where r.game_id = g.id
                                                                          and r.reviewer_id = auth.uid() and r.reviewee_id = gp.user_id))
                                   order by gp.team, gp.rating desc)
                  from public.game_players gp join public.profiles p on p.id = gp.user_id where gp.game_id = g.id)
    ) as item
    from public.games g
    join public.game_players me on me.game_id = g.id and me.user_id = auth.uid()
    join public.venues v on v.id = g.venue_id
    where g.ends_at > now() - interval '60 days'
  ) items
$$;

revoke execute on function public.game_host(uuid) from public, anon, authenticated;
revoke execute on function public.report_result(uuid, public.result_outcome, text), public.mark_paid(uuid, uuid, boolean) from public, anon;
grant execute on function public.report_result(uuid, public.result_outcome, text), public.mark_paid(uuid, uuid, boolean) to authenticated;
