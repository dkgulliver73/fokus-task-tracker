-- Focus library projects and private image attachments.
-- Safe to run repeatedly after 20260907000000_focus_modules.sql.

create extension if not exists pgcrypto;

create table if not exists public.library_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint library_projects_user_name_unique unique (user_id, name),
  constraint library_projects_id_user_unique unique (id, user_id)
);

create index if not exists library_projects_user_sort_idx
  on public.library_projects (user_id, sort_order, created_at);

drop trigger if exists library_projects_set_updated_at on public.library_projects;
create trigger library_projects_set_updated_at
before update on public.library_projects
for each row execute function public.set_focus_modules_updated_at();

alter table public.library_projects enable row level security;
alter table public.library_projects force row level security;

revoke all on table public.library_projects from anon;
grant select, insert, update, delete on table public.library_projects to authenticated;

drop policy if exists "library_projects_select_own" on public.library_projects;
create policy "library_projects_select_own"
on public.library_projects for select
using (user_id = (select auth.uid()));

drop policy if exists "library_projects_insert_own" on public.library_projects;
create policy "library_projects_insert_own"
on public.library_projects for insert
with check (user_id = (select auth.uid()));

drop policy if exists "library_projects_update_own" on public.library_projects;
create policy "library_projects_update_own"
on public.library_projects for update
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "library_projects_delete_own" on public.library_projects;
create policy "library_projects_delete_own"
on public.library_projects for delete
using (user_id = (select auth.uid()));

alter table public.library_items
  add column if not exists project_id uuid;

-- Preserve every existing text project label as a real project. Empty labels
-- are grouped into one explicit fallback so project_id can become required.
insert into public.library_projects (user_id, name)
select distinct
  item.user_id,
  case
    when btrim(coalesce(item.project_label, '')) = '' then 'Без проекта'
    else left(btrim(item.project_label), 80)
  end
from public.library_items item
where item.project_id is null
on conflict (user_id, name) do nothing;

update public.library_items item
set project_id = project.id
from public.library_projects project
where item.project_id is null
  and project.user_id = item.user_id
  and project.name = case
    when btrim(coalesce(item.project_label, '')) = '' then 'Без проекта'
    else left(btrim(item.project_label), 80)
  end;

alter table public.library_items
  alter column project_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'library_items_project_owner_fk'
      and conrelid = 'public.library_items'::regclass
  ) then
    alter table public.library_items
      add constraint library_items_project_owner_fk
      foreign key (project_id, user_id)
      references public.library_projects (id, user_id)
      on delete cascade;
  end if;
end
$$;

create index if not exists library_items_project_id_idx
  on public.library_items (project_id, updated_at desc);

-- The application keeps the original CodeBridge limit of ten images per card.
-- The existing, slightly wider database limit is intentionally preserved so
-- this migration cannot fail on previously imported rows.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'focus-library-images',
  'focus-library-images',
  false,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/heic', 'image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "focus_library_images_select_own" on storage.objects;
create policy "focus_library_images_select_own"
on storage.objects for select
using (
  bucket_id = 'focus-library-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "focus_library_images_insert_own" on storage.objects;
create policy "focus_library_images_insert_own"
on storage.objects for insert
with check (
  bucket_id = 'focus-library-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "focus_library_images_update_own" on storage.objects;
create policy "focus_library_images_update_own"
on storage.objects for update
using (
  bucket_id = 'focus-library-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'focus-library-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "focus_library_images_delete_own" on storage.objects;
create policy "focus_library_images_delete_own"
on storage.objects for delete
using (
  bucket_id = 'focus-library-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
