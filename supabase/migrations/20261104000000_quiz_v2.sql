-- 定级问卷重新标定（选项分值和算法都改了，旧版太松）：已经做过问卷的人可以马上重做一次，不用等 90 天
update public.profiles set assessed_at = now() - interval '91 days'
  where assessed_at > now() - interval '90 days';
