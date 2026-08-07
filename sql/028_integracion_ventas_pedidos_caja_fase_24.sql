begin;

alter table public.quick_sales
  add column if not exists financial_account_id uuid references public.financial_accounts(id) on delete restrict,
  add column if not exists financial_movement_id uuid references public.financial_movements(id) on delete restrict;

alter table public.payments
  add column if not exists financial_account_id uuid references public.financial_accounts(id) on delete restrict,
  add column if not exists financial_movement_id uuid references public.financial_movements(id) on delete restrict;

create unique index if not exists quick_sales_financial_movement_uidx
  on public.quick_sales(financial_movement_id) where financial_movement_id is not null;
create unique index if not exists payments_financial_movement_uidx
  on public.payments(financial_movement_id) where financial_movement_id is not null;
create index if not exists quick_sales_financial_account_idx on public.quick_sales(financial_account_id);
create index if not exists payments_financial_account_idx on public.payments(financial_account_id);

create or replace function public.create_quick_sale_financial_atomic_idempotent(
  p_operation_key text,
  p_customer_id uuid default null,
  p_payment_method text default 'efectivo',
  p_financial_account_id uuid default null,
  p_payment_reference text default null,
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_existing public.quick_sales;
  v_result jsonb;
  v_sale public.quick_sales;
  v_account public.financial_accounts;
  v_movement public.financial_movements;
  v_movement_key text := p_operation_key || ':ingreso';
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_financial_account_id is null then raise exception 'Selecciona la cuenta que recibió el dinero'; end if;

  select * into v_existing from public.quick_sales where financial_movement_id in (
    select id from public.financial_movements where operation_key=v_movement_key
  );
  if found then
    return jsonb_build_object(
      'sale',to_jsonb(v_existing),
      'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_existing.id),
      'idempotent',true
    );
  end if;

  select * into v_account from public.financial_accounts where id=p_financial_account_id for update;
  if not found or not v_account.active or not v_account.initial_balance_configured then
    raise exception 'La cuenta seleccionada no está disponible o no tiene saldo inicial configurado';
  end if;

  v_result := public.create_quick_sale_atomic_idempotent(
    p_operation_key,p_customer_id,p_payment_method,p_payment_reference,
    p_discount_type,p_discount_value,p_notes,p_items
  );
  v_sale := jsonb_populate_record(null::public.quick_sales,v_result->'sale');

  if v_sale.financial_movement_id is null then
    insert into public.financial_movements(
      account_id,movement_type,amount,balance_before,balance_after,category,description,
      source_type,source_id,operation_key,performed_by,occurred_at
    ) values (
      v_account.id,'ingreso',v_sale.total,v_account.current_balance,v_account.current_balance+v_sale.total,
      'venta_rapida','Ingreso por venta rápida '||v_sale.sale_number,'quick_sale',v_sale.id,
      v_movement_key,auth.uid(),coalesce(v_sale.created_at,now())
    ) returning * into v_movement;

    update public.financial_accounts
      set current_balance=v_movement.balance_after,updated_by=auth.uid(),updated_at=now()
      where id=v_account.id;
    update public.quick_sales
      set financial_account_id=v_account.id,financial_movement_id=v_movement.id
      where id=v_sale.id returning * into v_sale;
  end if;

  return jsonb_build_object(
    'sale',to_jsonb(v_sale),
    'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_sale.id),
    'idempotent',coalesce((v_result->>'idempotent')::boolean,false)
  );
end;
$$;

create or replace function public.cancel_quick_sale_financial_atomic_idempotent(
  p_operation_key text,
  p_sale_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sale public.quick_sales;
  v_account public.financial_accounts;
  v_original public.financial_movements;
  v_reverse public.financial_movements;
  v_result jsonb;
  v_reverse_key text := p_operation_key || ':reintegro';
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  select * into v_sale from public.quick_sales where id=p_sale_id for update;
  if not found then raise exception 'Venta no encontrada'; end if;
  if v_sale.financial_account_id is null or v_sale.financial_movement_id is null then
    raise exception 'La venta no tiene un movimiento financiero asociado';
  end if;

  select * into v_reverse from public.financial_movements where operation_key=v_reverse_key;
  if found then return jsonb_build_object('sale_id',p_sale_id,'financial_reversal',to_jsonb(v_reverse),'idempotent',true); end if;

  select * into v_account from public.financial_accounts where id=v_sale.financial_account_id for update;
  select * into v_original from public.financial_movements where id=v_sale.financial_movement_id for update;
  if v_account.current_balance < v_sale.total then raise exception 'Saldo insuficiente en la cuenta para anular esta venta'; end if;

  v_result := public.cancel_quick_sale_atomic_idempotent(p_operation_key,p_sale_id,p_reason);

  insert into public.financial_movements(
    account_id,movement_type,amount,balance_before,balance_after,category,description,
    source_type,source_id,operation_key,performed_by,occurred_at
  ) values (
    v_account.id,'egreso',v_sale.total,v_account.current_balance,v_account.current_balance-v_sale.total,
    'anulacion_venta','Reintegro por anulación de '||v_sale.sale_number,'quick_sale',v_sale.id,
    v_reverse_key,auth.uid(),now()
  ) returning * into v_reverse;

  update public.financial_accounts set current_balance=v_reverse.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_account.id;
  update public.financial_movements set status='reversado' where id=v_original.id and status='activo';

  return v_result || jsonb_build_object('financial_reversal',to_jsonb(v_reverse));
end;
$$;

create or replace function public.close_order_direct_financial_atomic_idempotent(
  p_operation_key text,
  p_order_id uuid,
  p_payment_method text,
  p_financial_account_id uuid,
  p_reason text,
  p_reference_number text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order public.orders;
  v_account public.financial_accounts;
  v_payment public.payments;
  v_movement public.financial_movements;
  v_result jsonb;
  v_movement_key text := p_operation_key || ':ingreso';
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_financial_account_id is null then raise exception 'Selecciona la cuenta que recibió el dinero'; end if;

  select * into v_movement from public.financial_movements where operation_key=v_movement_key;
  if found then
    select * into v_order from public.orders where id=p_order_id;
    return jsonb_build_object('order',to_jsonb(v_order),'financial_movement',to_jsonb(v_movement),'idempotent',true);
  end if;

  select * into v_account from public.financial_accounts where id=p_financial_account_id for update;
  if not found or not v_account.active or not v_account.initial_balance_configured then
    raise exception 'La cuenta seleccionada no está disponible o no tiene saldo inicial configurado';
  end if;

  v_result := public.close_order_direct_atomic_idempotent(
    p_operation_key,p_order_id,p_payment_method,p_reason,p_reference_number,p_notes
  );
  select * into v_order from public.orders where id=p_order_id for update;

  select * into v_payment
  from public.payments
  where order_id=p_order_id and status='pagado'::public.payment_status
  order by payment_date desc, created_at desc
  limit 1
  for update;
  if not found then raise exception 'No se encontró el pago creado para el pedido'; end if;

  if v_payment.financial_movement_id is null then
    insert into public.financial_movements(
      account_id,movement_type,amount,balance_before,balance_after,category,description,
      source_type,source_id,operation_key,performed_by,occurred_at
    ) values (
      v_account.id,'ingreso',v_payment.amount,v_account.current_balance,v_account.current_balance+v_payment.amount,
      'pago_pedido','Ingreso por pedido '||v_order.order_number,'order',v_order.id,
      v_movement_key,auth.uid(),coalesce(v_payment.payment_date,now())
    ) returning * into v_movement;

    update public.financial_accounts set current_balance=v_movement.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_account.id;
    update public.payments set financial_account_id=v_account.id,financial_movement_id=v_movement.id where id=v_payment.id returning * into v_payment;
  end if;

  return v_result || jsonb_build_object('financial_movement',to_jsonb(v_movement),'payment',to_jsonb(v_payment));
end;
$$;

revoke all on function public.create_quick_sale_financial_atomic_idempotent(text,uuid,text,uuid,text,text,numeric,text,jsonb) from public,anon;
grant execute on function public.create_quick_sale_financial_atomic_idempotent(text,uuid,text,uuid,text,text,numeric,text,jsonb) to authenticated;
revoke all on function public.cancel_quick_sale_financial_atomic_idempotent(text,uuid,text) from public,anon;
grant execute on function public.cancel_quick_sale_financial_atomic_idempotent(text,uuid,text) to authenticated;
revoke all on function public.close_order_direct_financial_atomic_idempotent(text,uuid,text,uuid,text,text,text) from public,anon;
grant execute on function public.close_order_direct_financial_atomic_idempotent(text,uuid,text,uuid,text,text,text) to authenticated;

commit;
