-- 用户反馈：App 和网站里直接提交，管理员在后台看、回复（回复作为通知发给用户）
create table public.feedback (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('bug', 'idea', 'court', 'other')),
  body text not null check (char_length(body) between 5 and 2000),
  -- 版本、系统、机型、语言：用户提交前能看到
  context jsonb not null default '{}',
  status text not null default 'new' check (status in ('new', 'done')),
  reply text check (char_length(reply) <= 1000),
  replied_at timestamptz,
  replied_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index feedback_status_idx on public.feedback (status, id desc);
create index feedback_user_idx on public.feedback (user_id, created_at);
alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;

create function public.submit_feedback(p_kind text, p_body text, p_context jsonb default '{}')
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  text_ text := btrim(p_body);
  new_id bigint;
  admin record;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if char_length(text_) not between 5 and 2000 then raise exception 'invalid_feedback' using errcode = '22023'; end if;
  if (select count(*) from public.feedback where user_id = me and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_much_feedback' using errcode = '54000';
  end if;
  insert into public.feedback (user_id, kind, body, context)
    values (me, p_kind, text_, coalesce((select jsonb_object_agg(key, left(value, 60)) from jsonb_each_text(coalesce(p_context, '{}'))
                                          where key in ('app', 'platform', 'os', 'device', 'locale')), '{}'))
    returning id into new_id;
  for admin in select user_id from public.admin_users loop
    perform public.notify(admin.user_id, 'feedback', 'New feedback', '{name}: {text}', '/admin/feedback/',
      jsonb_build_object('name', (select nickname from public.profiles where id = me), 'text', left(text_, 80)));
  end loop;
  return new_id;
end
$$;

-- 待处理的在前；每次最多 100 条
create function public.admin_feedback(p_status text default 'new')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return coalesce((
    select jsonb_agg(x order by x.id desc) from (
      select f.id, f.kind, f.body, f.context, f.status, f.reply, f.replied_at, f.created_at,
             jsonb_build_object('id', p.id, 'nickname', p.nickname, 'tag', p.tag) as "user"
      from public.feedback f join public.profiles p on p.id = f.user_id
      where f.status = p_status order by f.id desc limit 100) x), '[]');
end
$$;

-- 写了回复就作为通知发给用户；不写只标记处理完
create function public.admin_reply_feedback(p_id bigint, p_reply text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  f public.feedback;
  reply_ text := nullif(btrim(coalesce(p_reply, '')), '');
begin
  perform public.require_admin();
  update public.feedback set status = 'done', reply = coalesce(reply_, reply),
         replied_at = case when reply_ is null then replied_at else now() end,
         replied_by = case when reply_ is null then replied_by else auth.uid() end
    where id = p_id returning * into f;
  if f.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if reply_ is not null then
    perform public.notify(f.user_id, 'feedback_reply', 'Reply from Badie', '{text}', null, jsonb_build_object('text', reply_));
  end if;
end
$$;

revoke execute on function public.submit_feedback(text, text, jsonb), public.admin_feedback(text), public.admin_reply_feedback(bigint, text)
  from public, anon;
grant execute on function public.submit_feedback(text, text, jsonb), public.admin_feedback(text), public.admin_reply_feedback(bigint, text)
  to authenticated;

insert into public.notification_texts (locale, english, translated)
select l.locale, t.english, t.translated
from (values
  ('zh-Hans', 'New feedback', '新反馈'), ('zh-Hans', '{name}: {text}', '{name}：{text}'), ('zh-Hans', 'Reply from Badie', 'Badie 回复了你的反馈'),
  ('zh-Hant', 'New feedback', '新回饋'), ('zh-Hant', '{name}: {text}', '{name}：{text}'), ('zh-Hant', 'Reply from Badie', 'Badie 回覆了你的回饋'),
  ('ja', 'New feedback', '新しいフィードバック'), ('ja', '{name}: {text}', '{name}：{text}'), ('ja', 'Reply from Badie', 'Badie からの返信'),
  ('ko', 'New feedback', '새 의견'), ('ko', '{name}: {text}', '{name}: {text}'), ('ko', 'Reply from Badie', 'Badie의 답변'),
  ('hi', 'New feedback', 'नया फ़ीडबैक'), ('hi', '{name}: {text}', '{name}: {text}'), ('hi', 'Reply from Badie', 'Badie का जवाब'),
  ('id', 'New feedback', 'Masukan baru'), ('id', '{name}: {text}', '{name}: {text}'), ('id', 'Reply from Badie', 'Balasan dari Badie'),
  ('ms', 'New feedback', 'Maklum balas baharu'), ('ms', '{name}: {text}', '{name}: {text}'), ('ms', 'Reply from Badie', 'Balasan daripada Badie'),
  ('th', 'New feedback', 'ความคิดเห็นใหม่'), ('th', '{name}: {text}', '{name}: {text}'), ('th', 'Reply from Badie', 'Badie ตอบกลับแล้ว'),
  ('vi', 'New feedback', 'Góp ý mới'), ('vi', '{name}: {text}', '{name}: {text}'), ('vi', 'Reply from Badie', 'Badie đã trả lời')
) as t(locale, english, translated)
join (select distinct locale from public.notification_texts) l on l.locale = t.locale;
