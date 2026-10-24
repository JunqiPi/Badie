-- 新用户的默认设置：谁都可以发起挑战，在常去球馆显示为常客（约球邮件仍默认关）。已有用户的设置不变
alter table public.profiles
  alter column challenge_policy set default 'everyone',
  alter column show_as_regular set default true;
