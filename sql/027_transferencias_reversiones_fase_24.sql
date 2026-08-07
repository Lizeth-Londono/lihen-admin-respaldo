begin;

create or replace function public.transfer_financial_funds_atomic(
  p_source_account_id uuid,
  p_destination_account_id uuid,
  p_amount numeric,
  p_description text,
  p_occurred_at timestamptz,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source public.financial_accounts;
  v_destination public.financial_accounts;
  v_group uuid := gen_random_uuid();
  v_out public.financial_movements;
  v_in public.financial_movements;
  v_existing public.financial_movements;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_source_account_id = p_destination_account_id then raise exception 'Las cuentas deben ser diferentes'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'El valor debe ser mayor que cero'; end if;
  if length(coalesce(p_operation_key,'')) < 12 then raise exception 'Clave de operación inválida'; end if;

  select * into v_existing from public.financial_movements where operation_key=p_operation_key||':salida';
  if found then
    select * into v_in from public.financial_movements where operation_key=p_operation_key||':entrada';
    return jsonb_build_object('outgoing',to_jsonb(v_existing),'incoming',to_jsonb(v_in),'recovered',true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(least(p_source_account_id::text,p_destination_account_id::text),0));
  perform pg_advisory_xact_lock(hashtextextended(greatest(p_source_account_id::text,p_destination_account_id::text),0));

  select * into v_source from public.financial_accounts where id=p_source_account_id for update;
  select * into v_destination from public.financial_accounts where id=p_destination_account_id for update;
  if not found then raise exception 'Cuenta destino no encontrada'; end if;
  if v_source.id is null then raise exception 'Cuenta origen no encontrada'; end if;
  if not v_source.active or not v_destination.active then raise exception 'Una de las cuentas está inactiva'; end if;
  if not v_source.initial_balance_configured or not v_destination.initial_balance_configured then raise exception 'Ambas cuentas deben tener saldo inicial configurado'; end if;
  if v_source.current_balance < p_amount then raise exception 'Saldo insuficiente en la cuenta origen'; end if;

  insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,created_by,occurred_at,transfer_group_id)
  values(v_source.id,'transferencia_salida',p_amount,v_source.current_balance,v_source.current_balance-p_amount,'transferencia',coalesce(nullif(trim(p_description),''),'Transferencia entre cuentas'),p_operation_key||':salida',auth.uid(),auth.uid(),coalesce(p_occurred_at,now()),v_group)
  returning * into v_out;

  insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,created_by,occurred_at,transfer_group_id)
  values(v_destination.id,'transferencia_entrada',p_amount,v_destination.current_balance,v_destination.current_balance+p_amount,'transferencia',coalesce(nullif(trim(p_description),''),'Transferencia entre cuentas'),p_operation_key||':entrada',auth.uid(),auth.uid(),coalesce(p_occurred_at,now()),v_group)
  returning * into v_in;

  update public.financial_accounts set current_balance=v_out.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_source.id;
  update public.financial_accounts set current_balance=v_in.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_destination.id;

  return jsonb_build_object('outgoing',to_jsonb(v_out),'incoming',to_jsonb(v_in),'recovered',false);
end $$;

create or replace function public.reverse_financial_movement_atomic(
  p_movement_id uuid,
  p_reason text,
  p_operation_key text
)
returns public.financial_movements
language plpgsql
security definer
set search_path=''
as $$
declare
  v_original public.financial_movements;
  v_account public.financial_accounts;
  v_reverse public.financial_movements;
  v_delta numeric;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if length(trim(coalesce(p_reason,''))) < 8 then raise exception 'Escribe un motivo claro para la reversión'; end if;
  select * into v_reverse from public.financial_movements where operation_key=p_operation_key;
  if found then return v_reverse; end if;

  select * into v_original from public.financial_movements where id=p_movement_id for update;
  if not found then raise exception 'Movimiento no encontrado'; end if;
  if v_original.status <> 'activo' then raise exception 'El movimiento ya fue reversado'; end if;
  if v_original.movement_type in ('saldo_inicial','transferencia_entrada','transferencia_salida','reversion') then raise exception 'Este movimiento no se puede reversar desde esta opción'; end if;

  select * into v_account from public.financial_accounts where id=v_original.account_id for update;
  v_delta := case when v_original.movement_type in ('ingreso','ajuste_positivo') then -v_original.amount else v_original.amount end;
  if v_account.current_balance + v_delta < 0 then raise exception 'Saldo insuficiente para reversar el movimiento'; end if;

  insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,created_by,occurred_at,reversal_of_id,source_type,source_id)
  values(v_account.id,'reversion',v_original.amount,v_account.current_balance,v_account.current_balance+v_delta,'reversion',trim(p_reason),p_operation_key,auth.uid(),auth.uid(),now(),v_original.id,v_original.source_type,v_original.source_id)
  returning * into v_reverse;

  update public.financial_accounts set current_balance=v_reverse.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_account.id;
  update public.financial_movements set status='reversado' where id=v_original.id;
  return v_reverse;
end $$;

-- Corrige la RPC de pagos para el modelo consolidado de la fase 20.
create or replace function public.register_supplier_payment_atomic(p_supplier_request_id uuid,p_account_id uuid,p_amount numeric,p_payment_method text,p_paid_at timestamptz,p_reference_number text,p_notes text,p_operation_key text)
returns public.supplier_payments language plpgsql security definer set search_path=''
as $$ declare p public.supplier_requests; a public.financial_accounts; m public.financial_movements; result public.supplier_payments; new_paid numeric; begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 select * into result from public.supplier_payments where operation_key=p_operation_key; if found then return result; end if;
 select * into p from public.supplier_requests where id=p_supplier_request_id for update; if not found or p.status in ('cancelada','anulada') then raise exception 'Compra no disponible'; end if;
 if p_amount<=0 or p_amount>coalesce(p.balance_due,p.total_amount) then raise exception 'Pago inválido o superior al saldo pendiente'; end if;
 select * into a from public.financial_accounts where id=p_account_id for update; if not found or not a.active or not a.initial_balance_configured or a.current_balance<p_amount then raise exception 'Cuenta no disponible o saldo insuficiente'; end if;
 insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,source_type,source_id,operation_key,performed_by,created_by,occurred_at)
 values(a.id,'egreso',p_amount,a.current_balance,a.current_balance-p_amount,'pago_proveedor','Pago a proveedor','supplier_request',p.id,p_operation_key||':mov',auth.uid(),auth.uid(),coalesce(p_paid_at,now())) returning * into m;
 update public.financial_accounts set current_balance=m.balance_after,updated_at=now(),updated_by=auth.uid() where id=a.id;
 insert into public.supplier_payments(supplier_request_id,supplier_id,financial_account_id,financial_movement_id,amount,payment_method,reference_number,notes,operation_key,payment_date,created_by)
 values(p.id,p.supplier_id,a.id,m.id,p_amount,p_payment_method,p_reference_number,p_notes,p_operation_key,coalesce(p_paid_at,now()),auth.uid()) returning * into result;
 new_paid:=coalesce(p.amount_paid,0)+p_amount;
 update public.supplier_requests set amount_paid=new_paid,balance_due=greatest(0,total_amount-new_paid),payment_status=case when new_paid>=total_amount then 'pagada' else 'parcial' end,updated_by=auth.uid() where id=p.id;
 return result;
end $$;

grant execute on function public.transfer_financial_funds_atomic(uuid,uuid,numeric,text,timestamptz,text) to authenticated;
grant execute on function public.reverse_financial_movement_atomic(uuid,text,text) to authenticated;
grant execute on function public.register_supplier_payment_atomic(uuid,uuid,numeric,text,timestamptz,text,text,text) to authenticated;
revoke all on function public.transfer_financial_funds_atomic(uuid,uuid,numeric,text,timestamptz,text) from anon;
revoke all on function public.reverse_financial_movement_atomic(uuid,text,text) from anon;

commit;
