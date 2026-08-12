-- ============================================================
-- LIHEN.CO — FASE 14
-- Verificación POST-CUTOVER
-- Ejecutar DESPUÉS de 039..044.
-- Algunas pruebas deben ejecutarse además desde la WEB con Publishable Key.
-- ============================================================

-- A) Contrato de catalog_public.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_public'
order by ordinal_position;

-- B) Confirmar que no aparezcan columnas privadas.
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_public'
  and lower(column_name) = any (array[
    'current_cost','minimum_stock','reserved_stock','pending_stock',
    'available_stock','average_cost','supplier_id','supplier_name',
    'created_by','updated_by'
  ]);

-- Debe devolver 0 filas.

-- C) Conteo público esperado.
select count(*) as public_products
from public.catalog_public;

-- D) Verificación de muestra pública.
select id, sku, catalog_code, name, brand, sale_price,
       availability_status, availability_text,
       main_image_url, variants, images
from public.catalog_public
order by sku nulls last, name
limit 20;

-- E) Comparación de disponibilidad calculada contra inventory.
-- Solo diagnóstico con rol administrativo.
with variant_inventory as (
  select product_id, sum(greatest(0, available_stock))::bigint as available
  from public.inventory
  where variant_id is not null
  group by product_id
),
product_inventory as (
  select product_id, max(greatest(0, available_stock))::bigint as available
  from public.inventory
  where variant_id is null
  group by product_id
),
expected as (
  select p.id,
         case
           when vi.product_id is not null then coalesce(vi.available, 0)
           else coalesce(pi.available, 0)
         end as available
  from public.products p
  left join variant_inventory vi on vi.product_id = p.id
  left join product_inventory pi on pi.product_id = p.id
  where p.status = 'activo' and p.visible_on_website = true
)
select cp.id, cp.sku, cp.name,
       cp.availability_status,
       e.available as expected_available
from public.catalog_public cp
join expected e on e.id = cp.id
where (e.available > 0 and cp.availability_status <> 'available')
   or (e.available <= 0 and cp.availability_status <> 'out_of_stock');

-- Debe devolver 0 filas.

-- F) Verificar grants efectivos de objetos clave.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = any (array[
    'catalog_public','products','inventory','product_variants',
    'product_images','suppliers','supplier_products','inventory_movements'
  ])
  and grantee in ('anon','authenticated')
order by table_name, grantee, privilege_type;

-- G) Validar funciones nuevas/actualizadas presentes.
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name = any (array[
    'create_product_atomic',
    'adjust_inventory_atomic',
    'import_inventory_batch_atomic'
  ])
order by routine_name;

-- H) Diagnóstico de constraints de Fases 7–8 antes de VALIDATE CONSTRAINT.
select id, product_id, variant_id,
       physical_stock, reserved_stock, pending_stock
from public.inventory
where physical_stock < 0
   or reserved_stock < 0
   or pending_stock < 0
   or reserved_stock > physical_stock;

-- I) Smoke test de catálogo activo/visible con stock 0 y >0.
select availability_status, count(*)
from public.catalog_public
group by availability_status
order by availability_status;

-- J) PRUEBAS DESDE LA WEB/PUBLISHABLE KEY (no SQL administrativo):
--   1. SELECT catalog_public limit 1       -> DEBE FUNCIONAR.
--   2. SELECT products limit 1             -> DEBE FALLAR.
--   3. SELECT inventory limit 1            -> DEBE FALLAR.
--   4. Cambiar precio en ADMIN y recargar WEB -> nuevo precio sin redeploy.
--   5. Cambiar visible_on_website true/false  -> aparece/desaparece.
--   6. Cambiar stock a 0/>0                  -> Agotado/Disponible.
