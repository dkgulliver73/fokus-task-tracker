-- Keep open Library views synchronized across the user's devices.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'library_items'
  ) then
    alter publication supabase_realtime add table public.library_items;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'library_projects'
  ) then
    alter publication supabase_realtime add table public.library_projects;
  end if;
end
$$;
