-- 不是所有能打球的地方都是羽毛球馆：社区中心、学校、教会的体育馆只在固定时段开放羽毛球
create type public.venue_kind as enum ('dedicated', 'multi_sport', 'rec_center', 'school', 'community_hall');

alter table public.venues
  add column kind public.venue_kind,
  add column play_times text check (play_times is null or char_length(play_times) <= 200),
  -- 官方目录最后一次人工核实的日期
  add column checked_on date;
