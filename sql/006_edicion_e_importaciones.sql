-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 006
-- Edición, control de duplicados e historial de importaciones
-- Ejecutar una sola vez en Supabase SQL Editor.
-- ============================================================
begin;

alter table public.customers
  add column if not exists active boolean not null default true;

-- Los índices parciales permiten varios NULL, pero no códigos repetidos.
create unique index if not exists products_sku_unique_not_null
  on public.products (lower(trim(sku)))
  where sku is not null and trim(sku) <> '';

create unique index if not exists products_catalog_code_unique_not_null
  on public.products (lower(trim(catalog_code)))
  where catalog_code is not null and trim(catalog_code) <> '';

create unique index if not exists customers_whatsapp_unique_not_null
  on public.customers (regexp_replace(whatsapp, '[^0-9]', '', 'g'))
  where whatsapp is not null and trim(whatsapp) <> '';

create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  import_type text not null check (import_type in ('inventario','productos','proveedores','clientes','catalogo')),
  source_file text,
  status text not null default 'completado',
  total_rows integer not null default 0,
  created_rows integer not null default 0,
  updated_rows integer not null default 0,
  skipped_rows integer not null default 0,
  error_rows integer not null default 0,
  summary jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.import_batches enable row level security;

drop policy if exists "cofundadoras_consultan_importaciones" on public.import_batches;
create policy "cofundadoras_consultan_importaciones"
on public.import_batches for select to authenticated
using (public.is_active_cofounder());

drop policy if exists "cofundadoras_crean_importaciones" on public.import_batches;
create policy "cofundadoras_crean_importaciones"
on public.import_batches for insert to authenticated
with check (public.is_active_cofounder() and created_by = auth.uid());

grant select, insert on public.import_batches to authenticated;

commit;
