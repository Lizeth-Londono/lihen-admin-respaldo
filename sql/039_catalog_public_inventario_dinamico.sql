-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 039
-- Catálogo público con disponibilidad derivada de inventario.
-- Ejecutar después de 038_hotfix_anulacion_ventas_legacy.sql.
-- ============================================================

begin;

-- HOTFIX V8:
-- La vista catalog_public ya existe en producción con un contrato anterior.
-- PostgreSQL no permite cambiar/reordenar nombres de columnas mediante
-- CREATE OR REPLACE VIEW. Por eso se recrea explícitamente dentro de la
-- misma transacción.
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
      ) filter (where pi.id is not null and nullif(trim(pi.public_url), '') is not null),
      '[]'::jsonb
    ) as images,
    (array_agg(pi.public_url order by pi.is_main desc, pi.sort_order, pi.id)
      filter (where nullif(trim(pi.public_url), '') is not null))[1] as fallback_main_image_url
  from public.product_images pi
  group by pi.product_id
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
  -- Compatibilidad temporal con consumidores anteriores.
  case when coalesce(ip.available_stock, 0) > 0 then 'Disponible' else 'Agotado' end as catalog_availability_text,
  coalesce(nullif(trim(p.main_image_url), ''), img.fallback_main_image_url) as main_image_url,
  p.category_folder,
  p.product_folder,
  coalesce(v.variants, '[]'::jsonb) as variants,
  coalesce(img.images, '[]'::jsonb) as images
from public.products p
left join inventory_public ip on ip.product_id = p.id
left join variants_public v on v.product_id = p.id
left join images_public img on img.product_id = p.id
where p.status = 'activo'
  and p.visible_on_website = true;

revoke all on public.catalog_public from public;
grant select on public.catalog_public to anon, authenticated;

comment on view public.catalog_public is
  'Frontera pública LIHEN.CO. Expone datos comerciales y disponibilidad derivada de inventory sin revelar cantidades ni datos administrativos.';

commit;
