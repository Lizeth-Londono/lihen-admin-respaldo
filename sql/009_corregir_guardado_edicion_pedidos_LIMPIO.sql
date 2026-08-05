-- LIHEN ADMIN - MIGRACIÓN 009
-- Corrección de persistencia al editar o eliminar productos de un pedido.
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor.

begin;

create or replace function public.update_order_atomic_v2(
  p_order_id uuid,
  p_customer_id uuid,
  p_payment_method text default 'sin_definir',
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_delivery_cost numeric default 0,
  p_internal_notes text default null,
  p_status text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders;
  v_old_order jsonb;
  v_old_items jsonb := '[]'::jsonb;
  v_new_items jsonb := '[]'::jsonb;
  v_item jsonb;
  v_old_item record;
  v_product public.products;
  v_inventory public.inventory;
  v_qty integer;
  v_variant_id uuid;
  v_variant_snapshot text;
  v_price numeric(14,2);
  v_available integer;
  v_from_stock integer;
  v_to_source integer;
  v_subtotal numeric(14,2) := 0;
  v_discount numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_missing boolean := false;
  v_duplicate_count integer := 0;
begin
  if not public.is_active_cofounder() then
    raise exception using message = 'Acceso no autorizado', errcode = '42501';
  end if;

  if p_order_id is null then
    raise exception 'El identificador del pedido es obligatorio';
  end if;

  if p_customer_id is null then
    raise exception 'Debes seleccionar un cliente';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception using message = 'Pedido no encontrado', errcode = 'P0002';
  end if;

  if v_order.status in ('entregado', 'cancelado') then
    raise exception 'El pedido está bloqueado y no puede editarse';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe incluir al menos un producto';
  end if;

  if coalesce(p_delivery_cost, 0) < 0 or coalesce(p_discount_value, 0) < 0 then
    raise exception 'Los valores no pueden ser negativos';
  end if;

  if p_discount_type = 'porcentaje' and p_discount_value > 100 then
    raise exception 'El descuento porcentual no puede superar el 100%%';
  end if;

  -- Evita líneas repetidas para el mismo producto y variante.
  select
    count(*) - count(distinct concat_ws(':', x->>'product_id', coalesce(x->>'variant_id', '')))
  into v_duplicate_count
  from jsonb_array_elements(p_items) as t(x);

  if v_duplicate_count > 0 then
    raise exception 'El pedido contiene productos duplicados. Ajusta la cantidad en una sola línea.';
  end if;

  v_old_order := to_jsonb(v_order);

  select coalesce(jsonb_agg(to_jsonb(oi) order by oi.created_at, oi.id), '[]'::jsonb)
  into v_old_items
  from public.order_items oi
  where oi.order_id = p_order_id;

  -- Libera las reservas correspondientes a las líneas anteriores.
  for v_old_item in
    select *
    from public.order_items
    where order_id = p_order_id
    for update
  loop
    select *
    into v_inventory
    from public.inventory
    where product_id = v_old_item.product_id
      and variant_id is not distinct from v_old_item.variant_id
    for update;

    if found and coalesce(v_old_item.quantity_reserved, 0) > 0 then
      insert into public.inventory_movements(
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
        'liberacion_reserva',
        v_old_item.quantity_reserved,
        v_inventory.physical_stock,
        v_inventory.physical_stock,
        v_inventory.reserved_stock,
        greatest(0, v_inventory.reserved_stock - v_old_item.quantity_reserved),
        p_order_id,
        'Liberación por edición del pedido ' || v_order.order_number,
        v_user_id
      );

      update public.inventory
      set reserved_stock = greatest(0, reserved_stock - v_old_item.quantity_reserved),
          updated_by = v_user_id
      where id = v_inventory.id;
    end if;
  end loop;

  -- Elimina por completo las líneas antiguas.
  delete from public.order_items
  where order_id = p_order_id;

  -- Reconstruye el detalle exclusivamente con el arreglo recibido.
  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    v_qty := coalesce((v_item->>'quantity')::integer, 0);
    v_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_variant_id := nullif(v_item->>'variant_id', '')::uuid;
    v_variant_snapshot := nullif(v_item->>'variant_snapshot', '');

    if v_qty <= 0 then
      raise exception 'Todas las cantidades deben ser mayores que cero';
    end if;

    if v_price < 0 then
      raise exception 'El precio unitario no puede ser negativo';
    end if;

    select *
    into v_product
    from public.products
    where id = (v_item->>'product_id')::uuid
      and status <> 'descontinuado';

    if not found then
      raise exception 'Producto inválido o descontinuado: %', v_item->>'product_id';
    end if;

    select *
    into v_inventory
    from public.inventory
    where product_id = v_product.id
      and variant_id is not distinct from v_variant_id
    for update;

    if not found then
      insert into public.inventory(
        product_id,
        variant_id,
        physical_stock,
        reserved_stock,
        pending_stock,
        average_cost,
        updated_by
      ) values (
        v_product.id,
        v_variant_id,
        0,
        0,
        0,
        coalesce(v_product.current_cost, 0),
        v_user_id
      )
      returning * into v_inventory;
    end if;

    v_available := greatest(0, v_inventory.physical_stock - v_inventory.reserved_stock);
    v_from_stock := least(v_available, v_qty);
    v_to_source := v_qty - v_from_stock;

    if v_to_source > 0 then
      v_missing := true;
    end if;

    insert into public.order_items(
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
      p_order_id,
      v_product.id,
      v_variant_id,
      v_product.name,
      v_variant_snapshot,
      v_qty,
      v_price,
      0,
      round(v_qty * v_price, 2),
      v_from_stock,
      v_to_source,
      v_from_stock,
      0
    );

    if v_from_stock > 0 then
      insert into public.inventory_movements(
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
        p_order_id,
        'Reserva recalculada por edición del pedido ' || v_order.order_number,
        v_user_id
      );

      update public.inventory
      set reserved_stock = reserved_stock + v_from_stock,
          updated_by = v_user_id
      where id = v_inventory.id;
    end if;

    v_subtotal := v_subtotal + round(v_qty * v_price, 2);
  end loop;

  v_discount := case p_discount_type
    when 'porcentaje' then
      round(v_subtotal * least(greatest(coalesce(p_discount_value, 0), 0), 100) / 100, 2)
    when 'valor_fijo' then
      least(greatest(coalesce(p_discount_value, 0), 0), v_subtotal)
    else 0
  end;

  v_total := greatest(
    0,
    round(v_subtotal - v_discount + greatest(coalesce(p_delivery_cost, 0), 0), 2)
  );

  update public.orders
  set customer_id = p_customer_id,
      payment_method = p_payment_method::public.payment_method,
      discount_type = p_discount_type::public.discount_type,
      discount_value = greatest(coalesce(p_discount_value, 0), 0),
      discount_amount = v_discount,
      delivery_cost = greatest(coalesce(p_delivery_cost, 0), 0),
      subtotal = v_subtotal,
      total = v_total,
      internal_notes = p_internal_notes,
      status = case
        when p_status is not null then p_status::public.order_status
        when v_missing then 'pendiente_proveedor'::public.order_status
        else 'pedido_completo'::public.order_status
      end,
      updated_by = v_user_id
  where id = p_order_id
  returning * into v_order;

  select coalesce(jsonb_agg(to_jsonb(oi) order by oi.created_at, oi.id), '[]'::jsonb)
  into v_new_items
  from public.order_items oi
  where oi.order_id = p_order_id;

  insert into public.audit_logs(
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    details
  ) values (
    v_user_id,
    'actualizar_pedido',
    'orders',
    p_order_id::text,
    v_old_order,
    to_jsonb(v_order),
    jsonb_build_object(
      'old_items', v_old_items,
      'new_items', v_new_items,
      'old_item_count', jsonb_array_length(v_old_items),
      'new_item_count', jsonb_array_length(v_new_items),
      'deleted_count', greatest(0, jsonb_array_length(v_old_items) - jsonb_array_length(v_new_items)),
      'source', 'update_order_atomic_v2'
    )
  );

  return jsonb_build_object(
    'order', to_jsonb(v_order),
    'items', v_new_items,
    'old_items', v_old_items,
    'deleted_count', greatest(0, jsonb_array_length(v_old_items) - jsonb_array_length(v_new_items)),
    'totals', jsonb_build_object(
      'subtotal', v_subtotal,
      'discount', v_discount,
      'delivery', greatest(coalesce(p_delivery_cost, 0), 0),
      'total', v_total
    )
  );
end;
$$;

revoke all on function public.update_order_atomic_v2(
  uuid, uuid, text, text, numeric, numeric, text, text, jsonb
) from public;

grant execute on function public.update_order_atomic_v2(
  uuid, uuid, text, text, numeric, numeric, text, text, jsonb
) to authenticated;

commit;
