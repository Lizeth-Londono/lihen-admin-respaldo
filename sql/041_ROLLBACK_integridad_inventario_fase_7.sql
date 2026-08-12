-- Rollback Fase 7 — restaura adjust_inventory_atomic al contrato previo
-- y elimina solamente las protecciones agregadas por migración 041.
begin;

drop trigger if exists trg_validate_inventory_product_variant on public.inventory;
drop function if exists public.validate_inventory_product_variant();

alter table public.inventory drop constraint if exists inventory_physical_stock_nonnegative;
alter table public.inventory drop constraint if exists inventory_reserved_stock_nonnegative;
alter table public.inventory drop constraint if exists inventory_pending_stock_nonnegative;
alter table public.inventory drop constraint if exists inventory_reserved_not_above_physical;

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
  v_before integer;
  v_difference integer;
  v_type public.inventory_movement_type;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if p_new_physical_stock < 0 then
    raise exception 'El stock físico no puede ser negativo';
  end if;

  if p_variant_id is null then
    select * into v_inventory from public.inventory
    where product_id = p_product_id and variant_id is null for update;
  else
    select * into v_inventory from public.inventory
    where product_id = p_product_id and variant_id = p_variant_id for update;
  end if;

  if not found then
    insert into public.inventory (
      product_id, variant_id, physical_stock, reserved_stock,
      pending_stock, average_cost, last_counted_at, updated_by
    ) values (
      p_product_id, p_variant_id, p_new_physical_stock, 0,
      0, 0, now(), v_user_id
    ) returning * into v_inventory;

    if p_new_physical_stock > 0 then
      insert into public.inventory_movements (
        inventory_id, movement_type, quantity, physical_before, physical_after,
        reserved_before, reserved_after, reason, performed_by
      ) values (
        v_inventory.id, 'ajuste_positivo', p_new_physical_stock,
        0, p_new_physical_stock, 0, 0, p_reason, v_user_id
      );
    end if;
    return v_inventory;
  end if;

  if p_new_physical_stock < v_inventory.reserved_stock then
    raise exception 'El nuevo stock no puede ser menor que el stock reservado';
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
      inventory_id, movement_type, quantity, physical_before, physical_after,
      reserved_before, reserved_after, reason, performed_by
    ) values (
      v_inventory.id, v_type, abs(v_difference),
      v_before, p_new_physical_stock,
      v_inventory.reserved_stock, v_inventory.reserved_stock,
      p_reason, v_user_id
    );
  end if;

  insert into public.audit_logs (
    user_id, action, entity_type, entity_id, new_data, details
  ) values (
    v_user_id, 'ajustar_inventario', 'inventory', v_inventory.id::text,
    to_jsonb(v_inventory), jsonb_build_object('reason', p_reason)
  );

  return v_inventory;
end;
$$;

revoke all on function public.adjust_inventory_atomic(uuid,uuid,integer,text) from public;
grant execute on function public.adjust_inventory_atomic(uuid,uuid,integer,text) to authenticated;

commit;
