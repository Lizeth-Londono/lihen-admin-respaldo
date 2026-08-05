-- ============================================================
-- LIHEN ADMIN
-- MIGRACIÓN 004: PROVEEDORES, RECEPCIÓN Y PAGOS
-- ============================================================

begin;

create or replace function public.create_supplier_request_atomic(
  p_supplier_id uuid,
  p_related_order_id uuid default null,
  p_expected_date date default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns public.supplier_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.supplier_requests;
  v_item jsonb;
  v_product_id uuid;
  v_variant_id uuid;
  v_order_item_id uuid;
  v_qty integer;
  v_cost numeric(14,2);
  v_message text;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if not exists (select 1 from public.suppliers where id = p_supplier_id and active = true) then
    raise exception 'Proveedor no encontrado o inactivo';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La solicitud debe incluir al menos un producto';
  end if;

  insert into public.supplier_requests (
    supplier_id, related_order_id, status, expected_date, notes,
    created_by, updated_by
  ) values (
    p_supplier_id, p_related_order_id, 'borrador', p_expected_date, p_notes,
    v_user_id, v_user_id
  ) returning * into v_request;

  v_message := 'Hola, buen día. Somos LIHEN.CO.%0AQueremos confirmar disponibilidad de:%0A';

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_variant_id := nullif(v_item->>'variant_id','')::uuid;
    v_order_item_id := nullif(v_item->>'related_order_item_id','')::uuid;
    v_qty := coalesce((v_item->>'quantity_requested')::integer, 0);
    v_cost := nullif(v_item->>'quoted_unit_cost','')::numeric;

    if v_qty <= 0 then
      raise exception 'La cantidad solicitada debe ser mayor que cero';
    end if;

    if not exists (select 1 from public.products where id = v_product_id) then
      raise exception 'Uno de los productos no existe';
    end if;

    insert into public.supplier_request_items (
      supplier_request_id, product_id, variant_id, related_order_item_id,
      quantity_requested, quoted_unit_cost
    ) values (
      v_request.id, v_product_id, v_variant_id, v_order_item_id,
      v_qty, v_cost
    );

    update public.inventory
    set pending_stock = pending_stock + v_qty,
        updated_by = v_user_id
    where product_id = v_product_id
      and variant_id is not distinct from v_variant_id;

    v_message := v_message || '• ' || v_qty || ' x ' ||
      (select name from public.products where id = v_product_id) || '%0A';
  end loop;

  v_message := v_message || '%0APor favor confírmanos disponibilidad, precio actualizado y tiempo de entrega. Gracias.';

  update public.supplier_requests
  set whatsapp_message = v_message,
      updated_by = v_user_id
  where id = v_request.id
  returning * into v_request;

  insert into public.audit_logs(user_id, action, entity_type, entity_id, new_data)
  values (v_user_id, 'crear_solicitud_proveedor', 'supplier_requests', v_request.id::text, to_jsonb(v_request));

  return v_request;
end;
$$;

create or replace function public.receive_supplier_request_atomic(
  p_supplier_request_id uuid,
  p_items jsonb default '[]'::jsonb
)
returns public.supplier_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.supplier_requests;
  v_item jsonb;
  v_req_item public.supplier_request_items;
  v_inventory public.inventory;
  v_qty integer;
  v_cost numeric(14,2);
  v_new_average numeric(14,2);
  v_order_item public.order_items;
  v_needed integer;
  v_reserve integer;
  v_all_received boolean;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  select * into v_request
  from public.supplier_requests
  where id = p_supplier_request_id
  for update;

  if not found then raise exception 'Solicitud no encontrada'; end if;
  if v_request.status = 'cancelada' then raise exception 'La solicitud está cancelada'; end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select * into v_req_item
    from public.supplier_request_items
    where id = (v_item->>'supplier_request_item_id')::uuid
      and supplier_request_id = p_supplier_request_id
    for update;

    if not found then raise exception 'Detalle de solicitud no encontrado'; end if;

    v_qty := coalesce((v_item->>'quantity_received')::integer, 0);
    v_cost := coalesce(nullif(v_item->>'final_unit_cost','')::numeric, v_req_item.final_unit_cost, v_req_item.quoted_unit_cost, 0);

    if v_qty <= 0 then raise exception 'La cantidad recibida debe ser mayor que cero'; end if;
    if v_req_item.quantity_received + v_qty > v_req_item.quantity_requested then
      raise exception 'La recepción supera la cantidad solicitada';
    end if;

    select * into v_inventory
    from public.inventory
    where product_id = v_req_item.product_id
      and variant_id is not distinct from v_req_item.variant_id
    for update;

    if not found then
      insert into public.inventory(product_id, variant_id, physical_stock, reserved_stock, pending_stock, average_cost, updated_by)
      values(v_req_item.product_id, v_req_item.variant_id, 0, 0, 0, 0, v_user_id)
      returning * into v_inventory;
    end if;

    v_new_average := case
      when v_inventory.physical_stock + v_qty = 0 then v_cost
      else round(((v_inventory.physical_stock * v_inventory.average_cost) + (v_qty * v_cost)) / (v_inventory.physical_stock + v_qty), 2)
    end;

    update public.inventory
    set physical_stock = physical_stock + v_qty,
        pending_stock = greatest(0, pending_stock - v_qty),
        average_cost = v_new_average,
        updated_by = v_user_id
    where id = v_inventory.id;

    insert into public.inventory_movements(
      inventory_id, movement_type, quantity,
      physical_before, physical_after,
      reserved_before, reserved_after,
      unit_cost, supplier_request_id, reason, performed_by
    ) values (
      v_inventory.id, 'entrada_compra', v_qty,
      v_inventory.physical_stock, v_inventory.physical_stock + v_qty,
      v_inventory.reserved_stock, v_inventory.reserved_stock,
      v_cost, p_supplier_request_id,
      'Recepción de proveedor ' || v_request.request_number,
      v_user_id
    );

    update public.supplier_request_items
    set quantity_received = quantity_received + v_qty,
        final_unit_cost = v_cost
    where id = v_req_item.id;

    if v_req_item.related_order_item_id is not null then
      select * into v_order_item
      from public.order_items
      where id = v_req_item.related_order_item_id
      for update;

      if found then
        v_needed := greatest(0, v_order_item.quantity - v_order_item.quantity_reserved);
        v_reserve := least(v_needed, v_qty);

        if v_reserve > 0 then
          update public.inventory
          set reserved_stock = reserved_stock + v_reserve,
              updated_by = v_user_id
          where id = v_inventory.id;

          insert into public.inventory_movements(
            inventory_id, movement_type, quantity,
            physical_before, physical_after,
            reserved_before, reserved_after,
            order_id, supplier_request_id, reason, performed_by
          ) values (
            v_inventory.id, 'reserva_pedido', v_reserve,
            v_inventory.physical_stock + v_qty, v_inventory.physical_stock + v_qty,
            v_inventory.reserved_stock, v_inventory.reserved_stock + v_reserve,
            v_order_item.order_id, p_supplier_request_id,
            'Reserva de mercancía recibida para pedido', v_user_id
          );

          update public.order_items
          set quantity_received = quantity_received + v_qty,
              quantity_reserved = quantity_reserved + v_reserve
          where id = v_order_item.id;
        end if;
      end if;
    end if;
  end loop;

  select not exists (
    select 1 from public.supplier_request_items
    where supplier_request_id = p_supplier_request_id
      and quantity_received < quantity_requested
  ) into v_all_received;

  update public.supplier_requests
  set status = case when v_all_received then 'recibida' else 'parcial' end,
      received_at = case when v_all_received then now() else received_at end,
      updated_by = v_user_id
  where id = p_supplier_request_id
  returning * into v_request;

  if v_request.related_order_id is not null then
    update public.orders o
    set status = case
      when not exists (
        select 1 from public.order_items oi
        where oi.order_id = o.id and oi.quantity_reserved < oi.quantity
      ) then 'pedido_completo'::public.order_status
      else 'recepcion_parcial'::public.order_status
    end,
    updated_by = v_user_id
    where o.id = v_request.related_order_id;
  end if;

  insert into public.audit_logs(user_id, action, entity_type, entity_id, new_data)
  values (v_user_id, 'recibir_solicitud_proveedor', 'supplier_requests', v_request.id::text, to_jsonb(v_request));

  return v_request;
end;
$$;

create or replace function public.update_order_payment_atomic(
  p_order_id uuid,
  p_payment_method text,
  p_payment_status text,
  p_amount numeric default 0,
  p_reference_number text default null,
  p_notes text default null
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if v_order.status = 'cancelado' then raise exception 'No se puede registrar pago en un pedido cancelado'; end if;
  if p_amount < 0 then raise exception 'El valor no puede ser negativo'; end if;

  update public.orders
  set payment_method = p_payment_method::public.payment_method,
      payment_status = p_payment_status::public.payment_status,
      status = case
        when status in ('pedido_completo','esperando_medio_pago') then 'confirmado_cliente'::public.order_status
        else status
      end,
      confirmed_at = coalesce(confirmed_at, now()),
      updated_by = v_user_id
  where id = p_order_id
  returning * into v_order;

  if p_amount > 0 then
    insert into public.payments(order_id, method, status, amount, reference_number, payment_date, notes, registered_by)
    values(p_order_id, p_payment_method::public.payment_method, p_payment_status::public.payment_status,
           p_amount, p_reference_number, now(), p_notes, v_user_id);
  end if;

  insert into public.audit_logs(user_id, action, entity_type, entity_id, new_data)
  values(v_user_id, 'actualizar_pago_pedido', 'orders', p_order_id::text, to_jsonb(v_order));

  return v_order;
end;
$$;

revoke all on function public.create_supplier_request_atomic(uuid,uuid,date,text,jsonb) from public;
revoke all on function public.receive_supplier_request_atomic(uuid,jsonb) from public;
revoke all on function public.update_order_payment_atomic(uuid,text,text,numeric,text,text) from public;

grant execute on function public.create_supplier_request_atomic(uuid,uuid,date,text,jsonb) to authenticated;
grant execute on function public.receive_supplier_request_atomic(uuid,jsonb) to authenticated;
grant execute on function public.update_order_payment_atomic(uuid,text,text,numeric,text,text) to authenticated;

commit;
