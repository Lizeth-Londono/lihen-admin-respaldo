-- LIHEN.CO - Monitoreo operativo post-cutover
-- Solo lectura. No modifica datos.
-- Ejecutar después del despliegue y ante incidentes de catálogo/inventario.

-- 1. Resumen de productos e inventario
select
  count(*) filter (where p.status = 'activo') as productos_activos,
  count(*) filter (where p.status = 'activo' and p.visible_on_website is true) as productos_publicables,
  count(*) filter (where coalesce(i.available_stock, 0) > 0) as productos_con_stock,
  count(*) filter (where coalesce(i.available_stock, 0) <= 0) as productos_sin_stock
from public.products p
left join (
  select product_id, sum(available_stock) as available_stock
  from public.inventory
  group by product_id
) i on i.product_id = p.id;

-- 2. Productos activos/visibles con problemas comerciales básicos
select
  p.id,
  p.sku,
  p.name,
  p.sale_price,
  p.status,
  p.visible_on_website,
  p.main_image_url
from public.products p
where p.status = 'activo'
  and p.visible_on_website is true
  and (
    p.sale_price is null
    or p.sale_price < 0
    or nullif(trim(coalesce(p.name, '')), '') is null
  )
order by p.sku nulls last;

-- 3. Inconsistencias de inventario
select
  id,
  product_id,
  variant_id,
  physical_stock,
  reserved_stock,
  available_stock,
  pending_stock
from public.inventory
where physical_stock < 0
   or reserved_stock < 0
   or pending_stock < 0
   or reserved_stock > physical_stock
   or available_stock < 0;

-- 4. Variantes de inventario que no pertenecen al producto
select
  i.id as inventory_id,
  i.product_id as inventory_product_id,
  i.variant_id,
  pv.product_id as variant_product_id
from public.inventory i
join public.product_variants pv on pv.id = i.variant_id
where i.variant_id is not null
  and i.product_id <> pv.product_id;

-- 5. Duplicados de SKU
select sku, count(*)
from public.products
where nullif(trim(coalesce(sku, '')), '') is not null
group by sku
having count(*) > 1;

-- 6. Duplicados de codigo de catalogo
select catalog_code, count(*)
from public.products
where nullif(trim(coalesce(catalog_code, '')), '') is not null
group by catalog_code
having count(*) > 1;

-- 7. Vista publica: distribución de disponibilidad
select
  availability_status,
  availability_text,
  count(*) as total
from public.catalog_public
group by availability_status, availability_text
order by availability_status;

-- 8. Muestra de catalogo publico
select
  id,
  sku,
  catalog_code,
  name,
  brand,
  business_line,
  category,
  subcategory,
  sale_price,
  availability_status,
  availability_text,
  main_image_url
from public.catalog_public
order by name
limit 50;

-- 9. Verificar que catalog_public no exponga columnas sensibles
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'catalog_public'
  and column_name in (
    'current_cost',
    'minimum_stock',
    'reserved_stock',
    'pending_stock',
    'available_stock',
    'average_cost',
    'supplier_id',
    'supplier_name'
  );

-- Resultado esperado de la consulta 9: 0 filas.

-- 10. Últimos movimientos de inventario para auditoría operativa
select
  created_at,
  product_id,
  variant_id,
  movement_type,
  quantity,
  physical_before,
  physical_after,
  reserved_before,
  reserved_after,
  reason
from public.inventory_movements
order by created_at desc
limit 100;

-- 11. Últimos lotes de importación
select
  id,
  operation_key,
  status,
  total_rows,
  actionable_rows,
  unchanged_rows,
  pending_supplier_links,
  created_at,
  completed_at
from public.import_batches
order by created_at desc
limit 20;

-- 12. Filas recientes de importación con cambios trazados
select
  batch_id,
  row_number,
  sku,
  action,
  changes
from public.import_batch_rows
order by created_at desc
limit 100;
