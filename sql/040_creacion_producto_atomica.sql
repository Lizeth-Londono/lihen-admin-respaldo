-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 040
-- Fase 6: creación atómica de producto + inventario inicial + proveedor.
-- Ejecutar después de 039_catalog_public_inventario_dinamico.sql.
-- ============================================================

begin;

create or replace function public.create_product_atomic(
  p_product jsonb,
  p_initial_physical_stock integer default 0,
  p_supplier_id uuid default null
)
returns public.products
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_product public.products%rowtype;
  v_name text;
  v_sku text;
  v_catalog_code text;
  v_sale_price numeric;
  v_current_cost numeric;
  v_minimum_stock integer;
  v_visible boolean;
  v_supplier_exists boolean;
begin
  if v_user_id is null or not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado' using errcode = '42501';
  end if;

  if jsonb_typeof(p_product) <> 'object' then
    raise exception 'Los datos del producto no son válidos';
  end if;

  v_name := nullif(trim(p_product->>'name'), '');
  v_sku := nullif(trim(p_product->>'sku'), '');
  v_catalog_code := nullif(trim(p_product->>'catalog_code'), '');
  v_sale_price := nullif(p_product->>'sale_price', '')::numeric;
  v_current_cost := nullif(p_product->>'current_cost', '')::numeric;
  v_minimum_stock := coalesce(nullif(p_product->>'minimum_stock', '')::integer, 0);
  v_visible := coalesce(nullif(p_product->>'visible_on_website', '')::boolean, false);

  if v_name is null then
    raise exception 'El nombre del producto es obligatorio';
  end if;

  if v_sale_price is null or v_sale_price < 0 then
    raise exception 'El precio LIHEN debe ser mayor o igual a cero';
  end if;

  if v_current_cost is not null and v_current_cost < 0 then
    raise exception 'El costo actual debe ser mayor o igual a cero';
  end if;

  if v_minimum_stock < 0 then
    raise exception 'El stock mínimo debe ser mayor o igual a cero';
  end if;

  if coalesce(p_initial_physical_stock, 0) < 0 then
    raise exception 'El stock físico inicial debe ser mayor o igual a cero';
  end if;

  if v_sku is not null and exists (
    select 1 from public.products p where lower(trim(p.sku)) = lower(v_sku)
  ) then
    raise exception 'El SKU % ya está registrado', v_sku;
  end if;

  if v_catalog_code is not null and exists (
    select 1 from public.products p where lower(trim(p.catalog_code)) = lower(v_catalog_code)
  ) then
    raise exception 'El código catálogo % ya está registrado', v_catalog_code;
  end if;

  if p_supplier_id is not null then
    select exists(
      select 1
      from public.suppliers s
      where s.id = p_supplier_id
        and coalesce(s.active, true) = true
    ) into v_supplier_exists;

    if not v_supplier_exists then
      raise exception 'El proveedor seleccionado no existe o está inactivo';
    end if;
  end if;

  insert into public.products (
    catalog_code,
    sku,
    name,
    business_line,
    category,
    subcategory,
    brand,
    sale_price,
    current_cost,
    minimum_stock,
    description,
    status,
    visible_on_website,
    created_by,
    updated_by
  ) values (
    v_catalog_code,
    v_sku,
    v_name,
    nullif(trim(p_product->>'business_line'), ''),
    nullif(trim(p_product->>'category'), ''),
    nullif(trim(p_product->>'subcategory'), ''),
    nullif(trim(p_product->>'brand'), ''),
    v_sale_price,
    v_current_cost,
    v_minimum_stock,
    nullif(trim(p_product->>'description'), ''),
    coalesce(nullif(trim(p_product->>'status'), ''), 'activo'),
    v_visible,
    v_user_id,
    v_user_id
  )
  returning * into v_product;

  insert into public.inventory (
    product_id,
    variant_id,
    physical_stock,
    updated_by
  ) values (
    v_product.id,
    null,
    coalesce(p_initial_physical_stock, 0),
    v_user_id
  );

  if p_supplier_id is not null then
    insert into public.supplier_products (
      supplier_id,
      product_id,
      last_cost,
      preferred
    ) values (
      p_supplier_id,
      v_product.id,
      v_current_cost,
      true
    );
  end if;

  return v_product;
end;
$$;

revoke all on function public.create_product_atomic(jsonb,integer,uuid) from public, anon;
grant execute on function public.create_product_atomic(jsonb,integer,uuid) to authenticated;

comment on function public.create_product_atomic(jsonb,integer,uuid) is
  'Crea producto, inventario inicial y relación de proveedor en una sola transacción PostgreSQL.';

commit;
