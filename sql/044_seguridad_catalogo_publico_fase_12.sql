-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 044
-- Seguridad final de la frontera pública catalog_public.
-- Ejecutar después de 043_importacion_inventario_trazabilidad_fase_9.sql.
-- ============================================================

begin;

-- 1) El navegador público NO necesita acceso directo a tablas administrativas.
revoke all on table public.products from anon;
revoke all on table public.inventory from anon;
revoke all on table public.product_variants from anon;
revoke all on table public.product_images from anon;
revoke all on table public.suppliers from anon;
revoke all on table public.supplier_products from anon;
revoke all on table public.inventory_movements from anon;

-- 2) La vista pública es la única frontera de lectura del catálogo.
revoke all on public.catalog_public from public, anon, authenticated;
grant select on public.catalog_public to anon, authenticated;

-- 3) Evita que expresiones externas sean empujadas por debajo de los filtros
--    de la vista. Se conserva la vista con privilegios del owner deliberadamente:
--    anon no recibe SELECT directo sobre inventory, por lo que security_invoker
--    impediría derivar disponibilidad sin abrir acceso al stock exacto.
alter view public.catalog_public set (security_barrier = true);

-- 4) Defensa contra filtraciones accidentales futuras: si alguna migración previa
--    añadió una columna sensible a catalog_public, abortar esta migración.
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
      'current_cost',
      'minimum_stock',
      'reserved_stock',
      'pending_stock',
      'available_stock',
      'average_cost',
      'supplier_id',
      'supplier_name',
      'created_by',
      'updated_by'
    ]);

  if leaked is not null then
    raise exception 'catalog_public expone columnas sensibles: %', leaked;
  end if;
end
$$;

comment on view public.catalog_public is
  'Frontera pública de LIHEN.CO. Única fuente permitida para el catálogo web; no expone costos, proveedores ni cantidades internas de inventario.';

commit;

-- ============================================================
-- VERIFICACIÓN POST-DESPLIEGUE RECOMENDADA
-- ============================================================
-- 1. Con publishable key / rol anon:
--      select * from catalog_public limit 1;     -- DEBE funcionar
--      select * from products limit 1;           -- DEBE fallar por permisos/RLS
--      select * from inventory limit 1;          -- DEBE fallar por permisos/RLS
--
-- 2. Confirmar columnas públicas:
--      select column_name
--      from information_schema.columns
--      where table_schema='public' and table_name='catalog_public'
--      order by ordinal_position;
