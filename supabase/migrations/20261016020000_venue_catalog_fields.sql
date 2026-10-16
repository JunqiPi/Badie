-- 随 App 打包的场馆目录导入数据库时需要的字段

-- 原始数据只有地址没有坐标（韩国），位置是区中心，App 用 Apple 地图核对后才显示
alter table public.venues add column location_approximate boolean not null default false;

comment on column public.venues.pricing is '{"perPerson": 15, "perCourtHour": 38}，没有的键省略';

-- 用户添加时仍限 60 字（add_venue 里检查）；官方数据里有更长的正式名称
alter table public.venues drop constraint venues_name_check;
alter table public.venues add constraint venues_name_check check (char_length(name) between 2 and 120);
