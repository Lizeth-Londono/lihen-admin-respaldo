-- LIHEN ADMIN - MIGRACIÓN 008
-- Edición transaccional de pedidos con ajuste diferencial de reservas.
begin;

create or replace function public.update_order_atomic(
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
returns public.orders
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid:=auth.uid(); v_order public.orders; v_old jsonb; v_item jsonb; v_old_item record;
  v_product public.products; v_inventory public.inventory; v_qty int; v_old_reserved int; v_available int; v_from_stock int; v_to_source int;
  v_price numeric(14,2); v_subtotal numeric(14,2):=0; v_discount numeric(14,2):=0; v_total numeric(14,2):=0; v_missing boolean:=false;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if v_order.status in ('entregado','cancelado') then raise exception 'El pedido está bloqueado y no puede editarse'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'El pedido debe incluir productos'; end if;
  v_old:=to_jsonb(v_order);

  -- Libera reservas anteriores antes de recalcularlas.
  for v_old_item in select * from public.order_items where order_id=p_order_id loop
    if v_old_item.variant_id is null then
      select * into v_inventory from public.inventory where product_id=v_old_item.product_id and variant_id is null for update;
    else
      select * into v_inventory from public.inventory where product_id=v_old_item.product_id and variant_id=v_old_item.variant_id for update;
    end if;
    if found and coalesce(v_old_item.quantity_reserved,0)>0 then
      update public.inventory set reserved_stock=greatest(0,reserved_stock-v_old_item.quantity_reserved),updated_by=v_user_id where id=v_inventory.id;
      insert into public.inventory_movements(inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,order_id,reason,performed_by)
      values(v_inventory.id,'liberacion_reserva',v_old_item.quantity_reserved,v_inventory.physical_stock,v_inventory.physical_stock,v_inventory.reserved_stock,greatest(0,v_inventory.reserved_stock-v_old_item.quantity_reserved),p_order_id,'Recalculo por edición del pedido '||v_order.order_number,v_user_id);
    end if;
  end loop;
  delete from public.order_items where order_id=p_order_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty:=coalesce((v_item->>'quantity')::int,0); v_price:=coalesce((v_item->>'unit_price')::numeric,0);
    if v_qty<=0 or v_price<0 then raise exception 'Cantidad o precio inválido'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and status<>'descontinuado';
    if not found then raise exception 'Producto inválido'; end if;
    v_subtotal:=v_subtotal+round(v_qty*v_price,2);
    select * into v_inventory from public.inventory where product_id=v_product.id and variant_id is null for update;
    if not found then insert into public.inventory(product_id,physical_stock,reserved_stock,pending_stock,average_cost,updated_by) values(v_product.id,0,0,0,coalesce(v_product.current_cost,0),v_user_id) returning * into v_inventory; end if;
    v_available:=greatest(0,v_inventory.physical_stock-v_inventory.reserved_stock); v_from_stock:=least(v_available,v_qty); v_to_source:=v_qty-v_from_stock;
    if v_to_source>0 then v_missing:=true; end if;
    insert into public.order_items(order_id,product_id,variant_id,product_name_snapshot,variant_snapshot,quantity,unit_price,discount_amount,line_total,quantity_from_stock,quantity_to_source,quantity_reserved,quantity_received)
    values(p_order_id,v_product.id,null,v_product.name,v_item->>'variant_snapshot',v_qty,v_price,0,round(v_qty*v_price,2),v_from_stock,v_to_source,v_from_stock,0);
    if v_from_stock>0 then
      update public.inventory set reserved_stock=reserved_stock+v_from_stock,updated_by=v_user_id where id=v_inventory.id;
      insert into public.inventory_movements(inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,order_id,reason,performed_by)
      values(v_inventory.id,'reserva_pedido',v_from_stock,v_inventory.physical_stock,v_inventory.physical_stock,v_inventory.reserved_stock,v_inventory.reserved_stock+v_from_stock,p_order_id,'Nueva reserva por edición del pedido '||v_order.order_number,v_user_id);
    end if;
  end loop;

  v_discount:=case p_discount_type when 'porcentaje' then round(v_subtotal*least(p_discount_value,100)/100,2) when 'valor_fijo' then least(p_discount_value,v_subtotal) else 0 end;
  v_total:=greatest(0,round(v_subtotal-v_discount+p_delivery_cost,2));
  update public.orders set customer_id=p_customer_id,payment_method=p_payment_method::public.payment_method,discount_type=p_discount_type::public.discount_type,discount_value=p_discount_value,discount_amount=v_discount,delivery_cost=p_delivery_cost,subtotal=v_subtotal,total=v_total,internal_notes=p_internal_notes,status=(case when p_status is not null then p_status::public.order_status when v_missing then 'pendiente_proveedor'::public.order_status else 'pedido_completo'::public.order_status end),updated_by=v_user_id where id=p_order_id returning * into v_order;
  insert into public.audit_logs(user_id,action,entity_type,entity_id,old_data,new_data,details) values(v_user_id,'actualizar_pedido','orders',p_order_id::text,v_old,to_jsonb(v_order),jsonb_build_object('items',p_items));
  return v_order;
end;$$;

revoke all on function public.update_order_atomic(uuid,uuid,text,text,numeric,numeric,text,text,jsonb) from public;
grant execute on function public.update_order_atomic(uuid,uuid,text,text,numeric,numeric,text,text,jsonb) to authenticated;
commit;
