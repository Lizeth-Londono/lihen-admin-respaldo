-- LIHEN ADMIN - Compras históricas sin impacto en inventario ni caja
begin;

alter table if exists public.supplier_requests
  add column if not exists is_historical boolean not null default false,
  add column if not exists inventory_impact boolean not null default true,
  add column if not exists financial_impact boolean not null default true,
  add column if not exists historical_paid_amount numeric(14,2) not null default 0,
  add column if not exists historical_payment_method text,
  add column if not exists historical_payment_date date,
  add column if not exists historical_source_reference text,
  add column if not exists historical_registered_at timestamptz,
  add column if not exists historical_registered_by uuid;

create index if not exists idx_supplier_requests_historical
  on public.supplier_requests(is_historical, purchase_date desc);

create or replace function public.register_historical_supplier_purchase_atomic(
  p_supplier_id uuid,
  p_purchase_date date,
  p_invoice_number text,
  p_due_date date,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_freight_amount numeric,
  p_historical_paid_amount numeric,
  p_historical_payment_method text,
  p_historical_payment_date date,
  p_source_reference text,
  p_notes text,
  p_items jsonb,
  p_operation_key text
) returns public.supplier_requests
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_purchase public.supplier_requests;
  v_item jsonb;
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
  v_paid numeric(14,2);
  v_qty integer;
  v_cost numeric(14,2);
  v_product uuid;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;
  if coalesce(length(trim(p_operation_key)),0) < 12 then
    raise exception 'Clave de operación inválida';
  end if;

  select * into v_purchase
  from public.supplier_requests
  where operation_key = p_operation_key;
  if found then return v_purchase; end if;

  if not exists(select 1 from public.suppliers where id=p_supplier_id and active=true) then
    raise exception 'Proveedor no encontrado o inactivo';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'La compra histórica debe incluir productos asociados';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity_requested')::integer;
    v_cost := (v_item->>'quoted_unit_cost')::numeric;
    if v_qty <= 0 or v_cost < 0 then raise exception 'Cantidad o costo inválido'; end if;
    if not exists(select 1 from public.products where id=v_product) then
      raise exception 'Producto no encontrado';
    end if;
    v_subtotal := v_subtotal + (v_qty * v_cost);
  end loop;

  v_total := greatest(0, v_subtotal - coalesce(p_discount_amount,0) + coalesce(p_tax_amount,0) + coalesce(p_freight_amount,0));
  v_paid := least(v_total, greatest(0, coalesce(p_historical_paid_amount,0)));

  insert into public.supplier_requests(
    supplier_id,status,purchase_date,invoice_number,due_date,reception_status,payment_status,
    subtotal,discount_amount,tax_amount,freight_amount,total_amount,amount_paid,balance_due,notes,
    operation_key,created_by,updated_by,is_historical,inventory_impact,financial_impact,
    historical_paid_amount,historical_payment_method,historical_payment_date,historical_source_reference,
    historical_registered_at,historical_registered_by
  ) values (
    p_supplier_id,'confirmada',coalesce(p_purchase_date,current_date),nullif(trim(p_invoice_number),''),p_due_date,
    'completa',case when v_paid >= v_total then 'pagada' when v_paid > 0 then 'parcial' else 'pendiente' end,
    v_subtotal,coalesce(p_discount_amount,0),coalesce(p_tax_amount,0),coalesce(p_freight_amount,0),v_total,
    v_paid,greatest(0,v_total-v_paid),p_notes,p_operation_key,v_user,v_user,true,false,false,
    v_paid,nullif(trim(p_historical_payment_method),''),p_historical_payment_date,nullif(trim(p_source_reference),''),
    now(),v_user
  ) returning * into v_purchase;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity_requested')::integer;
    v_cost := (v_item->>'quoted_unit_cost')::numeric;

    insert into public.supplier_request_items(
      supplier_request_id,product_id,quantity_requested,quoted_unit_cost,quantity_received
    ) values (v_purchase.id,v_product,v_qty,v_cost,v_qty);

    update public.supplier_products
       set last_cost = case when v_cost > 0 then v_cost else last_cost end
     where supplier_id=p_supplier_id and product_id=v_product;
    if not found then
      insert into public.supplier_products(supplier_id,product_id,last_cost,preferred)
      values(p_supplier_id,v_product,v_cost,false);
    end if;
  end loop;

  -- Intencionalmente NO modifica inventory, financial_accounts ni financial_movements.
  return v_purchase;
end $$;

revoke all on function public.register_historical_supplier_purchase_atomic(uuid,date,text,date,numeric,numeric,numeric,numeric,text,date,text,text,jsonb,text) from public,anon;
grant execute on function public.register_historical_supplier_purchase_atomic(uuid,date,text,date,numeric,numeric,numeric,numeric,text,date,text,text,jsonb,text) to authenticated;

commit;
