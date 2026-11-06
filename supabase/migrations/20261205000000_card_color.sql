-- 资料卡片的颜色：没传照片时，卡片上半部分用这个颜色（没选过的按用户 ID 给一个默认色，前端算）
alter table public.profiles add column card_color text
  check (card_color in ('lime', 'lavender', 'peach', 'sky', 'pink', 'mint', 'butter', 'ink'));
grant update (card_color) on public.profiles to authenticated;

create or replace function public.player_card(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select base || jsonb_build_object(
    'win_rate', case when p_user = auth.uid() or (w ->> 'public')::boolean then w end,
    'challenge', public.challenge_availability(p_user),
    'message', public.message_option(auth.uid(), p_user) - 'group_id',
    'verified', pr.verified_kind,
    'avatar', pr.avatar_path,
    'gender', pr.gender,
    'tag', pr.tag,
    'card_color', pr.card_color,
    'recent_no_shows', public.recent_no_shows(p_user),
    'suspended_until', public.suspended_until(p_user))
  from public.player_card_base(p_user) base, public.win_rate(p_user) w, public.profiles pr
  where base is not null and pr.id = p_user
$$;

-- 卡片直接带上照片和颜色，不用每张再拉一次资料卡
create or replace function public.day_candidates(p_from timestamptz, p_to timestamptz, p_lat double precision, p_lon double precision,
                                      p_radius_km double precision)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(c order by c ->> 'starts_at'), '[]') from (
    select jsonb_build_object(
             'ticket', t.id, 'mode', t.mode, 'mixed', t.mixed, 'play_with', t.play_with,
             'starts_at', t.starts_at, 'ends_at', t.ends_at,
             'user', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'tag', p.tag, 'rating', p.rating, 'gender', p.gender,
                                        'recent_no_shows', public.recent_no_shows(p.id), 'avatar', p.avatar_path,
                                        'card_color', p.card_color),
             'venues', (select jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name) order by v.name)
                        from public.venues v where v.id = any (t.venue_ids))) as c
    from public.match_tickets t join public.profiles p on p.id = t.user_id
    where auth.uid() is not null and p_to - p_from <= interval '2 days'
      and t.status = 'searching' and t.starts_at < p_to and t.ends_at > p_from and t.lock_at > now() + interval '30 minutes'
      and public.can_invite(auth.uid(), t)
      and not exists (select 1 from public.candidate_skips s where s.viewer = auth.uid() and s.ticket_id = t.id)
      and exists (select 1 from public.venues v
                  where v.id = any (t.venue_ids)
                    and extensions.st_dwithin(v.location, extensions.st_makepoint(p_lon, p_lat)::extensions.geography,
                                              least(greatest(p_radius_km, 1), 100) * 1000))
    order by t.starts_at
    limit 50) x
$$;
