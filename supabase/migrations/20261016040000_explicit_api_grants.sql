-- 显式授权：不依赖项目“新表自动开放给 API”的设置。能看哪一行仍由 RLS 决定
grant usage on schema public to anon, authenticated;

grant select on public.venues to anon, authenticated;
grant select on public.venue_regular_counts to anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.venue_confirmations, public.venue_reports, public.moderation_log to authenticated;
grant select, insert, delete on public.favorite_venues to authenticated;

grant execute on function public.venues_near(double precision, double precision, double precision, int) to anon, authenticated;
grant execute on function public.venue_duplicates(text, double precision, double precision, text, text[]) to anon, authenticated;
grant execute on function public.normalize_venue_name(text), public.venue_name_core(text),
  public.venue_names_similar(text, text) to anon, authenticated;
