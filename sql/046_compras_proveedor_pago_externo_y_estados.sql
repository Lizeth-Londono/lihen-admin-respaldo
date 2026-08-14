-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 046
-- Compras a proveedor: pagos externos, estados canónicos y compatibilidad
-- Fecha: 2026-08-14
--
-- Objetivos:
-- 1) separar compra, recepción y pago;
-- 2) permitir pagos personales/externos SIN afectar caja LIHEN;
-- 3) eliminar la comparación inválida supplier_request_status = 'anulada';
-- 4) conservar pagos LIHEN con impacto financiero atómico e idempotente;
-- 5) no modificar datos históricos ni saldos existentes.
--
-- Ejecutar DESPUÉS de 045 y antes de desplegar el frontend que invoque
-- register_supplier_payment_v2_atomic.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 0. Diagnóstico recomendado antes de ejecutar (solo lectura)
-- ------------------------------------------------------------
-- select t.typname, e.enumlabel
-- from pg_type t
-- join pg_enum e on e.enumtypid=t.oid
-- where t.typname in ('supplier_request_status','product_status')
-- order by t.typname,e.enumsortorder;
--
-- select status::text, count(*) from public.supplier_requests group by 1 order by 1;
-- select payment_status, count(*) from public.supplier_requests group by 1 order by 1;
-- select reception_status, count(*) from public.supplier_requests group by 1 order by 1;

-- ------------------------------------------------------------
-- 1. Origen del pago: LIHEN o externo/personal
-- ------------------------------------------------------------
alter table public.supplier_payments
  add column if not exists payment_source text not null default 'lihen';

-- Los pagos externos no tienen cuenta ni movimiento financiero de LIHEN.
alter table public.supplier_payments
  alter column financial_account_id drop not null,
  alter column financial_movement_id drop not null;

-- Normaliza cualquier fila histórica previa al nuevo contrato.
update public.supplier_payments
set payment_source = case
  when financial_account_id is null and financial_movement_id is null then 'external'
  else 'lihen'
end
where payment_source is null or trim(payment_source)='' or payment_source='lihen';

alter table public.supplier_payments
  drop constraint if exists supplier_payments_payment_source_allowed;
alter table public.supplier_payments
  add constraint supplier_payments_payment_source_allowed
  check (payment_source in ('lihen','external')) not valid;

alter table public.supplier_payments
  drop constraint if exists supplier_payments_source_consistency;
alter table public.supplier_payments
  add constraint supplier_payments_source_consistency
  check (
    (payment_source='lihen' and financial_account_id is not null)
    or
    (payment_source='external' and financial_account_id is null and financial_movement_id is null)
  ) not valid;

alter table public.supplier_payments validate constraint supplier_payments_payment_source_allowed;
-- source_consistency queda NOT VALID para tolerar filas legacy incompletas;
-- PostgreSQL sí la exige para toda fila nueva o actualizada después de 046.

create index if not exists supplier_payments_source_date_idx
  on public.supplier_payments(payment_source,payment_date desc);

comment on column public.supplier_payments.payment_source is
  'Origen económico del pago: lihen descuenta una cuenta LIHEN; external registra pago personal/externo sin modificar caja LIHEN.';

-- ------------------------------------------------------------
-- 2. RPC V2: pago con impacto financiero opcional
-- ------------------------------------------------------------
create or replace function public.register_supplier_payment_v2_atomic(
  p_supplier_request_id uuid,
  p_account_id uuid,
  p_payment_source text,
  p_amount numeric,
  p_payment_method text,
  p_paid_at timestamptz,
  p_reference_number text,
  p_notes text,
  p_operation_key text
)
returns public.supplier_payments
language plpgsql
security definer
set search_path=''
as $$
declare
  v_purchase public.supplier_requests;
  v_account public.financial_accounts;
  v_movement public.financial_movements;
  v_result public.supplier_payments;
  v_new_paid numeric;
  v_source text := lower(trim(coalesce(p_payment_source,'lihen')));
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;
  if length(trim(coalesce(p_operation_key,''))) < 12 then
    raise exception 'Clave de operación inválida';
  end if;

  select * into v_result
  from public.supplier_payments
  where operation_key=p_operation_key;
  if found then return v_result; end if;

  if v_source not in ('lihen','external') then
    raise exception 'Origen de pago inválido. Usa lihen o external';
  end if;

  select * into v_purchase
  from public.supplier_requests
  where id=p_supplier_request_id
  for update;

  if not found then raise exception 'Compra no encontrada'; end if;
  -- IMPORTANTE: comparar como text evita que PostgreSQL intente convertir
  -- el literal obsoleto "anulada" al enum supplier_request_status.
  if v_purchase.status::text = 'cancelada' then
    raise exception 'La compra está cancelada';
  end if;
  if v_purchase.status::text = 'borrador' then
    raise exception 'Confirma la compra antes de registrar pagos';
  end if;
  if p_amount is null or p_amount<=0 or p_amount>coalesce(v_purchase.balance_due,v_purchase.total_amount,0) then
    raise exception 'Pago inválido o superior al saldo pendiente';
  end if;

  if v_source='lihen' then
    if p_account_id is null then raise exception 'Selecciona una cuenta LIHEN'; end if;

    select * into v_account
    from public.financial_accounts
    where id=p_account_id
    for update;

    if not found or not v_account.active or not v_account.initial_balance_configured then
      raise exception 'Cuenta LIHEN no disponible';
    end if;
    if v_account.current_balance < p_amount then
      raise exception 'Saldo insuficiente en la cuenta seleccionada';
    end if;

    insert into public.financial_movements(
      account_id,movement_type,amount,balance_before,balance_after,
      category,description,source_type,source_id,operation_key,
      performed_by,created_by,occurred_at
    ) values (
      v_account.id,'egreso',p_amount,v_account.current_balance,v_account.current_balance-p_amount,
      'pago_proveedor','Pago a proveedor','supplier_request',v_purchase.id,p_operation_key||':mov',
      auth.uid(),auth.uid(),coalesce(p_paid_at,now())
    ) returning * into v_movement;

    update public.financial_accounts
    set current_balance=v_movement.balance_after,updated_at=now(),updated_by=auth.uid()
    where id=v_account.id;
  else
    -- Pago personal/externo: jamás crear movimiento financiero LIHEN.
    if p_account_id is not null then
      raise exception 'Un pago externo no debe indicar una cuenta LIHEN';
    end if;
    v_movement := null;
  end if;

  insert into public.supplier_payments(
    supplier_request_id,supplier_id,financial_account_id,financial_movement_id,
    amount,payment_method,payment_source,reference_number,notes,
    operation_key,payment_date,created_by
  ) values (
    v_purchase.id,v_purchase.supplier_id,
    case when v_source='lihen' then v_account.id else null end,
    case when v_source='lihen' then v_movement.id else null end,
    p_amount,p_payment_method,v_source,p_reference_number,p_notes,
    p_operation_key,coalesce(p_paid_at,now()),auth.uid()
  ) returning * into v_result;

  v_new_paid := coalesce(v_purchase.amount_paid,0)+p_amount;
  update public.supplier_requests
  set amount_paid=v_new_paid,
      balance_due=greatest(0,total_amount-v_new_paid),
      payment_status=case when v_new_paid>=total_amount then 'pagada' else 'parcial' end,
      updated_by=auth.uid(),
      updated_at=now()
  where id=v_purchase.id;

  return v_result;
end;
$$;

-- ------------------------------------------------------------
-- 3. Compatibilidad: la RPC histórica delega a V2 con origen LIHEN.
--    Esto elimina el bug de `status in ('cancelada','anulada')` sin romper
--    importadores o módulos antiguos que aún llaman a la firma original.
-- ------------------------------------------------------------
create or replace function public.register_supplier_payment_atomic(
  p_supplier_request_id uuid,
  p_account_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_paid_at timestamptz,
  p_reference_number text,
  p_notes text,
  p_operation_key text
)
returns public.supplier_payments
language plpgsql
security definer
set search_path=''
as $$
begin
  return public.register_supplier_payment_v2_atomic(
    p_supplier_request_id,
    p_account_id,
    'lihen',
    p_amount,
    p_payment_method,
    p_paid_at,
    p_reference_number,
    p_notes,
    p_operation_key
  );
end;
$$;

revoke all on function public.register_supplier_payment_v2_atomic(uuid,uuid,text,numeric,text,timestamptz,text,text,text) from public,anon;
grant execute on function public.register_supplier_payment_v2_atomic(uuid,uuid,text,numeric,text,timestamptz,text,text,text) to authenticated;
revoke all on function public.register_supplier_payment_atomic(uuid,uuid,numeric,text,timestamptz,text,text,text) from public,anon;
grant execute on function public.register_supplier_payment_atomic(uuid,uuid,numeric,text,timestamptz,text,text,text) to authenticated;

commit;

-- ============================================================
-- VERIFICACIÓN POST-DESPLIEGUE
-- ============================================================
-- 1) Debe existir payment_source:
-- select column_name,is_nullable,column_default
-- from information_schema.columns
-- where table_schema='public' and table_name='supplier_payments'
--   and column_name in ('payment_source','financial_account_id','financial_movement_id');
--
-- 2) Pago externo NO debe crear movimiento financiero:
-- select sp.id,sp.amount,sp.payment_source,sp.financial_account_id,sp.financial_movement_id
-- from public.supplier_payments sp order by sp.created_at desc limit 20;
--
-- 3) Seguridad:
-- anon no debe recibir permisos nuevos sobre tablas administrativas.
