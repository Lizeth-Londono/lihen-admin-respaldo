-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 029
-- Fase 24: coherencia y compatibilidad entre migraciones 024–028
--
-- Objetivo:
-- 1) normalizar nombres de columnas que evolucionaron entre fases;
-- 2) conservar compatibilidad con instalaciones parciales anteriores;
-- 3) completar columnas requeridas por las RPC financieras;
-- 4) exponer un diagnóstico ejecutable antes de probar producción.
--
-- Ejecutar después de 028. Es defensiva e idempotente.
-- No crea compras, pagos, saldos ni movimientos ficticios.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Compras: reception_status es el nombre canónico del frontend.
--    receipt_status se conserva como alias de compatibilidad.
-- ------------------------------------------------------------
alter table if exists public.supplier_requests
  add column if not exists reception_status text default 'pendiente',
  add column if not exists receipt_status text default 'pendiente',
  add column if not exists operation_key text,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if to_regclass('public.supplier_requests') is not null then
    update public.supplier_requests
       set reception_status = coalesce(nullif(reception_status,''), nullif(receipt_status,''), 'pendiente'),
           receipt_status = coalesce(nullif(reception_status,''), nullif(receipt_status,''), 'pendiente');
  end if;
end $$;

create or replace function public.sync_supplier_request_reception_status()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if tg_op = 'INSERT' then
    new.reception_status := coalesce(nullif(new.reception_status,''), nullif(new.receipt_status,''), 'pendiente');
    new.receipt_status := new.reception_status;
  else
    if new.reception_status is distinct from old.reception_status then
      new.receipt_status := new.reception_status;
    elsif new.receipt_status is distinct from old.receipt_status then
      new.reception_status := new.receipt_status;
    else
      new.reception_status := coalesce(nullif(new.reception_status,''), 'pendiente');
      new.receipt_status := new.reception_status;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_sync_supplier_request_reception_status on public.supplier_requests;
create trigger trg_sync_supplier_request_reception_status
before insert or update of reception_status, receipt_status
on public.supplier_requests
for each row execute function public.sync_supplier_request_reception_status();

create unique index if not exists ux_supplier_requests_operation_key
  on public.supplier_requests(operation_key)
  where operation_key is not null;

-- ------------------------------------------------------------
-- 2. Cuentas financieras: normaliza moneda y tipos históricos.
-- ------------------------------------------------------------
alter table if exists public.financial_accounts
  add column if not exists currency_code text default 'COP',
  add column if not exists created_by uuid,
  add column if not exists updated_by uuid,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if to_regclass('public.financial_accounts') is not null then
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='financial_accounts' and column_name='currency'
    ) then
      execute $q$
        update public.financial_accounts
           set currency_code = coalesce(nullif(currency_code,''), nullif(currency,''), 'COP')
      $q$;
    else
      update public.financial_accounts set currency_code=coalesce(nullif(currency_code,''),'COP');
    end if;

    update public.financial_accounts
       set account_type = case lower(coalesce(account_type,''))
         when 'wallet' then 'billetera_digital'
         when 'cash' then 'efectivo'
         when 'bank' then 'banco'
         when 'billetera_digital' then 'billetera_digital'
         when 'efectivo' then 'efectivo'
         when 'banco' then 'banco'
         else 'otro'
       end;
  end if;
end $$;

do $$
declare c record;
begin
  if to_regclass('public.financial_accounts') is null then return; end if;
  for c in
    select conname
      from pg_constraint
     where conrelid='public.financial_accounts'::regclass
       and contype='c'
       and pg_get_constraintdef(oid) ilike '%account_type%'
  loop
    execute format('alter table public.financial_accounts drop constraint %I', c.conname);
  end loop;
  if not exists(select 1 from pg_constraint where conname='financial_accounts_account_type_allowed') then
    alter table public.financial_accounts
      add constraint financial_accounts_account_type_allowed
      check (account_type in ('billetera_digital','efectivo','banco','otro')) not valid;
  end if;
end $$;

-- ------------------------------------------------------------
-- 3. Libro financiero: completa columnas usadas por 026–028.
-- ------------------------------------------------------------
alter table if exists public.financial_movements
  add column if not exists reference_number text,
  add column if not exists transfer_group_id uuid,
  add column if not exists reversal_of_id uuid references public.financial_movements(id) on delete restrict,
  add column if not exists performed_by uuid,
  add column if not exists created_by uuid,
  add column if not exists source_type text,
  add column if not exists source_id uuid,
  add column if not exists description text,
  add column if not exists category text,
  add column if not exists occurred_at timestamptz not null default now();

do $$
begin
  if to_regclass('public.financial_movements') is not null then
    update public.financial_movements
       set performed_by=coalesce(performed_by,created_by),
           created_by=coalesce(created_by,performed_by);
  end if;
end $$;

do $$
declare c record;
begin
  if to_regclass('public.financial_movements') is null then return; end if;
  for c in
    select conname
      from pg_constraint
     where conrelid='public.financial_movements'::regclass
       and contype='c'
       and pg_get_constraintdef(oid) ilike '%movement_type%'
  loop
    execute format('alter table public.financial_movements drop constraint %I', c.conname);
  end loop;
  if not exists(select 1 from pg_constraint where conname='financial_movements_type_allowed') then
    alter table public.financial_movements
      add constraint financial_movements_type_allowed check (
        movement_type in (
          'saldo_inicial','ingreso','egreso','ajuste_positivo','ajuste_negativo',
          'transferencia_entrada','transferencia_salida','reversion'
        )
      ) not valid;
  end if;
end $$;

create index if not exists financial_movements_account_date_idx
  on public.financial_movements(account_id,occurred_at desc);
create index if not exists financial_movements_source_idx
  on public.financial_movements(source_type,source_id);
create index if not exists financial_movements_transfer_group_idx
  on public.financial_movements(transfer_group_id)
  where transfer_group_id is not null;

-- ------------------------------------------------------------
-- 4. Pagos a proveedores: nombres canónicos usados por JS/reportes.
-- ------------------------------------------------------------
alter table if exists public.supplier_payments
  add column if not exists financial_account_id uuid references public.financial_accounts(id) on delete restrict,
  add column if not exists payment_date timestamptz default now(),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid,
  add column if not exists cancellation_reason text;

do $$
begin
  if to_regclass('public.supplier_payments') is null then return; end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='supplier_payments' and column_name='account_id'
  ) then
    execute $q$
      update public.supplier_payments
         set financial_account_id=coalesce(financial_account_id,account_id)
    $q$;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='supplier_payments' and column_name='paid_at'
  ) then
    execute $q$
      update public.supplier_payments
         set payment_date=coalesce(payment_date,paid_at,created_at,now())
    $q$;
  else
    update public.supplier_payments
       set payment_date=coalesce(payment_date,created_at,now());
  end if;
end $$;

create index if not exists supplier_payments_request_date_idx
  on public.supplier_payments(supplier_request_id,payment_date desc);
create index if not exists supplier_payments_account_date_idx
  on public.supplier_payments(financial_account_id,payment_date desc);
create unique index if not exists supplier_payments_operation_key_uidx
  on public.supplier_payments(operation_key);
create unique index if not exists supplier_payments_financial_movement_uidx
  on public.supplier_payments(financial_movement_id)
  where financial_movement_id is not null;

-- ------------------------------------------------------------
-- 5. Vista de conciliación recompilada con nombres canónicos.
-- ------------------------------------------------------------
-- PostgreSQL no permite renombrar/reordenar columnas con CREATE OR REPLACE VIEW.
-- Se elimina la vista técnica y se recrea; no contiene datos almacenados.
drop view if exists public.v_supplier_purchase_account_status;

create view public.v_supplier_purchase_account_status as
select
  sr.id as supplier_request_id,
  sr.supplier_id,
  sr.status as purchase_status,
  sr.reception_status,
  sr.payment_status,
  sr.total_amount,
  sr.amount_paid as stored_amount_paid,
  sr.balance_due as stored_balance_due,
  coalesce(sum(sp.amount) filter (where sp.status='activo'),0)::numeric(14,2) as active_payments_total,
  greatest(0,coalesce(sr.total_amount,0)-coalesce(sum(sp.amount) filter (where sp.status='activo'),0))::numeric(14,2) as calculated_balance_due,
  max(sp.payment_date) filter (where sp.status='activo') as last_payment_at
from public.supplier_requests sr
left join public.supplier_payments sp on sp.supplier_request_id=sr.id
group by sr.id;

grant select on public.v_supplier_purchase_account_status to authenticated;

-- ------------------------------------------------------------
-- 6. Diagnóstico ejecutable del esquema instalado.
-- ------------------------------------------------------------
create or replace function public.validate_lihen_schema_coherence()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_missing_columns jsonb;
  v_missing_functions jsonb;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  select coalesce(jsonb_agg(format('%s.%s',required.table_name,required.column_name) order by required.table_name,required.column_name),'[]'::jsonb)
    into v_missing_columns
  from (values
    ('supplier_requests','reception_status'),
    ('supplier_requests','payment_status'),
    ('supplier_requests','total_amount'),
    ('supplier_requests','balance_due'),
    ('financial_accounts','current_balance'),
    ('financial_accounts','initial_balance_configured'),
    ('financial_movements','operation_key'),
    ('financial_movements','performed_by'),
    ('financial_movements','transfer_group_id'),
    ('financial_movements','reversal_of_id'),
    ('supplier_payments','financial_account_id'),
    ('supplier_payments','payment_date'),
    ('quick_sales','financial_account_id'),
    ('quick_sales','financial_movement_id'),
    ('payments','financial_account_id'),
    ('payments','financial_movement_id')
  ) as required(table_name,column_name)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema='public'
      and c.table_name=required.table_name
      and c.column_name=required.column_name
  );

  select coalesce(jsonb_agg(required.signature order by required.signature),'[]'::jsonb)
    into v_missing_functions
  from (values
    ('public.create_supplier_purchase_atomic'),
    ('public.confirm_supplier_purchase_atomic'),
    ('public.configure_initial_balance_atomic'),
    ('public.register_financial_movement_atomic'),
    ('public.register_supplier_payment_atomic'),
    ('public.transfer_financial_funds_atomic'),
    ('public.reverse_financial_movement_atomic'),
    ('public.import_inventory_batch_atomic'),
    ('public.create_quick_sale_financial_atomic_idempotent'),
    ('public.cancel_quick_sale_financial_atomic_idempotent'),
    ('public.close_order_direct_financial_atomic_idempotent')
  ) as required(signature)
  where to_regprocedure(required.signature || case
    when required.signature='public.create_supplier_purchase_atomic' then '(uuid,date,date,text,date,numeric,numeric,numeric,text,jsonb,text)'
    when required.signature='public.confirm_supplier_purchase_atomic' then '(uuid,text)'
    when required.signature='public.configure_initial_balance_atomic' then '(uuid,numeric,date,text,text)'
    when required.signature='public.register_financial_movement_atomic' then '(uuid,text,numeric,text,text,timestamptz,text)'
    when required.signature='public.register_supplier_payment_atomic' then '(uuid,uuid,numeric,text,timestamptz,text,text,text)'
    when required.signature='public.transfer_financial_funds_atomic' then '(uuid,uuid,numeric,text,timestamptz,text)'
    when required.signature='public.reverse_financial_movement_atomic' then '(uuid,text,text)'
    when required.signature='public.import_inventory_batch_atomic' then '(text,text,integer,integer,jsonb)'
    when required.signature='public.create_quick_sale_financial_atomic_idempotent' then '(text,uuid,text,uuid,text,text,numeric,text,jsonb)'
    when required.signature='public.cancel_quick_sale_financial_atomic_idempotent' then '(text,uuid,text)'
    when required.signature='public.close_order_direct_financial_atomic_idempotent' then '(text,uuid,text,uuid,text,text,text)'
    else '()' end) is null;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_missing_columns)=0 and jsonb_array_length(v_missing_functions)=0,
    'missing_columns',v_missing_columns,
    'missing_functions',v_missing_functions,
    'checked_at',now()
  );
end $$;

revoke all on function public.validate_lihen_schema_coherence() from public,anon;
grant execute on function public.validate_lihen_schema_coherence() to authenticated;

commit;
