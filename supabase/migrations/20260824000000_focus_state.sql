create table if not exists public.focus_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.focus_state enable row level security;

grant select, insert, update on table public.focus_state to authenticated;

create policy "Users can read their own Focus state"
on public.focus_state for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can insert their own Focus state"
on public.focus_state for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can update their own Focus state"
on public.focus_state for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create or replace function public.set_focus_state_updated_at()
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

drop trigger if exists focus_state_updated_at on public.focus_state;
create trigger focus_state_updated_at
before update on public.focus_state
for each row execute function public.set_focus_state_updated_at();
