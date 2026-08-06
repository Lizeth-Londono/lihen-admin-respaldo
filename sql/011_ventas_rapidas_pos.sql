-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 011
-- Ventas rápidas / POS ligero con descuento inmediato de stock
-- Ejecutar una sola vez en Supabase SQL Editor.
-- ============================================================

begin;

create table if not exists public.quick_sales (
  id uuid primary key default gen_random_uuid(),
  sale_number text not null unique,
  customer_id uuid null references public.customers(id) on delete set null,
  payment_method text not null check (payment_method in ('efectivo','nequi','transferencia','llave_bancaria','datafono','otro')),
  payment_reference text null,
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_type text not null default 'ninguno' check (discount_type in ('ninguno','porcentaje','valor_fijo')),
  discount_value numeric(14,2) not null default 0 check (discount_value >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  notes text null,
  status text not null default 'completada' check (status in ('completada','anulada')),
  created_by uuid not null references public.profiles(id),
  cancelled_by uuid null references public.profiles(id),
  cancelled_at timestamptz null,
  cancellation_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.quick_sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.quick_sales(id) on delete cascade,
  product_id uuid not null references public.products(id),
  variant_id uuid null,
  product_name_snapshot text not null,
  variant_snapshot text null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

create index if not exists quick_sales_created_at_idx on public.quick_sales(created_at desc);
create index if not exists quick_sales_customer_idx on public.quick_sales(customer_id);
create index if not exists quick_sale_items_sale_idx on public.quick_sale_items(sale_id);

alter table public.quick_sales enable row level security;
alter table public.quick_sale_items enable row level security;

drop policy if exists "cofundadoras_consultan_ventas_rapidas" on public.quick_sales;
create policy "cofundadoras_consultan_ventas_rapidas"
on public.quick_sales for select to authenticated
using (public.is_active_cofounder());

drop policy if exists "cofundadoras_consultan_items_ventas_rapidas" on public.quick_sale_items;
create policy "cofundadoras_consultan_items_ventas_rapidas"
on public.quick_sale_items for select to authenticated
using (public.is_active_cofounder());

grant select on public.quick_sales, public.quick_sale_items to authenticated;

create or replace function public.next_quick_sale_number()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year text := to_char(current_date, 'YYYY');
  v_next integer;
begin
  select coalesce(max(substring(sale_number from '([0-9]+)$')::integer),0)+1
  into v_next
  from public.quick_sales
  where sale_number like 'VR-' || v_year || '-%';

  return 'VR-' || v_year || '-' || lpad(v_next::text,5,'0');
end;
$$;

create or replace function public.create_quick_sale_atomic(
  p_customer_id uuid default null,
  p_payment_method text default 'efectivo',
  p_payment_reference text default null,
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_sale public.quick_sales;
  v_item jsonb;
  v_product public.products;
  v_inventory public.inventory;
  v_variant_id uuid;
  v_quantity integer;
  v_price numeric(14,2);
  v_line numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_discount numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_available integer;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'Agrega al menos un producto'; end if;
  if p_payment_method not in ('efectivo','nequi','transferencia','llave_bancaria','datafono','otro') then raise exception 'Método de pago no válido'; end if;
  if p_discount_value < 0 then raise exception 'El descuento no puede ser negativo'; end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_quantity := coalesce((v_item->>'quantity')::integer,0);
    v_price := coalesce((v_item->>'unit_price')::numeric,0);
    if v_quantity <= 0 then raise exception 'Las cantidades deben ser mayores que cero'; end if;
    if v_price < 0 then raise exception 'El precio no puede ser negativo'; end if;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and status <> 'descontinuado';
    if not found then raise exception 'Producto no disponible'; end if;
    v_subtotal := v_subtotal + round(v_quantity*v_price,2);
  end loop;

  v_discount := case p_discount_type
    when 'porcentaje' then round(v_subtotal*least(p_discount_value,100)/100,2)
    when 'valor_fijo' then least(round(p_discount_value,2),v_subtotal)
    else 0 end;
  v_total := greatest(0,round(v_subtotal-v_discount,2));

  insert into public.quick_sales(
    sale_number,customer_id,payment_method,payment_reference,subtotal,
    discount_type,discount_value,discount_amount,total,notes,created_by
  ) values (
    public.next_quick_sale_number(),p_customer_id,p_payment_method,nullif(trim(p_payment_reference),''),v_subtotal,
    p_discount_type,p_discount_value,v_discount,v_total,p_notes,v_user_id
  ) returning * into v_sale;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_variant_id := nullif(v_item->>'variant_id','')::uuid;
    v_quantity := (v_item->>'quantity')::integer;
    v_price := (v_item->>'unit_price')::numeric;
    v_line := round(v_quantity*v_price,2);

    select * into v_product from public.products where id=(v_item->>'product_id')::uuid;
    if v_variant_id is null then
      select * into v_inventory from public.inventory where product_id=v_product.id and variant_id is null for update;
    else
      select * into v_inventory from public.inventory where product_id=v_product.id and variant_id=v_variant_id for update;
    end if;
    if not found then raise exception 'El producto % no tiene inventario registrado',v_product.name; end if;

    v_available := greatest(0,v_inventory.physical_stock-v_inventory.reserved_stock);
    if v_available < v_quantity then
      raise exception 'Stock insuficiente para %. Disponible: %, solicitado: %',v_product.name,v_available,v_quantity;
    end if;

    insert into public.quick_sale_items(sale_id,product_id,variant_id,product_name_snapshot,variant_snapshot,quantity,unit_price,line_total)
    values(v_sale.id,v_product.id,v_variant_id,v_product.name,v_item->>'variant_snapshot',v_quantity,v_price,v_line);

    insert into public.inventory_movements(
      inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
    ) values(
      v_inventory.id,'ajuste_negativo',v_quantity,v_inventory.physical_stock,v_inventory.physical_stock-v_quantity,
      v_inventory.reserved_stock,v_inventory.reserved_stock,'Salida por venta rápida '||v_sale.sale_number,v_user_id
    );

    update public.inventory set physical_stock=physical_stock-v_quantity,updated_by=v_user_id where id=v_inventory.id;
  end loop;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(v_user_id,'crear_venta_rapida','quick_sales',v_sale.id::text,to_jsonb(v_sale),jsonb_build_object('items',p_items));

  return jsonb_build_object('sale',to_jsonb(v_sale),'items',(
    select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_sale.id
  ));
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
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  select * into v_sale from public.quick_sales where id=p_sale_id for update;
  if not found then raise exception 'Venta rápida no encontrada'; end if;
  if v_sale.status='anulada' then return to_jsonb(v_sale); end if;

  for v_item in select * from public.quick_sale_items where sale_id=p_sale_id
  loop
    if v_item.variant_id is null then
      select * into v_inventory from public.inventory where product_id=v_item.product_id and variant_id is null for update;
    else
      select * into v_inventory from public.inventory where product_id=v_item.product_id and variant_id=v_item.variant_id for update;
    end if;
    if found then
      insert into public.inventory_movements(
        inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
      ) values(
        v_inventory.id,'ajuste_positivo',v_item.quantity,v_inventory.physical_stock,v_inventory.physical_stock+v_item.quantity,
        v_inventory.reserved_stock,v_inventory.reserved_stock,'Devolución por anulación de venta rápida '||v_sale.sale_number,v_user_id
      );
      update public.inventory set physical_stock=physical_stock+v_item.quantity,updated_by=v_user_id where id=v_inventory.id;
    end if;
  end loop;

  update public.quick_sales set status='anulada',cancelled_by=v_user_id,cancelled_at=now(),cancellation_reason=p_reason,updated_at=now()
  where id=p_sale_id returning * into v_sale;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(v_user_id,'anular_venta_rapida','quick_sales',v_sale.id::text,to_jsonb(v_sale),jsonb_build_object('reason',p_reason));

  return to_jsonb(v_sale);
end;
$$;

revoke all on function public.create_quick_sale_atomic(uuid,text,text,text,numeric,text,jsonb) from public;
grant execute on function public.create_quick_sale_atomic(uuid,text,text,text,numeric,text,jsonb) to authenticated;
revoke all on function public.cancel_quick_sale_atomic(uuid,text) from public;
grant execute on function public.cancel_quick_sale_atomic(uuid,text) to authenticated;

commit;
