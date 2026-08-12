-- ============================================================
-- LIHEN.CO — FASE 21
-- SMOKE TEST DE PRODUCCIÓN / PREPRODUCCIÓN
-- SOLO LECTURA. NO MODIFICA DATOS.
-- Ejecutar DESPUÉS de aplicar migraciones 039–044.
-- ============================================================

-- 1) Confirmar existencia de catalog_public.
select
  to_regclass('public.catalog_public') as catalog_public;

-- 2) Confirmar columnas públicas reales.
select
  column_name,
  data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_public'
order by ordinal_position;

-- 3) Bloque de detección de columnas sensibles.
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_public'
  and lower(column_name) in (
    'current_cost',
    'minimum_stock',
    'reserved_stock',
    'pending_stock',
    'available_stock',
    'average_cost',
    'supplier_id',
    'supplier_name'
  );

-- Resultado esperado: 0 filas.

-- 4) Resumen de productos públicos.
select
  count(*) as total_publicos,
  count(*) filter (where availability_status = 'available') as disponibles,
  count(*) filter (where availability_status = 'out_of_stock') as agotados
from public.catalog_public;

-- 5) Muestra de contrato público.
select
  id,
  sku,
  catalog_code,
  name,
  brand,
  sale_price,
  availability_status,
  availability_text,
  main_image_url,
  variants,
  images
from public.catalog_public
order by name
limit 20;

-- 6) Productos administrativos marcados para publicar que NO aparecen en la vista.
select
  p.id,
  p.sku,
  p.name,
  p.status,
  p.visible_on_website
from public.products p
left join public.catalog_public c on c.id = p.id
where p.status = 'activo'
  and p.visible_on_website = true
  and c.id is null
order by p.name;

-- Resultado esperado: 0 filas.

-- 7) Comprobar disponibilidad calculada contra inventario.
with variant_inventory as (
  select
    product_id,
    sum(greatest(0, coalesce(available_stock, 0)))::bigint as available_stock
  from public.inventory
  where variant_id is not null
  group by product_id
),
product_inventory as (
  select
    product_id,
    max(greatest(0, coalesce(available_stock, 0)))::bigint as available_stock
  from public.inventory
  where variant_id is null
  group by product_id
),
expected as (
  select
    p.id,
    case
      when vi.product_id is not null then coalesce(vi.available_stock, 0)
      else coalesce(pi.available_stock, 0)
    end::bigint as available_stock
  from public.products p
  left join variant_inventory vi on vi.product_id = p.id
  left join product_inventory pi on pi.product_id = p.id
)
select
  c.sku,
  c.name,
  e.available_stock as internal_available_stock,
  c.availability_status,
  c.availability_text
from public.catalog_public c
join expected e on e.id = c.id
where
  (e.available_stock > 0 and c.availability_status <> 'available')
  or
  (e.available_stock <= 0 and c.availability_status <> 'out_of_stock');

-- Resultado esperado: 0 filas.

-- 8) Inventario inconsistente.
select
  id,
  product_id,
  variant_id,
  physical_stock,
  reserved_stock,
  available_stock,
  pending_stock
from public.inventory
where coalesce(physical_stock, 0) < 0
   or coalesce(reserved_stock, 0) < 0
   or coalesce(pending_stock, 0) < 0
   or coalesce(reserved_stock, 0) > coalesce(physical_stock, 0);

-- Resultado esperado: 0 filas.

-- 9) SKU duplicados.
select
  lower(trim(sku)) as normalized_sku,
  count(*) as total
from public.products
where nullif(trim(sku), '') is not null
group by lower(trim(sku))
having count(*) > 1;

-- Resultado esperado: 0 filas.

-- 10) Códigos catálogo duplicados.
select
  lower(trim(catalog_code)) as normalized_catalog_code,
  count(*) as total
from public.products
where nullif(trim(catalog_code), '') is not null
group by lower(trim(catalog_code))
having count(*) > 1;

-- Resultado esperado: 0 filas.

-- 11) Verificar grants de catalog_public.
select
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'catalog_public'
order by grantee, privilege_type;

-- Debe existir SELECT para anon/authenticated.
-- No debe existir INSERT/UPDATE/DELETE.

-- 12) Grants directos peligrosos sobre tablas administrativas.
select
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'products',
    'inventory',
    'suppliers',
    'supplier_products',
    'inventory_movements'
  )
  and grantee = 'anon'
order by table_name, privilege_type;

-- Resultado esperado: 0 filas.

-- 13) Verificar RPC críticas.
select
  routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'create_product_atomic',
    'adjust_inventory_atomic',
    'import_inventory_batch_atomic'
  )
order by routine_name;

-- Resultado esperado: las 3 RPC.

-- 14) Últimos movimientos.
-- V9: inventory_movements referencia inventory mediante inventory_id.
-- Se obtiene product_id/variant_id haciendo JOIN con public.inventory.
select
  im.created_at,
  i.product_id,
  i.variant_id,
  im.movement_type,
  im.quantity,
  im.physical_before,
  im.physical_after,
  im.reserved_before,
  im.reserved_after,
  im.reason
from public.inventory_movements im
left join public.inventory i on i.id = im.inventory_id
order by im.created_at desc
limit 20;

-- 15) Últimas importaciones.
-- V9: el esquema real usa skipped_rows. Las filas accionables se derivan.
select
  id,
  created_at,
  status,
  total_rows,
  greatest(coalesce(total_rows, 0) - coalesce(skipped_rows, 0), 0) as actionable_rows,
  coalesce(skipped_rows, 0) as unchanged_rows,
  operation_key,
  source_file
from public.import_batches
order by created_at desc
limit 10;

-- ============================================================
-- INTERPRETACIÓN
-- Si los bloques marcados "Resultado esperado: 0 filas"
-- devuelven registros, NO activar CATALOG_SOURCE=supabase
-- hasta revisar el problema.
-- ============================================================
