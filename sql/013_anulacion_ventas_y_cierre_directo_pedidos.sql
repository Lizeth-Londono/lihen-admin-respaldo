-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 013
-- 1) Corrige y refuerza la anulación de ventas rápidas.
-- 2) Permite registrar un pedido como pagado y entregado,
--    dejando motivo obligatorio cuando se omiten resumen y confirmación.
-- Ejecutar una sola vez en Supabase SQL Editor.
-- ============================================================

begin;

alter table public.orders
  add column if not exists summary_skipped boolean not null default false,
  add column if not exists confirmation_skipped boolean not null default false,
  add column if not exists workflow_override_reason text null,
  add column if not exists workflow_override_at timestamptz null,
  add column if not exists workflow_override_by uuid null references public.profiles(id),
  add column if not exists delivered_at timestamptz null;

create or replace function public.close_order_direct_atomic(
  p_order_id uuid,
  p_payment_method text,
  p_reason text,
  p_reference_number text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_note text;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if v_reason is null or char_length(v_reason) < 10 then
    raise exception 'Debes registrar un motivo claro de al menos 10 caracteres';
  end if;

  if p_payment_method is null or p_payment_method = 'sin_definir' then
    raise exception 'Selecciona el método de pago';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_order.status = 'cancelado' then
    raise exception 'No se puede cerrar como entregado un pedido cancelado';
  end if;

  v_note := concat_ws(E'\n',
    nullif(trim(coalesce(v_order.internal_notes,'')),''),
    '[Cierre directo] ' || v_reason,
    nullif(trim(coalesce(p_notes,'')),'')
  );

  update public.orders
  set payment_method = p_payment_method::public.payment_method,
      payment_status = 'pagado'::public.payment_status,
      status = 'entregado'::public.order_status,
      confirmed_at = coalesce(confirmed_at, now()),
      delivered_at = coalesce(delivered_at, now()),
      summary_skipped = true,
      confirmation_skipped = true,
      workflow_override_reason = v_reason,
      workflow_override_at = now(),
      workflow_override_by = v_user_id,
      internal_notes = v_note,
      updated_by = v_user_id
  where id = p_order_id
  returning * into v_order;

  if not exists (
    select 1
    from public.payments p
    where p.order_id = p_order_id
      and p.status = 'pagado'::public.payment_status
      and p.amount = v_order.total
  ) then
    insert into public.payments(
      order_id, method, status, amount, reference_number,
      payment_date, notes, registered_by
    ) values (
      p_order_id,
      p_payment_method::public.payment_method,
      'pagado'::public.payment_status,
      v_order.total,
      nullif(trim(coalesce(p_reference_number,'')),''),
      now(),
      'Pago registrado mediante cierre directo. Motivo: ' || v_reason,
      v_user_id
    );
  end if;

  insert into public.audit_logs(
    user_id, action, entity_type, entity_id, new_data, details
  ) values (
    v_user_id,
    'cerrar_pedido_sin_confirmacion',
    'orders',
    p_order_id::text,
    to_jsonb(v_order),
    jsonb_build_object(
      'reason', v_reason,
      'skipped_steps', jsonb_build_array('resumen_whatsapp','confirmacion_cliente'),
      'payment_method', p_payment_method,
      'payment_reference', nullif(trim(coalesce(p_reference_number,'')),''),
      'new_status', 'entregado',
      'payment_status', 'pagado'
    )
  );

  return jsonb_build_object(
    'order', to_jsonb(v_order),
    'skipped_steps', jsonb_build_array('resumen_whatsapp','confirmacion_cliente'),
    'reason', v_reason
  );
end;
$$;

create or replace function public.cancel_quick_sale_atomic(
  p_sale_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_sale public.quick_sales;
  v_item record;
  v_inventory public.inventory;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if v_reason is null or char_length(v_reason) < 8 then
    raise exception 'Debes registrar un motivo de al menos 8 caracteres';
  end if;

  select * into v_sale
  from public.quick_sales
  where id = p_sale_id
  for update;

  if not found then
    raise exception 'Venta rápida no encontrada';
  end if;

  if v_sale.status = 'anulada' then
    return jsonb_build_object('sale',to_jsonb(v_sale),'already_cancelled',true);
  end if;

  for v_item in
    select * from public.quick_sale_items where sale_id = p_sale_id
  loop
    if v_item.variant_id is null then
      select * into v_inventory
      from public.inventory
      where product_id = v_item.product_id and variant_id is null
      for update;
    else
      select * into v_inventory
      from public.inventory
      where product_id = v_item.product_id and variant_id = v_item.variant_id
      for update;
    end if;

    if not found then
      raise exception 'No se encontró el inventario para el producto %', v_item.product_name_snapshot;
    end if;

    insert into public.inventory_movements(
      inventory_id, movement_type, quantity,
      physical_before, physical_after,
      reserved_before, reserved_after,
      reason, performed_by
    ) values (
      v_inventory.id,
      'ajuste_positivo',
      v_item.quantity,
      v_inventory.physical_stock,
      v_inventory.physical_stock + v_item.quantity,
      v_inventory.reserved_stock,
      v_inventory.reserved_stock,
      'Devolución por anulación de venta rápida ' || v_sale.sale_number,
      v_user_id
    );

    update public.inventory
    set physical_stock = physical_stock + v_item.quantity,
        updated_by = v_user_id
    where id = v_inventory.id;
  end loop;

  update public.quick_sales
  set status = 'anulada',
      cancelled_by = v_user_id,
      cancelled_at = now(),
      cancellation_reason = v_reason,
      updated_at = now()
  where id = p_sale_id
  returning * into v_sale;

  insert into public.audit_logs(
    user_id, action, entity_type, entity_id, new_data, details
  ) values (
    v_user_id,
    'anular_venta_rapida',
    'quick_sales',
    v_sale.id::text,
    to_jsonb(v_sale),
    jsonb_build_object('reason',v_reason,'stock_reintegrated',true)
  );

  return jsonb_build_object('sale',to_jsonb(v_sale),'stock_reintegrated',true);
end;
$$;

revoke all on function public.close_order_direct_atomic(uuid,text,text,text,text) from public;
grant execute on function public.close_order_direct_atomic(uuid,text,text,text,text) to authenticated;

revoke all on function public.cancel_quick_sale_atomic(uuid,text) from public;
grant execute on function public.cancel_quick_sale_atomic(uuid,text) to authenticated;

commit;
