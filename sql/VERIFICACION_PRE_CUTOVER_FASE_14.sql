-- ============================================================
-- LIHEN.CO — FASE 14
-- Verificación PRE-CUTOVER (solo lectura)
-- Ejecutar ANTES de 039..044 en preproducción/producción.
-- No modifica datos.
-- ============================================================

-- 1) Confirmar versión/esquema esperado de tablas clave.
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name = any (array[
    'products','inventory','product_variants','product_images',
    'suppliers','supplier_products','inventory_movements',
    'import_batches','import_batch_rows'
  ])
order by table_name;

-- 2) Comprobar duplicados de SKU no nulos.
select sku, count(*) as duplicates
from public.products
where sku is not null and btrim(sku) <> ''
group by sku
having count(*) > 1;

-- 3) Comprobar duplicados de catalog_code no nulos.
select catalog_code, count(*) as duplicates
from public.products
where catalog_code is not null and btrim(catalog_code) <> ''
group by catalog_code
having count(*) > 1;

-- 4) Inconsistencias actuales de inventario.
select id, product_id, variant_id,
       physical_stock, reserved_stock, available_stock, pending_stock
from public.inventory
where physical_stock < 0
   or reserved_stock < 0
   or pending_stock < 0
   or reserved_stock > physical_stock
order by product_id, variant_id nulls first;

-- 5) Variantes de inventario asociadas a producto incorrecto o inexistente.
select i.id as inventory_id,
       i.product_id as inventory_product_id,
       i.variant_id,
       pv.product_id as variant_product_id
from public.inventory i
left join public.product_variants pv on pv.id = i.variant_id
where i.variant_id is not null
  and (pv.id is null or pv.product_id is distinct from i.product_id);

-- 6) Cantidad de productos según visibilidad/estado.
select status, visible_on_website, count(*) as total
from public.products
group by status, visible_on_website
order by status, visible_on_website;

-- 7) Productos activos + visibles sin imagen utilizable.
select p.id, p.sku, p.name, p.main_image_url
from public.products p
where p.status = 'activo'
  and p.visible_on_website = true
  and coalesce(nullif(btrim(p.main_image_url), ''), '') = ''
  and not exists (
    select 1
    from public.product_images pi
    where pi.product_id = p.id
      and coalesce(nullif(btrim(pi.public_url), ''), nullif(btrim(pi.storage_path), '')) is not null
  )
order by p.sku nulls last, p.name;

-- 8) Productos activos + visibles con precio nulo/negativo.
select id, sku, name, sale_price
from public.products
where status = 'activo'
  and visible_on_website = true
  and (sale_price is null or sale_price < 0)
order by sku nulls last, name;

-- 9) Inventario general + por variante simultáneo (diagnóstico de posible doble fuente).
select p.id, p.sku, p.name,
       bool_or(i.variant_id is null) as has_product_inventory,
       bool_or(i.variant_id is not null) as has_variant_inventory,
       count(*) as inventory_rows
from public.products p
join public.inventory i on i.product_id = p.id
group by p.id, p.sku, p.name
having bool_or(i.variant_id is null) and bool_or(i.variant_id is not null)
order by p.sku nulls last, p.name;

-- 10) Snapshot de conteos para comparación post-cutover.
select
  (select count(*) from public.products) as products,
  (select count(*) from public.inventory) as inventory_rows,
  (select count(*) from public.product_variants) as variants,
  (select count(*) from public.product_images) as images,
  (select count(*) from public.inventory_movements) as inventory_movements;
