-- 聊天消息也推送（以前只有“想和你聊天”的请求会推）：
-- - 私信、球局群聊、球群群聊有新消息，推给会话里的其他人：自己发的不推，互相拉黑的不推；消息请求还是只推那条请求
-- - 不进通知列表、不发邮件：单独一张排队表，推送服务取走就删，2 分钟内没推出去的不再推
-- - 私信：标题是对方，内容是消息；群聊（球局用球馆名、球群用群名）：标题是群名，内容是“谁: 消息”
-- - 推送里带上发消息的人（名字、头像）和会话：iPhone 显示带头像的聊天通知，点开直接进这个会话

create table public.chat_pushes (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  thread text not null,
  sender_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text not null,
  link text not null,
  -- 群聊的名字（球群名；球局群聊用球馆名），私信为空；members 是会话里一共几个人（私信为空）
  group_name text,
  members int,
  created_at timestamptz not null default now()
);

alter table public.chat_pushes enable row level security;
revoke all on public.chat_pushes from anon, authenticated;
grant all on public.chat_pushes to service_role;

-- 给会话里的其他人排队推送（只排有设备的人）。p_body 是存进去的那份（不当词已经换成 ***）
create function public.queue_chat_push(p_kind text, p_id uuid, p_thread text, p_sender uuid, p_body text)
returns void language sql security definer set search_path = '' as $$
  with members as (
    select p_id as user_id where p_kind = 'dm'
    union select gp.user_id from public.game_players gp where p_kind = 'game' and gp.game_id = p_id
    union select m.user_id from public.group_members m where p_kind = 'group' and m.group_id = p_id
  ), info as (
    select coalesce((select nickname from public.profiles where id = p_sender), '') as sender,
           case p_kind when 'group' then (select name from public.play_groups where id = p_id)
                       when 'game' then (select v.name from public.games g join public.venues v on v.id = g.venue_id where g.id = p_id)
           end as place,
           case when p_kind <> 'dm' then (select count(*)::int from members) end as total
  )
  insert into public.chat_pushes (user_id, thread, sender_id, title, body, link, group_name, members)
  select m.user_id, p_thread, p_sender,
         case when p_kind = 'dm' then i.sender else coalesce(i.place, i.sender) end,
         case when p_kind = 'dm' then p_body else i.sender || ': ' || p_body end,
         '/messages/' || p_kind || '/' || case when p_kind = 'dm' then p_sender else p_id end || '/',
         i.place, i.total
  from members m cross join info i
  where m.user_id <> p_sender
    and exists (select 1 from public.push_devices d where d.user_id = m.user_id)
    and not exists (select 1 from public.blocks b
                    where (b.blocker = m.user_id and b.blocked = p_sender) or (b.blocker = p_sender and b.blocked = m.user_id))
$$;

-- 发消息：和原来一样，只是会话开着（不是消息请求）时给其他人排队推送
create or replace function public.send_message(p_kind text, p_id uuid, p_body text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  key text := public.thread_key(p_kind, p_id);
  access text := public.thread_access(p_kind, p_id, me);
  content text := btrim(p_body);
  new_id bigint;
begin
  if me is null or access is null or access = 'closed' then raise exception 'chat_closed' using errcode = '42501'; end if;
  if access = 'requested' then raise exception 'request_pending' using errcode = '22023'; end if;
  if content is null or char_length(content) not between 1 and 1000 then raise exception 'invalid_message' using errcode = '22023'; end if;
  if (select count(*) from public.messages where sender_id = me and created_at > now() - interval '1 minute') >= 20
     or (select count(*) from public.messages where sender_id = me and created_at > now() - interval '1 day') >= 500 then
    raise exception 'too_many_messages' using errcode = '54000';
  end if;
  if access = 'request' then
    if content ~* '(https?:|www\.|@|\d{7,})' then raise exception 'no_contact_info' using errcode = '22023'; end if;
    if (select count(*) from public.message_requests where from_id = me and created_at > now() - interval '1 day') >= 10 then
      raise exception 'too_many_message_requests' using errcode = '54000';
    end if;
    insert into public.message_requests (from_id, to_id, group_id)
      values (me, p_id, (public.message_option(me, p_id) ->> 'group_id')::uuid);
    perform public.notify(p_id, 'message_request', '{name} wants to chat',
                          'You’re both in {group}. Reply or accept to keep chatting. If you ignore it, they won’t know.',
                          '/app/messages/dm/' || me || '/',
                          jsonb_build_object('name', (select nickname from public.profiles where id = me),
                                             'group', (select pg.name from public.play_groups pg join public.message_requests r on r.group_id = pg.id
                                                       where r.from_id = me and r.to_id = p_id)));
  elsif p_kind = 'dm' then
    -- 回复对方的请求就算接受
    update public.message_requests set accepted_at = now(), ignored_at = null where from_id = p_id and to_id = me and accepted_at is null;
  end if;
  insert into public.messages (thread, sender_id, body) values (key, me, content) returning id, body into new_id, content;
  insert into public.thread_reads as r (user_id, thread, last_read_id) values (me, key, new_id)
    on conflict on constraint thread_reads_pkey do update set last_read_id = excluded.last_read_id;
  if access = 'open' then perform public.queue_chat_push(p_kind, p_id, key, me, content); end if;
  return new_id;
end
$$;

-- 排了队就马上叫推送服务（和通知共用同一个触发函数）
create trigger chat_pushes_push after insert on public.chat_pushes
  referencing new table as fresh for each statement execute function public.push_new_notifications();

-- 取活：原来的通知，加上排队的聊天推送（取走就删；2 分钟前的直接丢掉）。
-- 聊天推送没有 id（不回报送达），多带一个 chat：会话、发消息的人（名字、头像路径）、群名、人数
create or replace function public.claim_push_batch()
returns jsonb language sql security definer set search_path = '' as $$
  with picked as (
    update public.notifications n set push_tried_at = now()
    where n.id in (select x.id from public.notifications x
                   where x.push_tried_at is null and x.created_at > now() - interval '2 minutes'
                     and exists (select 1 from public.push_devices d where d.user_id = x.user_id)
                   order by x.id limit 200 for update skip locked)
    returning n.id, n.user_id, n.title, n.body, n.link
  ), chats as (
    delete from public.chat_pushes c
    where c.id in (select x.id from public.chat_pushes x order by x.id limit 200 for update skip locked)
    returning c.*
  )
  select coalesce(jsonb_agg(item), '[]') from (
    select jsonb_build_object('id', p.id, 'kind', d.kind, 'token', d.token, 'keys', d.keys,
                              'title', p.title, 'body', p.body, 'link', p.link) as item
    from picked p join public.push_devices d on d.user_id = p.user_id
    union all
    select jsonb_build_object('id', null, 'kind', d.kind, 'token', d.token, 'keys', d.keys,
                              'title', c.title, 'body', c.body, 'link', c.link,
                              'chat', jsonb_build_object('thread', c.thread, 'sender', c.sender_id, 'name', pr.nickname,
                                                         'avatar', pr.avatar_path, 'group', c.group_name, 'members', c.members))
    from chats c join public.push_devices d on d.user_id = c.user_id left join public.profiles pr on pr.id = c.sender_id
    where c.created_at > now() - interval '2 minutes'
  ) items
$$;

revoke execute on function public.queue_chat_push(text, uuid, text, uuid, text) from public, anon, authenticated;
revoke execute on function public.claim_push_batch() from public, anon, authenticated;
grant execute on function public.claim_push_batch() to service_role;
