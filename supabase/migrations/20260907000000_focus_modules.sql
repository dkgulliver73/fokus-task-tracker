-- Focus modules: CodeBridge library and client-encrypted credential vault.
-- Vault secrets must be encrypted in the browser before they reach Supabase.

create extension if not exists pgcrypto;

create table if not exists public.library_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  description text not null default '',
  content text not null default '',
  language text not null default 'text' check (char_length(language) between 1 and 40),
  tags text[] not null default '{}',
  project_label text not null default '' check (char_length(project_label) <= 100),
  link_url text not null default '' check (char_length(link_url) <= 2048),
  image_paths text[] not null default '{}',
  is_favorite boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint library_items_tags_limit check (cardinality(tags) <= 50),
  constraint library_items_images_limit check (cardinality(image_paths) <= 20)
);

create table if not exists public.vault_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  version integer not null default 1,
  kdf jsonb not null,
  wrapped_key jsonb not null,
  verifier jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vault_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  version integer not null default 1,
  envelope jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint vault_items_envelope_object check (jsonb_typeof(envelope) = 'object')
);

comment on table public.vault_items is
  'Zero-knowledge vault records. Service names, logins, passwords, URLs, categories and notes belong inside ciphertext.';
comment on table public.vault_profiles is
  'Per-user encrypted DEK envelope. The master password and plaintext DEK never leave the browser.';
comment on column public.vault_items.envelope is
  'AES-GCM envelope containing only IV and authenticated ciphertext.';

create index if not exists library_items_user_updated_idx
  on public.library_items (user_id, updated_at desc);
create index if not exists library_items_user_active_idx
  on public.library_items (user_id, sort_order, updated_at desc)
  where deleted_at is null;
create index if not exists library_items_user_project_idx
  on public.library_items (user_id, project_label)
  where deleted_at is null;
create index if not exists library_items_tags_gin_idx
  on public.library_items using gin (tags);

create index if not exists vault_items_user_updated_idx
  on public.vault_items (user_id, updated_at desc);
create index if not exists vault_items_user_active_idx
  on public.vault_items (user_id, updated_at desc)
  where deleted_at is null;

create or replace function public.set_focus_modules_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists library_items_set_updated_at on public.library_items;
create trigger library_items_set_updated_at
before update on public.library_items
for each row execute function public.set_focus_modules_updated_at();

drop trigger if exists vault_items_set_updated_at on public.vault_items;
create trigger vault_items_set_updated_at
before update on public.vault_items
for each row execute function public.set_focus_modules_updated_at();

drop trigger if exists vault_profiles_set_updated_at on public.vault_profiles;
create trigger vault_profiles_set_updated_at
before update on public.vault_profiles
for each row execute function public.set_focus_modules_updated_at();

alter table public.library_items enable row level security;
alter table public.library_items force row level security;
alter table public.vault_items enable row level security;
alter table public.vault_items force row level security;
alter table public.vault_profiles enable row level security;
alter table public.vault_profiles force row level security;

revoke all on table public.library_items from anon;
revoke all on table public.vault_items from anon;
revoke all on table public.vault_profiles from anon;
grant select, insert, update, delete on table public.library_items to authenticated;
grant select, insert, update, delete on table public.vault_items to authenticated;
grant select, insert, update, delete on table public.vault_profiles to authenticated;

drop policy if exists "vault_profiles_owner_all" on public.vault_profiles;
create policy "vault_profiles_owner_all"
on public.vault_profiles for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "library_items_select_own" on public.library_items;
create policy "library_items_select_own"
on public.library_items for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "library_items_insert_own" on public.library_items;
create policy "library_items_insert_own"
on public.library_items for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "library_items_update_own" on public.library_items;
create policy "library_items_update_own"
on public.library_items for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "library_items_delete_own" on public.library_items;
create policy "library_items_delete_own"
on public.library_items for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "vault_items_select_own" on public.vault_items;
create policy "vault_items_select_own"
on public.vault_items for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "vault_items_insert_own" on public.vault_items;
create policy "vault_items_insert_own"
on public.vault_items for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "vault_items_update_own" on public.vault_items;
create policy "vault_items_update_own"
on public.vault_items for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "vault_items_delete_own" on public.vault_items;
create policy "vault_items_delete_own"
on public.vault_items for delete
to authenticated
using ((select auth.uid()) = user_id);
