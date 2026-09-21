-- User-managed ordering for encrypted Vault cards. Ordering metadata remains
-- outside the AES-GCM envelope, so moving a card never rewrites its secrets.

alter table public.vault_items
  add column if not exists sort_order bigint;

-- Vault content edits retain the existing updated_at semantics. A sort-only
-- write is technical metadata and therefore preserves the old timestamp.
create or replace function public.set_vault_items_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.sort_order is distinct from old.sort_order
    and new.envelope is not distinct from old.envelope
    and new.user_id is not distinct from old.user_id
    and new.version is not distinct from old.version
    and new.created_at is not distinct from old.created_at
    and new.deleted_at is not distinct from old.deleted_at then
    new.updated_at = old.updated_at;
  else
    new.updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists vault_items_set_updated_at on public.vault_items;
create trigger vault_items_set_updated_at
before update on public.vault_items
for each row execute function public.set_vault_items_updated_at();

-- Preserve the legacy order for active cards, independently per user. UUID is
-- only a deterministic tie breaker for equal legacy timestamps.
with ranked_active as (
  select id,
    row_number() over (
      partition by user_id
      order by updated_at desc, id asc
    ) - 1 as position
  from public.vault_items
  where deleted_at is null
    and sort_order is null
)
update public.vault_items as item
set sort_order = ranked_active.position
from ranked_active
where item.id = ranked_active.id;

-- Deleted cards are not part of the active sequence. They only receive a
-- non-null technical value so the column can be made NOT NULL safely.
update public.vault_items
set sort_order = 0
where deleted_at is not null
  and sort_order is null;

alter table public.vault_items
  alter column sort_order set default 0,
  alter column sort_order set not null;

create index if not exists vault_items_user_active_order_idx
  on public.vault_items (user_id, sort_order, updated_at desc, id)
  where deleted_at is null;

-- A full sequence is validated before one set-based UPDATE. PostgreSQL runs a
-- function call atomically, so a validation or update error preserves the old
-- order entirely.
create or replace function public.reorder_vault_items(p_items jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  payload_count integer;
  active_count integer;
  matching_count integer;
  distinct_id_count integer;
  distinct_position_count integer;
  min_position bigint;
  max_position bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'Order payload must be an array';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_items) as entry(value)
    where pg_catalog.jsonb_typeof(value) <> 'object'
      or pg_catalog.jsonb_typeof(value -> 'id') <> 'string'
      or pg_catalog.jsonb_typeof(value -> 'sort_order') <> 'number'
      or (value ->> 'sort_order') !~ '^(0|[1-9][0-9]*)$'
  ) then
    raise exception 'Order payload contains an invalid item';
  end if;

  with payload as (
    select (value ->> 'id')::uuid as id,
      (value ->> 'sort_order')::bigint as sort_order
    from pg_catalog.jsonb_array_elements(p_items) as entry(value)
  )
  select count(*), count(distinct id), count(distinct sort_order),
    min(sort_order), max(sort_order)
  into payload_count, distinct_id_count, distinct_position_count,
    min_position, max_position
  from payload;

  if payload_count <> distinct_id_count
    or payload_count <> distinct_position_count
    or (payload_count > 0 and (min_position <> 0 or max_position <> payload_count - 1)) then
    raise exception 'Order payload must contain one complete sequence';
  end if;

  select count(*) into active_count
  from public.vault_items
  where user_id = auth.uid()
    and deleted_at is null;

  if payload_count <> active_count then
    raise exception 'Order payload does not include every active Vault item';
  end if;

  with payload as (
    select (value ->> 'id')::uuid as id
    from pg_catalog.jsonb_array_elements(p_items) as entry(value)
  )
  select count(*) into matching_count
  from payload
  join public.vault_items as item
    on item.id = payload.id
   and item.user_id = auth.uid()
   and item.deleted_at is null;

  if matching_count <> payload_count then
    raise exception 'Order payload contains an inaccessible Vault item';
  end if;

  update public.vault_items as item
  set sort_order = payload.sort_order
  from (
    select (value ->> 'id')::uuid as id,
      (value ->> 'sort_order')::bigint as sort_order
    from pg_catalog.jsonb_array_elements(p_items) as entry(value)
  ) as payload
  where item.id = payload.id
    and item.user_id = auth.uid()
    and item.deleted_at is null;
end;
$$;

revoke all on function public.reorder_vault_items(jsonb) from public;
grant execute on function public.reorder_vault_items(jsonb) to authenticated;

comment on column public.vault_items.sort_order is
  'Non-secret, user-managed Vault card position. It is independent of the encrypted envelope and updated_at.';
