-- 审核规则 1.2（用户内容）：过滤不当用语，举报多一个“不当内容”，管理员 24 小时内处理举报。
-- 名字（昵称、球群名、球馆名）有不当词就不让存；自由文字（消息、简介、备注、约战留言）把不当词换成 ***。
-- 只查用户自己写的（auth.uid() 有值）；后台同步球馆目录、迁移、测试数据不查，免得误伤真实的地名。
--
-- 英文词表取自 LDNOOBW（List of Dirty, Naughty, Obscene, and Otherwise Bad Words，Shutterstock，CC BY 4.0，
-- https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words），去掉了容易误伤的词
-- （sex、sucks、hardcore、dick、cum、cornhole、coon 等），补了常见变形和针对亚裔的歧视词。中日韩的词是自己整理的：
-- 只收多字、没有别的意思的（不收“奶”“乳”这类单字，免得拦掉“奶茶”）。

create table public.blocked_terms (
  term text primary key,
  -- 拉丁字母按整词匹配（不误伤 Scunthorpe、Cockfosters）；中日韩、emoji 没有词的边界，按包含匹配
  whole_word boolean not null,
  -- 正则：数字、符号代替字母（sh1t、@ss）也算；词组里的空格可以没有或换成 - _
  pattern text not null generated always as (
    case when whole_word then
      replace(replace(replace(replace(replace(replace(replace(
        regexp_replace(term, '([.+*?(){}|^$\\[\]])', '\\\1', 'g'),
        'a', '[a@4]'), 'e', '[e3]'), 'i', '[i1!]'), 'o', '[o0]'), 's', '[s$5]'), 't', '[t7]'), ' ', '[\s_-]*')
    else regexp_replace(term, '([.+*?(){}|^$\\[\]])', '\\\1', 'g') end) stored
);
alter table public.blocked_terms enable row level security;
revoke all on public.blocked_terms from anon, authenticated;

insert into public.blocked_terms (term, whole_word) values
('2 girls 1 cup', true),
('2g1c', true),
('acrotomophilia', true),
('alabama hot pocket', true),
('alaskan pipeline', true),
('anal', true),
('anilingus', true),
('anus', true),
('apeshit', true),
('arsehole', true),
('arseholes', true),
('ass', true),
('asshole', true),
('assholes', true),
('assmunch', true),
('auto erotic', true),
('autoerotic', true),
('baby batter', true),
('baby juice', true),
('ball gag', true),
('ball gravy', true),
('ball licking', true),
('ball sack', true),
('ball sucking', true),
('bangbros', true),
('bangbus', true),
('barely legal', true),
('bastard', true),
('bastardo', true),
('bbw', true),
('bdsm', true),
('beaner', true),
('beaners', true),
('beastiality', true),
('bestiality', true),
('big breasts', true),
('big knockers', true),
('big tits', true),
('bimbos', true),
('bitch', true),
('bitches', true),
('bitchy', true),
('black cock', true),
('blow job', true),
('blow your load', true),
('blowjob', true),
('blue waffle', true),
('blumpkin', true),
('bollocks', true),
('boner', true),
('boob', true),
('boobs', true),
('booty call', true),
('brown showers', true),
('bukkake', true),
('bulldyke', true),
('bullet vibe', true),
('bullshit', true),
('bung hole', true),
('bunghole', true),
('busty', true),
('buttcheeks', true),
('butthole', true),
('camel toe', true),
('camgirl', true),
('camslut', true),
('camwhore', true),
('carpet muncher', true),
('carpetmuncher', true),
('ching chong', true),
('chink', true),
('chinky', true),
('cialis', true),
('circlejerk', true),
('cleveland steamer', true),
('clit', true),
('clitoris', true),
('clover clamps', true),
('clusterfuck', true),
('cock', true),
('cocks', true),
('coprolagnia', true),
('coprophilia', true),
('creampie', true),
('cumming', true),
('cumshot', true),
('cumshots', true),
('cunnilingus', true),
('cunt', true),
('cunts', true),
('darkie', true),
('date rape', true),
('daterape', true),
('deep throat', true),
('deepthroat', true),
('dendrophilia', true),
('dickhead', true),
('dickheads', true),
('dildo', true),
('dingleberries', true),
('dingleberry', true),
('dirty sanchez', true),
('dog style', true),
('doggie style', true),
('doggiestyle', true),
('doggy style', true),
('doggystyle', true),
('dominatrix', true),
('dommes', true),
('donkey punch', true),
('double dong', true),
('double penetration', true),
('dp action', true),
('dry hump', true),
('dvda', true),
('dyke', true),
('eat my ass', true),
('ecchi', true),
('ejaculation', true),
('fag', true),
('faggot', true),
('faggots', true),
('fck', true),
('felch', true),
('fellatio', true),
('feltch', true),
('female squirting', true),
('femdom', true),
('fingerbang', true),
('fisting', true),
('foot fetish', true),
('footjob', true),
('frotting', true),
('fuck', true),
('fuck buttons', true),
('fucked', true),
('fucker', true),
('fuckers', true),
('fuckface', true),
('fuckin', true),
('fucking', true),
('fucks', true),
('fucktards', true),
('fuckwit', true),
('fudge packer', true),
('fudgepacker', true),
('fuk', true),
('futanari', true),
('g-spot', true),
('gang bang', true),
('gangbang', true),
('gay sex', true),
('giant cock', true),
('girls gone wild', true),
('goatcx', true),
('goatse', true),
('gokkun', true),
('golden shower', true),
('goo girl', true),
('gook', true),
('goregasm', true),
('group sex', true),
('hand job', true),
('handjob', true),
('hentai', true),
('honkey', true),
('horny', true),
('hot carl', true),
('humping', true),
('incest', true),
('jack off', true),
('jail bait', true),
('jailbait', true),
('jerk off', true),
('jigaboo', true),
('jiggaboo', true),
('jiggerboo', true),
('jizz', true),
('kike', true),
('kill yourself', true),
('kinbaku', true),
('kinkster', true),
('knobbing', true),
('kys', true),
('lemon party', true),
('livesex', true),
('male squirting', true),
('masturbate', true),
('masturbating', true),
('masturbation', true),
('menage a trois', true),
('milf', true),
('missionary position', true),
('motherfucker', true),
('mound of venus', true),
('mr hands', true),
('muff diver', true),
('muffdiving', true),
('nambla', true),
('nawashi', true),
('negro', true),
('neonazi', true),
('nig nog', true),
('nigga', true),
('niggas', true),
('nigger', true),
('niggers', true),
('nimphomania', true),
('nsfw', true),
('nsfw images', true),
('nutten', true),
('nympho', true),
('nymphomania', true),
('omorashi', true),
('one cup two girls', true),
('one guy one jar', true),
('orgasm', true),
('orgy', true),
('paedophile', true),
('paki', true),
('pedobear', true),
('pedophile', true),
('penis', true),
('phone sex', true),
('piece of shit', true),
('pikey', true),
('piss pig', true),
('pisspig', true),
('pole smoker', true),
('ponyplay', true),
('poof', true),
('poontang', true),
('poop chute', true),
('poopchute', true),
('porn', true),
('porno', true),
('pornography', true),
('prince albert piercing', true),
('pthc', true),
('pubes', true),
('punany', true),
('pussy', true),
('queaf', true),
('queef', true),
('quim', true),
('raghead', true),
('raging boner', true),
('rape', true),
('raping', true),
('rapist', true),
('retard', true),
('retarded', true),
('retards', true),
('reverse cowgirl', true),
('rimjob', true),
('rimming', true),
('rosy palm', true),
('rosy palm and her 5 sisters', true),
('rusty trombone', true),
('s&m', true),
('schlong', true),
('semen', true),
('sexcam', true),
('sexo', true),
('shaved beaver', true),
('shaved pussy', true),
('shemale', true),
('shibari', true),
('shit', true),
('shitblimp', true),
('shithead', true),
('shits', true),
('shitty', true),
('slanteye', true),
('slut', true),
('sluts', true),
('smut', true),
('sodomize', true),
('sodomy', true),
('spastic', true),
('spic', true),
('splooge', true),
('splooge moose', true),
('spooge', true),
('strap on', true),
('strapon', true),
('strappado', true),
('style doggy', true),
('suicide girls', true),
('sultry women', true),
('swastika', true),
('tea bagging', true),
('threesome', true),
('throating', true),
('thumbzilla', true),
('tits', true),
('titties', true),
('titty', true),
('tosser', true),
('towelhead', true),
('tranny', true),
('tribadism', true),
('tub girl', true),
('tubgirl', true),
('twat', true),
('twats', true),
('two girls one cup', true),
('upskirt', true),
('urethra play', true),
('urophilia', true),
('vagina', true),
('venus mound', true),
('viagra', true),
('vibrator', true),
('vorarephilia', true),
('voyeurweb', true),
('voyuer', true),
('vulva', true),
('wank', true),
('wanker', true),
('wankers', true),
('wet dream', true),
('wetback', true),
('white power', true),
('whore', true),
('whores', true),
('worldsex', true),
('wrapping men', true),
('wrinkled starfish', true),
('xxx', true),
('yaoi', true),
('yellow showers', true),
('yiffy', true),
('zoophilia', true),
('おまんこ', false),
('ちんぽ', false),
('ヤリマン', false),
('一夜情', false),
('仆街', false),
('他妈的', false),
('他媽的', false),
('你妈的', false),
('你妈逼', false),
('你媽的', false),
('你媽逼', false),
('做愛', false),
('做爱', false),
('傻屄', false),
('傻屌', false),
('傻比', false),
('傻逼', false),
('冚家鏟', false),
('冚家铲', false),
('卖淫', false),
('口交', false),
('妈逼', false),
('妓女', false),
('婊', false),
('媽逼', false),
('嫖娼', false),
('屄', false),
('屌你', false),
('干你娘', false),
('幹你娘', false),
('強姦', false),
('强奸', false),
('性交', false),
('援交', false),
('撲街', false),
('操你', false),
('操你妈', false),
('操你媽', false),
('支那', false),
('日你妈', false),
('日你媽', false),
('机掰', false),
('機掰', false),
('死基佬', false),
('沙比', false),
('煞笔', false),
('狗娘养的', false),
('狗娘養的', false),
('狗日的', false),
('王八蛋', false),
('約炮', false),
('约炮', false),
('肏', false),
('肛交', false),
('自慰', false),
('色情', false),
('草你妈', false),
('草你媽', false),
('草泥馬', false),
('草泥马', false),
('裸照', false),
('賣淫', false),
('賤人', false),
('賤貨', false),
('贱人', false),
('贱货', false),
('輪姦', false),
('轮奸', false),
('阴茎', false),
('阴道', false),
('陰莖', false),
('陰道', false),
('雞巴', false),
('雞掰', false),
('騷貨', false),
('骚货', false),
('鸡巴', false),
('鸡掰', false),
('黃片', false),
('黄片', false),
('黑鬼', false),
('개새끼', false),
('병신', false),
('썅', false),
('씨바', false),
('씨발', false),
('좆', false),
('지랄', false),
('🖕', false);

-- 所有词合成一个正则（整词的一组 + 包含的一组）
create function public.blocked_pattern()
returns text language sql stable security definer set search_path = '' as $$
  select nullif(concat_ws('|', '\m(' || string_agg(pattern, '|') filter (where whole_word) || ')\M',
                                '(' || string_agg(pattern, '|') filter (where not whole_word) || ')'), '')
  from public.blocked_terms
$$;

create function public.has_offensive(p_text text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(p_text ~* public.blocked_pattern(), false)
$$;

create function public.clean_text(p_text text)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(regexp_replace(p_text, public.blocked_pattern(), '***', 'gi'), p_text)
$$;
revoke execute on function public.blocked_pattern(), public.has_offensive(text), public.clean_text(text) from public, anon, authenticated;

-- 名字类：有不当词就不让存（参数是要查的列名）
create function public.reject_offensive()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  col text;
begin
  if auth.uid() is null then return new; end if;
  foreach col in array tg_argv loop
    if public.has_offensive(to_jsonb(new) ->> col) then raise exception 'objectionable_content' using errcode = '22023'; end if;
  end loop;
  return new;
end
$$;

-- 自由文字：把不当词换成 ***
create function public.mask_offensive()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  col text;
begin
  if auth.uid() is null then return new; end if;
  foreach col in array tg_argv loop
    if to_jsonb(new) ->> col is not null then
      new := jsonb_populate_record(new, jsonb_build_object(col, public.clean_text(to_jsonb(new) ->> col)));
    end if;
  end loop;
  return new;
end
$$;
revoke execute on function public.reject_offensive(), public.mask_offensive() from public, anon, authenticated;

create trigger profiles_name_filter before insert or update of nickname on public.profiles
  for each row execute function public.reject_offensive('nickname');
create trigger groups_name_filter before insert or update of name on public.play_groups
  for each row execute function public.reject_offensive('name');
create trigger groups_text_filter before insert or update of summary on public.play_groups
  for each row execute function public.mask_offensive('summary');
create trigger venues_name_filter before insert or update of name, aliases on public.venues
  for each row execute function public.reject_offensive('name', 'aliases');
create trigger venues_text_filter before insert or update of entrance_note on public.venues
  for each row execute function public.mask_offensive('entrance_note');
create trigger messages_filter before insert on public.messages
  for each row execute function public.mask_offensive('body');
create trigger schedules_text_filter before insert or update of fee_note on public.group_schedules
  for each row execute function public.mask_offensive('fee_note');
create trigger rooms_text_filter before insert or update of note on public.rooms
  for each row execute function public.mask_offensive('note');
create trigger challenges_text_filter before insert or update of message on public.challenges
  for each row execute function public.mask_offensive('message');

-- ---------------------------------------------------------------------------
-- 举报：多一个“不当内容（昵称、头像、消息）”；通知管理员去审核页
-- ---------------------------------------------------------------------------

alter table public.user_reports drop constraint user_reports_reason_check,
  add constraint user_reports_reason_check
    check (reason in ('harassment', 'scam', 'unsafe', 'fake', 'wrong_gender', 'inappropriate', 'other'));

create or replace function public.report_user(p_user uuid, p_reason text, p_details text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  admin record;
begin
  if me is null or p_user = me or not public.related(me, p_user) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if (select count(*) from public.user_reports where reporter_id = me and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_many_requests' using errcode = '54000';
  end if;
  insert into public.user_reports (reporter_id, reported_id, reason, details) values (me, p_user, p_reason, nullif(btrim(p_details), ''));
  for admin in select user_id from public.admin_users loop
    perform public.notify(admin.user_id, 'report', 'New player report', 'Reason: {reason}. Review it within 24 hours.', '/app/admin/',
      jsonb_build_object('reason', p_reason));
  end loop;
end
$$;

-- 管理员的举报队列：被举报的人、原因、说明，以及他最近 30 天在举报人看得到的会话里发的消息（最多 20 条）
create function public.admin_report_queue()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'reason', r.reason, 'details', r.details, 'created_at', r.created_at,
      'reporter', jsonb_build_object('id', rp.id, 'nickname', rp.nickname),
      'reported', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'avatar', p.avatar_path,
                                     'suspended', coalesce(u.banned_until > now(), false)),
      'open_reports', (select count(*) from public.user_reports x where x.reported_id = r.reported_id and x.resolved_at is null),
      'messages', (select coalesce(jsonb_agg(jsonb_build_object('body', m.body, 'at', m.created_at) order by m.created_at desc), '[]')
                   from (select m.body, m.created_at from public.messages m
                         where m.sender_id = r.reported_id and m.created_at > now() - interval '30 days'
                           and (m.thread = 'dm:' || least(r.reporter_id, r.reported_id) || ':' || greatest(r.reporter_id, r.reported_id)
                                or (m.thread ~ '^(game|group):'
                                    and public.thread_access(split_part(m.thread, ':', 1), split_part(m.thread, ':', 2)::uuid, r.reporter_id) is not null))
                         order by m.created_at desc limit 20) m)
    ) order by r.created_at, r.id)
    from public.user_reports r
    join public.profiles p on p.id = r.reported_id
    join public.profiles rp on rp.id = r.reporter_id
    join auth.users u on u.id = r.reported_id
    where r.resolved_at is null), '[]'::jsonb);
end
$$;

-- 处理举报：dismiss 只结这一条；其余（改掉昵称、撤下照片、封号）会把这个人所有没处理的举报一起结案。
-- 封号：登录不了（已登录的最多 1 小时后失效），在找的约球取消，开着的局关掉。都记进审核日志
create function public.admin_resolve_report(p_report bigint, p_action text, p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.user_reports;
  room record;
begin
  perform public.require_admin();
  select * into r from public.user_reports where id = p_report and resolved_at is null for update;
  if r.id is null then raise exception 'request_not_found' using errcode = 'P0002'; end if;
  if p_action not in ('dismiss', 'reset_nickname', 'clear_avatar', 'suspend')
     or (p_action = 'suspend' and (r.reported_id = auth.uid() or exists (select 1 from public.admin_users where user_id = r.reported_id))) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;

  if p_action = 'reset_nickname' then
    update public.profiles set nickname = 'Player ' || upper(left(replace(r.reported_id::text, '-', ''), 4)) where id = r.reported_id;
  elsif p_action = 'clear_avatar' then
    update public.profiles set avatar_path = null where id = r.reported_id;
  elsif p_action = 'suspend' then
    update auth.users set banned_until = now() + interval '100 years' where id = r.reported_id;
    delete from auth.sessions where user_id = r.reported_id;
    update public.match_tickets set status = 'cancelled' where user_id = r.reported_id and status in ('searching', 'paused');
    for room in select id from public.rooms where owner_id = r.reported_id and status = 'open' loop
      perform public.close_room(room.id, 'owner_closed');
    end loop;
  end if;

  update public.user_reports set resolved_at = now()
    where case when p_action = 'dismiss' then id = r.id else reported_id = r.reported_id and resolved_at is null end;
  insert into public.moderation_log (admin_id, target_type, target_id, action, note)
    values (auth.uid(), 'user', r.reported_id::text, p_action, left(coalesce(p_note, ''), 500));
end
$$;
revoke execute on function public.admin_report_queue(), public.admin_resolve_report(bigint, text, text) from public, anon;
grant execute on function public.admin_report_queue(), public.admin_resolve_report(bigint, text, text) to authenticated;
