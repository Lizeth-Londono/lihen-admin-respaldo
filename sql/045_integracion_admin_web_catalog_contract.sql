-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 045
-- Contrato canónico ADMIN -> catalog_public -> LIHEN WEB.
-- Ejecutar después de 044_seguridad_catalogo_publico_fase_12.sql.
--
-- Objetivos:
-- 1) Supabase queda como fuente única de verdad del catálogo dinámico.
-- 2) catalog_public publica solo productos activos, habilitados para web y con foto válida.
-- 3) La disponibilidad se deriva de inventory sin exponer cantidades internas.
-- 4) anon conserva acceso únicamente a catalog_public.
-- ============================================================

begin;

-- PostgreSQL no permite cambiar libremente el contrato de una VIEW existente
-- con CREATE OR REPLACE, por lo que se recrea dentro de la misma transacción.
drop view if exists public.catalog_public;

create view public.catalog_public as
with variant_inventory as (
  select
    i.product_id,
    sum(greatest(0, coalesce(i.available_stock, 0)))::bigint as available_stock
  from public.inventory i
  where i.variant_id is not null
  group by i.product_id
),
product_inventory as (
  select
    i.product_id,
    max(greatest(0, coalesce(i.available_stock, 0)))::bigint as available_stock
  from public.inventory i
  where i.variant_id is null
  group by i.product_id
),
inventory_public as (
  select
    p.id as product_id,
    case
      when vi.product_id is not null then coalesce(vi.available_stock, 0)
      else coalesce(pi.available_stock, 0)
    end::bigint as available_stock
  from public.products p
  left join variant_inventory vi on vi.product_id = p.id
  left join product_inventory pi on pi.product_id = p.id
),
variants_public as (
  select
    pv.product_id,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', pv.id,
          'size', pv.size,
          'color', pv.color,
          'tone', pv.tone,
          'presentation', pv.presentation,
          'additional_price', pv.additional_price
        ) order by pv.created_at, pv.id
      ) filter (where pv.id is not null and pv.active = true),
      '[]'::jsonb
    ) as variants
  from public.product_variants pv
  where pv.active = true
  group by pv.product_id
),
images_public as (
  select
    pi.product_id,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'url', pi.public_url,
          'alt', pi.alt_text,
          'sort_order', pi.sort_order,
          'is_main', pi.is_main
        ) order by pi.is_main desc, pi.sort_order, pi.id
      ) filter (where pi.id is not null and nullif(btrim(pi.public_url), '') is not null),
      '[]'::jsonb
    ) as images,
    (array_agg(pi.public_url order by pi.is_main desc, pi.sort_order, pi.id)
      filter (where nullif(btrim(pi.public_url), '') is not null))[1] as fallback_main_image_url
  from public.product_images pi
  group by pi.product_id
),
public_ready as (
  select
    p.*,
    coalesce(nullif(btrim(p.main_image_url), ''), img.fallback_main_image_url) as resolved_main_image_url,
    coalesce(img.images, '[]'::jsonb) as resolved_images
  from public.products p
  left join images_public img on img.product_id = p.id
  where p.status = 'activo'
    and p.visible_on_website = true
    -- Invariante de publicación: un producto preparado administrativamente no
    -- se hace público hasta tener al menos una imagen pública válida.
    and coalesce(nullif(btrim(p.main_image_url), ''), img.fallback_main_image_url) is not null
)
select
  p.id,
  p.catalog_code,
  p.sku,
  p.name,
  p.brand,
  p.business_line,
  p.category,
  p.subcategory,
  p.description,
  p.sale_price,
  case when coalesce(ip.available_stock, 0) > 0 then 'available' else 'out_of_stock' end as availability_status,
  case when coalesce(ip.available_stock, 0) > 0 then 'Disponible' else 'Agotado' end as availability_text,
  -- Alias temporal para consumidores anteriores; retirar tras cutover definitivo.
  case when coalesce(ip.available_stock, 0) > 0 then 'Disponible' else 'Agotado' end as catalog_availability_text,
  p.resolved_main_image_url as main_image_url,
  p.category_folder,
  p.product_folder,
  coalesce(v.variants, '[]'::jsonb) as variants,
  p.resolved_images as images
from public_ready p
left join inventory_public ip on ip.product_id = p.id
left join variants_public v on v.product_id = p.id;

-- La WEB no necesita SELECT directo sobre el write model.
revoke all on table public.products from anon;
revoke all on table public.inventory from anon;
revoke all on table public.product_variants from anon;
revoke all on table public.product_images from anon;
revoke all on table public.suppliers from anon;
revoke all on table public.supplier_products from anon;
revoke all on table public.inventory_movements from anon;

revoke all on public.catalog_public from public, anon, authenticated;
grant select on public.catalog_public to anon, authenticated;
alter view public.catalog_public set (security_barrier = true);

-- Defensa contractual: catalog_public nunca debe filtrar datos operativos.
do $$
declare
  leaked text;
begin
  select string_agg(column_name, ', ' order by ordinal_position)
    into leaked
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'catalog_public'
    and lower(column_name) = any (array[
      'current_cost', 'minimum_stock', 'physical_stock', 'reserved_stock',
      'pending_stock', 'available_stock', 'average_cost', 'supplier_id',
      'supplier_name', 'created_by', 'updated_by'
    ]);

  if leaked is not null then
    raise exception 'catalog_public expone columnas sensibles: %', leaked;
  end if;
end
$$;

comment on view public.catalog_public is
  'Contrato público ADMIN -> WEB de LIHEN.CO. Solo productos activos, visibles y con fotografía; disponibilidad derivada sin cantidades, costos ni proveedores.';

commit;

-- VERIFICACIÓN POST-DESPLIEGUE (solo lectura):
-- select id, sku, name, sale_price, availability_status, main_image_url
-- from public.catalog_public order by name limit 20;
--
-- Con Publishable Key / rol anon:
--   catalog_public       -> SELECT debe funcionar
--   products             -> SELECT debe fallar
--   inventory            -> SELECT debe fallar
--   suppliers            -> SELECT debe fallar
--   financial_movements  -> SELECT debe fallar si aplica al rol anon
