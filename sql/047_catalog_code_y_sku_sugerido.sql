-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 047
-- Hotfix: defensa amigable de Código catálogo único.
-- La sugerencia de SKU por línea vive en frontend y NO altera el modelo.
-- Esta migración NO elimina ni relaja la restricción única existente.
-- ============================================================

begin;

create or replace function public.guard_unique_product_catalog_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner record;
begin
  new.catalog_code := nullif(trim(new.catalog_code), '');

  if new.catalog_code is null then
    return new;
  end if;

  select p.id, p.sku, p.name
    into v_owner
  from public.products p
  where lower(trim(p.catalog_code)) = lower(trim(new.catalog_code))
    and p.id is distinct from new.id
  limit 1;

  if found then
    raise exception 'El código catálogo % ya pertenece a % · %. Usa otro código o déjalo vacío.',
      new.catalog_code,
      coalesce(v_owner.sku, 'otro producto'),
      coalesce(v_owner.name, 'sin nombre')
      using errcode = '23505', constraint = 'products_catalog_code_key';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_unique_product_catalog_code() from public, anon, authenticated;

drop trigger if exists trg_products_catalog_code_friendly_unique on public.products;
create trigger trg_products_catalog_code_friendly_unique
before insert or update of catalog_code on public.products
for each row
execute function public.guard_unique_product_catalog_code();

comment on function public.guard_unique_product_catalog_code() is
  'Normaliza Código catálogo vacío a NULL y produce un error legible antes de la restricción única products_catalog_code_key.';

commit;

-- Verificación sugerida:
-- 1) No debe haber duplicados persistidos:
-- select catalog_code, count(*)
-- from public.products
-- where nullif(trim(catalog_code),'') is not null
-- group by catalog_code
-- having count(*) > 1;
--
-- 2) La restricción/índice único existente debe conservarse.
