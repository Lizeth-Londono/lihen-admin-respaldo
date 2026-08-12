-- ============================================================
-- LIHEN ADMIN PRO
-- MIGRACIÓN 041: INTEGRIDAD DE INVENTARIO — FASE 7
-- Objetivos:
-- 1) impedir cantidades negativas y reservas superiores al físico;
-- 2) impedir que variant_id pertenezca a otro producto;
-- 3) reforzar adjust_inventory_atomic sin duplicar la lógica de stock disponible;
-- 4) conservar inventory.available_stock como campo derivado/canónico existente.
-- ============================================================

begin;

-- Las restricciones se crean NOT VALID para no convertir una migración de
-- protección futura en una operación destructiva sobre datos históricos.
-- PostgreSQL sí las aplica a INSERT/UPDATE nuevos. Luego pueden validarse
-- explícitamente cuando el diagnóstico de producción confirme que no hay
-- registros históricos inconsistentes.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.inventory'::regclass
      and conname = 'inventory_physical_stock_nonnegative'
  ) then
    alter table public.inventory
      add constraint inventory_physical_stock_nonnegative
      check (physical_stock >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.inventory'::regclass
      and conname = 'inventory_reserved_stock_nonnegative'
  ) then
    alter table public.inventory
      add constraint inventory_reserved_stock_nonnegative
      check (reserved_stock >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.inventory'::regclass
      and conname = 'inventory_pending_stock_nonnegative'
  ) then
    alter table public.inventory
      add constraint inventory_pending_stock_nonnegative
      check (pending_stock >= 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.inventory'::regclass
      and conname = 'inventory_reserved_not_above_physical'
  ) then
    alter table public.inventory
      add constraint inventory_reserved_not_above_physical
      check (reserved_stock <= physical_stock) not valid;
  end if;
end
$$;

-- Una variante de inventario solo puede apuntar a una variante del mismo
-- producto. El trigger protege todos los caminos de escritura (pedidos,
-- compras, importaciones y ajustes), no solamente la UI.
create or replace function public.validate_inventory_product_variant()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.variant_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.product_variants pv
    where pv.id = new.variant_id
      and pv.product_id = new.product_id
  ) then
    raise exception 'La variante de inventario no pertenece al producto indicado';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_inventory_product_variant on public.inventory;
create trigger trg_validate_inventory_product_variant
before insert or update of product_id, variant_id
on public.inventory
for each row
execute function public.validate_inventory_product_variant();

-- Refuerza el ajuste manual existente. No escribe reserved_stock,
-- pending_stock ni available_stock desde el cliente.
create or replace function public.adjust_inventory_atomic(
  p_product_id uuid,
  p_variant_id uuid default null,
  p_new_physical_stock integer default 0,
  p_reason text default 'Ajuste manual de inventario'
)
returns public.inventory
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_inventory public.inventory;
  v_product public.products;
  v_before integer;
  v_difference integer;
  v_type public.inventory_movement_type;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if p_product_id is null then
    raise exception 'Debes indicar el producto';
  end if;

  select * into v_product
  from public.products
  where id = p_product_id;

  if not found then
    raise exception 'El producto no existe';
  end if;

  if p_new_physical_stock < 0 then
    raise exception 'El stock físico no puede ser negativo';
  end if;

  if p_variant_id is not null and not exists (
    select 1
    from public.product_variants pv
    where pv.id = p_variant_id
      and pv.product_id = p_product_id
  ) then
    raise exception 'La variante no pertenece al producto indicado';
  end if;

  v_reason := coalesce(v_reason, 'Ajuste manual de inventario');

  if p_variant_id is null then
    select * into v_inventory
    from public.inventory
    where product_id = p_product_id and variant_id is null
    for update;
  else
    select * into v_inventory
    from public.inventory
    where product_id = p_product_id and variant_id = p_variant_id
    for update;
  end if;

  if not found then
    insert into public.inventory (
      product_id, variant_id, physical_stock, reserved_stock,
      pending_stock, average_cost, last_counted_at, updated_by
    ) values (
      p_product_id, p_variant_id, p_new_physical_stock, 0,
      0, coalesce(v_product.current_cost, 0), now(), v_user_id
    ) returning * into v_inventory;

    if p_new_physical_stock > 0 then
      insert into public.inventory_movements (
        inventory_id, movement_type, quantity,
        physical_before, physical_after,
        reserved_before, reserved_after,
        reason, performed_by
      ) values (
        v_inventory.id, 'ajuste_positivo', p_new_physical_stock,
        0, p_new_physical_stock, 0, 0, v_reason, v_user_id
      );
    end if;

    insert into public.audit_logs (
      user_id, action, entity_type, entity_id, new_data, details
    ) values (
      v_user_id, 'ajustar_inventario', 'inventory', v_inventory.id::text,
      to_jsonb(v_inventory), jsonb_build_object(
        'reason', v_reason,
        'created_inventory_row', true,
        'physical_before', 0,
        'physical_after', p_new_physical_stock
      )
    );

    return v_inventory;
  end if;

  if p_new_physical_stock < v_inventory.reserved_stock then
    raise exception 'El nuevo stock no puede ser menor que el stock reservado (%)', v_inventory.reserved_stock;
  end if;

  v_before := v_inventory.physical_stock;
  v_difference := p_new_physical_stock - v_before;

  update public.inventory
  set physical_stock = p_new_physical_stock,
      last_counted_at = now(),
      updated_by = v_user_id
  where id = v_inventory.id
  returning * into v_inventory;

  if v_difference <> 0 then
    v_type := case when v_difference > 0
      then 'ajuste_positivo'::public.inventory_movement_type
      else 'ajuste_negativo'::public.inventory_movement_type
    end;

    insert into public.inventory_movements (
      inventory_id, movement_type, quantity,
      physical_before, physical_after,
      reserved_before, reserved_after,
      reason, performed_by
    ) values (
      v_inventory.id, v_type, abs(v_difference),
      v_before, p_new_physical_stock,
      v_inventory.reserved_stock, v_inventory.reserved_stock,
      v_reason, v_user_id
    );
  end if;

  insert into public.audit_logs (
    user_id, action, entity_type, entity_id, old_data, new_data, details
  ) values (
    v_user_id, 'ajustar_inventario', 'inventory', v_inventory.id::text,
    jsonb_build_object(
      'physical_stock', v_before,
      'reserved_stock', v_inventory.reserved_stock
    ),
    to_jsonb(v_inventory),
    jsonb_build_object(
      'reason', v_reason,
      'physical_before', v_before,
      'physical_after', p_new_physical_stock,
      'difference', v_difference
    )
  );

  return v_inventory;
end;
$$;

revoke all on function public.validate_inventory_product_variant() from public;
revoke all on function public.adjust_inventory_atomic(uuid,uuid,integer,text) from public;
grant execute on function public.adjust_inventory_atomic(uuid,uuid,integer,text) to authenticated;

commit;

-- Diagnóstico recomendado antes de VALIDATE CONSTRAINT en producción:
-- select id, product_id, variant_id, physical_stock, reserved_stock, pending_stock
-- from public.inventory
-- where physical_stock < 0
--    or reserved_stock < 0
--    or pending_stock < 0
--    or reserved_stock > physical_stock;
--
-- Si devuelve 0 filas, validar después de la migración:
-- alter table public.inventory validate constraint inventory_physical_stock_nonnegative;
-- alter table public.inventory validate constraint inventory_reserved_stock_nonnegative;
-- alter table public.inventory validate constraint inventory_pending_stock_nonnegative;
-- alter table public.inventory validate constraint inventory_reserved_not_above_physical;
