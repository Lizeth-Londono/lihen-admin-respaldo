-- ============================================================
-- LIHEN ADMIN
-- MIGRACIÓN 003: OPERACIONES TRANSACCIONALES DE PEDIDOS E INVENTARIO
-- ============================================================

begin;

-- Evita inventarios duplicados cuando una referencia no tiene variante.
create unique index if not exists inventory_product_without_variant_unique
on public.inventory (product_id)
where variant_id is null;

create unique index if not exists inventory_product_with_variant_unique
on public.inventory (product_id, variant_id)
where variant_id is not null;

-- Garantiza que los importes del pedido sean calculados en el servidor.
create or replace function public.create_order_atomic(
  p_customer_id uuid,
  p_delivery_address_id uuid default null,
  p_payment_method text default 'sin_definir',
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_delivery_cost numeric default 0,
  p_discount_reason text default null,
  p_customer_notes text default null,
  p_internal_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders;
  v_item jsonb;
  v_product public.products;
  v_inventory public.inventory;
  v_variant_id uuid;
  v_quantity integer;
  v_unit_price numeric(14,2);
  v_line_total numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_discount_amount numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_available integer;
  v_from_stock integer;
  v_to_source integer;
  v_has_missing boolean := false;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if p_customer_id is null then
    raise exception 'Debes seleccionar un cliente';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe incluir al menos un producto';
  end if;

  if p_delivery_cost < 0 or p_discount_value < 0 then
    raise exception 'Los valores no pueden ser negativos';
  end if;

  if p_discount_type = 'porcentaje' and p_discount_value > 100 then
    raise exception 'El descuento porcentual no puede superar el 100%%';
  end if;

  -- Primera pasada: validar productos y calcular subtotal con precios enviados.
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_quantity := coalesce((v_item->>'quantity')::integer, 0);
    v_unit_price := coalesce((v_item->>'unit_price')::numeric, 0);

    if v_quantity <= 0 then
      raise exception 'Todas las cantidades deben ser mayores que cero';
    end if;

    if v_unit_price < 0 then
      raise exception 'El precio unitario no puede ser negativo';
    end if;

    select * into v_product
    from public.products
    where id = (v_item->>'product_id')::uuid
      and status <> 'descontinuado';

    if not found then
      raise exception 'Uno de los productos no existe o está descontinuado';
    end if;

    v_line_total := round(v_quantity * v_unit_price, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  v_discount_amount := case p_discount_type
    when 'porcentaje' then round(v_subtotal * p_discount_value / 100, 2)
    when 'valor_fijo' then least(round(p_discount_value, 2), v_subtotal)
    else 0
  end;

  v_total := greatest(0, round(v_subtotal - v_discount_amount + p_delivery_cost, 2));

  insert into public.orders (
    customer_id,
    delivery_address_id,
    status,
    payment_method,
    payment_status,
    subtotal,
    discount_type,
    discount_value,
    discount_amount,
    delivery_cost,
    total,
    discount_reason,
    customer_notes,
    internal_notes,
    estimated_delivery_date,
    created_by,
    updated_by
  ) values (
    p_customer_id,
    p_delivery_address_id,
    'validando_disponibilidad',
    p_payment_method::public.payment_method,
    'pendiente',
    v_subtotal,
    p_discount_type::public.discount_type,
    p_discount_value,
    v_discount_amount,
    p_delivery_cost,
    v_total,
    p_discount_reason,
    p_customer_notes,
    p_internal_notes,
    current_date + 3,
    v_user_id,
    v_user_id
  ) returning * into v_order;

  -- Segunda pasada: bloquear inventario, reservar y crear detalle.
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_variant_id := nullif(v_item->>'variant_id', '')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    v_unit_price := (v_item->>'unit_price')::numeric;
    v_line_total := round(v_quantity * v_unit_price, 2);

    select * into v_product
    from public.products
    where id = (v_item->>'product_id')::uuid;

    if v_variant_id is null then
      select * into v_inventory
      from public.inventory
      where product_id = v_product.id and variant_id is null
      for update;
    else
      select * into v_inventory
      from public.inventory
      where product_id = v_product.id and variant_id = v_variant_id
      for update;
    end if;

    if not found then
      insert into public.inventory (
        product_id, variant_id, physical_stock, reserved_stock,
        pending_stock, average_cost, updated_by
      ) values (
        v_product.id, v_variant_id, 0, 0, 0,
        coalesce(v_product.current_cost, 0), v_user_id
      ) returning * into v_inventory;
    end if;

    v_available := greatest(0, v_inventory.physical_stock - v_inventory.reserved_stock);
    v_from_stock := least(v_available, v_quantity);
    v_to_source := v_quantity - v_from_stock;

    if v_to_source > 0 then
      v_has_missing := true;
    end if;

    insert into public.order_items (
      order_id,
      product_id,
      variant_id,
      product_name_snapshot,
      variant_snapshot,
      quantity,
      unit_price,
      discount_amount,
      line_total,
      quantity_from_stock,
      quantity_to_source,
      quantity_reserved,
      quantity_received
    ) values (
      v_order.id,
      v_product.id,
      v_variant_id,
      v_product.name,
      v_item->>'variant_snapshot',
      v_quantity,
      v_unit_price,
      0,
      v_line_total,
      v_from_stock,
      v_to_source,
      v_from_stock,
      0
    );

    if v_from_stock > 0 then
      update public.inventory
      set reserved_stock = reserved_stock + v_from_stock,
          updated_by = v_user_id
      where id = v_inventory.id;

      insert into public.inventory_movements (
        inventory_id,
        movement_type,
        quantity,
        physical_before,
        physical_after,
        reserved_before,
        reserved_after,
        order_id,
        reason,
        performed_by
      ) values (
        v_inventory.id,
        'reserva_pedido',
        v_from_stock,
        v_inventory.physical_stock,
        v_inventory.physical_stock,
        v_inventory.reserved_stock,
        v_inventory.reserved_stock + v_from_stock,
        v_order.id,
        'Reserva automática al crear el pedido ' || v_order.order_number,
        v_user_id
      );
    end if;
  end loop;

  update public.orders
  set status = case
      when v_has_missing then 'pendiente_proveedor'::public.order_status
      else 'pedido_completo'::public.order_status
    end,
    updated_by = v_user_id
  where id = v_order.id
  returning * into v_order;

  insert into public.audit_logs (
    user_id, action, entity_type, entity_id, new_data, details
  ) values (
    v_user_id,
    'crear_pedido',
    'orders',
    v_order.id::text,
    to_jsonb(v_order),
    jsonb_build_object('items_count', jsonb_array_length(p_items))
  );

  return v_order;
end;
$$;

create or replace function public.cancel_order_atomic(
  p_order_id uuid,
  p_reason text default null
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders;
  v_item record;
  v_inventory public.inventory;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_order.status = 'entregado' then
    raise exception 'No se puede cancelar un pedido ya entregado';
  end if;

  if v_order.status = 'cancelado' then
    return v_order;
  end if;

  for v_item in
    select * from public.order_items where order_id = p_order_id
  loop
    if v_item.quantity_reserved > 0 then
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

      if found then
        update public.inventory
        set reserved_stock = greatest(0, reserved_stock - v_item.quantity_reserved),
            updated_by = v_user_id
        where id = v_inventory.id;

        insert into public.inventory_movements (
          inventory_id, movement_type, quantity,
          physical_before, physical_after,
          reserved_before, reserved_after,
          order_id, reason, performed_by
        ) values (
          v_inventory.id, 'liberacion_reserva', v_item.quantity_reserved,
          v_inventory.physical_stock, v_inventory.physical_stock,
          v_inventory.reserved_stock,
          greatest(0, v_inventory.reserved_stock - v_item.quantity_reserved),
          p_order_id,
          coalesce(p_reason, 'Cancelación del pedido ' || v_order.order_number),
          v_user_id
        );
      end if;
    end if;
  end loop;

  update public.orders
  set status = 'cancelado',
      cancelled_at = now(),
      internal_notes = concat_ws(E'\n', internal_notes, p_reason),
      updated_by = v_user_id
  where id = p_order_id
  returning * into v_order;

  insert into public.audit_logs (
    user_id, action, entity_type, entity_id, new_data, details
  ) values (
    v_user_id, 'cancelar_pedido', 'orders', p_order_id::text,
    to_jsonb(v_order), jsonb_build_object('reason', p_reason)
  );

  return v_order;
end;
$$;

create or replace function public.deliver_order_atomic(
  p_order_id uuid
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders;
  v_item record;
  v_inventory public.inventory;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_order.status = 'cancelado' then
    raise exception 'No se puede entregar un pedido cancelado';
  end if;

  if v_order.status = 'entregado' then
    return v_order;
  end if;

  if exists (
    select 1 from public.order_items
    where order_id = p_order_id
      and quantity_reserved < quantity
  ) then
    raise exception 'El pedido todavía no tiene todas las unidades reservadas';
  end if;

  for v_item in
    select * from public.order_items where order_id = p_order_id
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
      raise exception 'No existe inventario para uno de los productos';
    end if;

    if v_inventory.physical_stock < v_item.quantity_reserved
       or v_inventory.reserved_stock < v_item.quantity_reserved then
      raise exception 'El inventario reservado no coincide con el pedido';
    end if;

    update public.inventory
    set physical_stock = physical_stock - v_item.quantity_reserved,
        reserved_stock = reserved_stock - v_item.quantity_reserved,
        updated_by = v_user_id
    where id = v_inventory.id;

    insert into public.inventory_movements (
      inventory_id, movement_type, quantity,
      physical_before, physical_after,
      reserved_before, reserved_after,
      order_id, reason, performed_by
    ) values (
      v_inventory.id, 'salida_venta', v_item.quantity_reserved,
      v_inventory.physical_stock,
      v_inventory.physical_stock - v_item.quantity_reserved,
      v_inventory.reserved_stock,
      v_inventory.reserved_stock - v_item.quantity_reserved,
      p_order_id,
      'Entrega del pedido ' || v_order.order_number,
      v_user_id
    );
  end loop;

  update public.orders
  set status = 'entregado',
      delivered_at = now(),
      updated_by = v_user_id
  where id = p_order_id
  returning * into v_order;

  insert into public.audit_logs (
    user_id, action, entity_type, entity_id, new_data
  ) values (
    v_user_id, 'entregar_pedido', 'orders', p_order_id::text,
    to_jsonb(v_order)
  );

  return v_order;
end;
$$;

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
      0, 0, now(), v_user_id
    ) returning * into v_inventory;

    if p_new_physical_stock > 0 then
      insert into public.inventory_movements (
        inventory_id, movement_type, quantity,
        physical_before, physical_after,
        reserved_before, reserved_after,
        reason, performed_by
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
      inventory_id, movement_type, quantity,
      physical_before, physical_after,
      reserved_before, reserved_after,
      reason, performed_by
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

revoke all on function public.create_order_atomic(uuid,uuid,text,text,numeric,numeric,text,text,text,jsonb) from public;
revoke all on function public.cancel_order_atomic(uuid,text) from public;
revoke all on function public.deliver_order_atomic(uuid) from public;
revoke all on function public.adjust_inventory_atomic(uuid,uuid,integer,text) from public;

grant execute on function public.create_order_atomic(uuid,uuid,text,text,numeric,numeric,text,text,text,jsonb) to authenticated;
grant execute on function public.cancel_order_atomic(uuid,text) to authenticated;
grant execute on function public.deliver_order_atomic(uuid) to authenticated;
grant execute on function public.adjust_inventory_atomic(uuid,uuid,integer,text) to authenticated;

commit;
