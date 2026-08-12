-- Rollback de la migración 039: restaura el contrato equivalente a 005.
begin;

create or replace view public.catalog_public as
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
  p.catalog_availability_text,
  p.main_image_url,
  p.category_folder,
  p.product_folder,
  coalesce(
    jsonb_agg(
      distinct jsonb_build_object(
        'id', pv.id,
        'size', pv.size,
        'color', pv.color,
        'tone', pv.tone,
        'presentation', pv.presentation,
        'additional_price', pv.additional_price
      )
    ) filter (where pv.id is not null and pv.active = true),
    '[]'::jsonb
  ) as variants,
  coalesce(
    jsonb_agg(
      distinct jsonb_build_object(
        'url', pi.public_url,
        'alt', pi.alt_text,
        'sort_order', pi.sort_order,
        'is_main', pi.is_main
      )
    ) filter (where pi.id is not null),
    '[]'::jsonb
  ) as images
from public.products p
left join public.product_variants pv on pv.product_id = p.id
left join public.product_images pi on pi.product_id = p.id
where p.status = 'activo'
  and p.visible_on_website = true
group by p.id;

revoke all on public.catalog_public from public;
grant select on public.catalog_public to anon, authenticated;

commit;
