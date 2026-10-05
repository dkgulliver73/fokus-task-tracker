-- Infrastructure-only row for a read-only external Supabase keep-alive.
-- This table intentionally contains no user, product, or encrypted data.

create table public.app_heartbeat (
  id smallint primary key default 1 check (id = 1),
  name text not null unique check (name = 'focus')
);

insert into public.app_heartbeat (id, name)
values (1, 'focus');

alter table public.app_heartbeat enable row level security;

revoke all on table public.app_heartbeat from public;
revoke all on table public.app_heartbeat from anon;
revoke all on table public.app_heartbeat from authenticated;
grant select on table public.app_heartbeat to anon;

create policy "app_heartbeat_anon_select_focus"
on public.app_heartbeat for select
to anon
using (name = 'focus');
