-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 024
-- Fase 20: modelo de datos consolidado y extensible
--
-- Objetivo:
-- 1) adaptar el esquema existente sin duplicar supplier_requests;
-- 2) separar compra, recepción, pago, inventario y dinero;
-- 3) establecer relaciones, índices, restricciones y trazabilidad;
-- 4) preparar el esquema para las fases funcionales posteriores.
--
-- Ejecutar después de las migraciones base y de 023.
-- Migración defensiva e idempotente. No inserta saldos ni operaciones falsas.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Solicitudes existentes convertibles en compras de proveedor
-- ------------------------------------------------------------
alter table public.supplier_requests
  add column if not exists purchase_date date,
  add column if not exists invoice_number text,
  add column if not exists due_date date,
  add column if not exists receipt_status text not null default 'pendiente',
  add column if not exists payment_status text not null default 'pendiente',
  add column if not exists subtotal numeric(14,2) not null default 0,
  add column if not exists discount_amount numeric(14,2) not null default 0,
  add column if not exists tax_amount numeric(14,2) not null default 0,
  add column if not exists freight_amount numeric(14,2) not null default 0,
  add column if not exists total_amount numeric(14,2) not null default 0,
  add column if not exists amount_paid numeric(14,2) not null default 0,
  add column if not exists balance_due numeric(14,2) not null default 0,
  add column if not exists confirmed_at timestamptz,
  add column if not exists confirmed_by uuid references public.profiles(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references public.profiles(id),
  add column if not exists cancellation_reason text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.supplier_request_items
  add column if not exists line_subtotal numeric(14,2) not null default 0,
  add column if not exists quantity_cancelled integer not null default 0,
  add column if not exists updated_at timestamptz not null default now();

-- Restricciones nuevas como NOT VALID para tolerar datos históricos.
do $$
begin
  if not exists (select 1 from pg_constraint where conname='supplier_requests_amounts_nonnegative') then
    alter table public.supplier_requests add constraint supplier_requests_amounts_nonnegative check (
      subtotal >= 0 and discount_amount >= 0 and tax_amount >= 0 and freight_amount >= 0
      and total_amount >= 0 and amount_paid >= 0 and balance_due >= 0
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='supplier_requests_payment_status_allowed') then
    alter table public.supplier_requests add constraint supplier_requests_payment_status_allowed check (
      payment_status in ('pendiente','parcial','pagada','anulada')
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='supplier_requests_receipt_status_allowed') then
    alter table public.supplier_requests add constraint supplier_requests_receipt_status_allowed check (
      receipt_status in ('pendiente','parcial','completa','anulada')
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='supplier_request_items_quantities_valid') then
    alter table public.supplier_request_items add constraint supplier_request_items_quantities_valid check (
      quantity_requested > 0 and quantity_received >= 0 and quantity_cancelled >= 0
      and quantity_received + quantity_cancelled <= quantity_requested
    ) not valid;
  end if;
end $$;

create index if not exists supplier_requests_supplier_purchase_date_idx
  on public.supplier_requests(supplier_id, purchase_date desc);
create index if not exists supplier_requests_payment_status_due_date_idx
  on public.supplier_requests(payment_status, due_date)
  where payment_status in ('pendiente','parcial');
create index if not exists supplier_requests_receipt_status_idx
  on public.supplier_requests(receipt_status);
create index if not exists supplier_request_items_request_product_idx
  on public.supplier_request_items(supplier_request_id, product_id);

-- ------------------------------------------------------------
-- 2. Recepciones: evento separado de la compra
-- ------------------------------------------------------------
create table if not exists public.supplier_purchase_receipts (
  id uuid primary key default gen_random_uuid(),
  supplier_request_id uuid not null references public.supplier_requests(id) on delete restrict,
  receipt_number text,
  received_at timestamptz not null default now(),
  notes text,
  operation_key text not null,
  status text not null default 'aplicada' check (status in ('aplicada','reversada')),
  created_by uuid not null references public.profiles(id),
  reversed_at timestamptz,
  reversed_by uuid references public.profiles(id),
  reversal_reason text,
  created_at timestamptz not null default now(),
  unique(operation_key)
);

create table if not exists public.supplier_purchase_receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.supplier_purchase_receipts(id) on delete cascade,
  supplier_request_item_id uuid not null references public.supplier_request_items(id) on delete restrict,
  inventory_id uuid not null references public.inventory(id) on delete restrict,
  quantity_received integer not null check (quantity_received > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  physical_before integer not null check (physical_before >= 0),
  physical_after integer not null check (physical_after >= 0),
  pending_before integer not null check (pending_before >= 0),
  pending_after integer not null check (pending_after >= 0),
  inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(receipt_id, supplier_request_item_id)
);

create index if not exists supplier_purchase_receipts_request_date_idx
  on public.supplier_purchase_receipts(supplier_request_id, received_at desc);
create index if not exists supplier_purchase_receipt_items_inventory_idx
  on public.supplier_purchase_receipt_items(inventory_id);

-- ------------------------------------------------------------
-- 3. Cuentas y movimientos financieros
-- ------------------------------------------------------------
create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_type text not null check (account_type in ('billetera_digital','efectivo','banco','otro')),
  currency_code text not null default 'COP' check (currency_code='COP'),
  initial_balance numeric(14,2) not null default 0 check (initial_balance >= 0),
  initial_balance_date date,
  current_balance numeric(14,2) not null default 0,
  initial_balance_configured boolean not null default false,
  active boolean not null default true,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.financial_movements (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  movement_type text not null check (movement_type in ('ingreso','egreso','ajuste_positivo','ajuste_negativo','transferencia_entrada','transferencia_salida','reversion')),
  category text not null,
  amount numeric(14,2) not null check (amount > 0),
  balance_before numeric(14,2) not null,
  balance_after numeric(14,2) not null,
  occurred_at timestamptz not null default now(),
  source_type text,
  source_id uuid,
  reference_number text,
  description text,
  operation_key text not null,
  transfer_group_id uuid,
  reversal_of_id uuid references public.financial_movements(id) on delete restrict,
  status text not null default 'activo' check (status in ('activo','reversado')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(operation_key)
);

create index if not exists financial_movements_account_date_idx
  on public.financial_movements(account_id, occurred_at desc);
create index if not exists financial_movements_source_idx
  on public.financial_movements(source_type, source_id);
create index if not exists financial_movements_transfer_group_idx
  on public.financial_movements(transfer_group_id)
  where transfer_group_id is not null;
create unique index if not exists financial_movements_one_active_source_unique
  on public.financial_movements(source_type, source_id, category)
  where source_id is not null and status='activo'
    and movement_type not in ('transferencia_entrada','transferencia_salida','reversion');

-- ------------------------------------------------------------
-- 4. Pagos a proveedores: evento financiero separado
-- ------------------------------------------------------------
create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_request_id uuid not null references public.supplier_requests(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  financial_movement_id uuid not null references public.financial_movements(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null,
  payment_date timestamptz not null default now(),
  reference_number text,
  notes text,
  operation_key text not null,
  status text not null default 'activo' check (status in ('activo','anulado')),
  created_by uuid not null references public.profiles(id),
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  unique(operation_key),
  unique(financial_movement_id)
);

create index if not exists supplier_payments_request_date_idx
  on public.supplier_payments(supplier_request_id, payment_date desc);
create index if not exists supplier_payments_supplier_date_idx
  on public.supplier_payments(supplier_id, payment_date desc);
create index if not exists supplier_payments_account_date_idx
  on public.supplier_payments(financial_account_id, payment_date desc);

-- ------------------------------------------------------------
-- 5. Historial de costos de producto
-- ------------------------------------------------------------
create table if not exists public.product_cost_history (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  variant_id uuid,
  supplier_id uuid references public.suppliers(id) on delete set null,
  supplier_request_id uuid references public.supplier_requests(id) on delete set null,
  receipt_item_id uuid references public.supplier_purchase_receipt_items(id) on delete set null,
  previous_product_cost numeric(14,2),
  new_product_cost numeric(14,2) not null check (new_product_cost >= 0),
  previous_average_cost numeric(14,2),
  new_average_cost numeric(14,2) not null check (new_average_cost >= 0),
  purchased_unit_cost numeric(14,2) not null check (purchased_unit_cost >= 0),
  quantity_received integer not null check (quantity_received > 0),
  stock_before integer not null check (stock_before >= 0),
  stock_after integer not null check (stock_after >= 0),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(receipt_item_id)
);

create index if not exists product_cost_history_product_date_idx
  on public.product_cost_history(product_id, created_at desc);
create index if not exists product_cost_history_supplier_idx
  on public.product_cost_history(supplier_id, created_at desc)
  where supplier_id is not null;

-- ------------------------------------------------------------
-- 6. Historial de saldos iniciales
-- ------------------------------------------------------------
create table if not exists public.financial_initial_balance_history (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  change_type text not null check (change_type in ('configuracion','correccion')),
  previous_balance numeric(14,2),
  new_balance numeric(14,2) not null check (new_balance >= 0),
  previous_date date,
  new_date date not null,
  reason text not null check (char_length(trim(reason)) >= 8),
  changed_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists financial_initial_balance_history_account_idx
  on public.financial_initial_balance_history(account_id, created_at desc);

-- ------------------------------------------------------------
-- 7. RLS: lectura de cofundadoras; escritura solo por RPC/funciones
-- ------------------------------------------------------------
alter table public.supplier_purchase_receipts enable row level security;
alter table public.supplier_purchase_receipt_items enable row level security;
alter table public.financial_accounts enable row level security;
alter table public.financial_movements enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.product_cost_history enable row level security;
alter table public.financial_initial_balance_history enable row level security;

-- Políticas de lectura uniformes.
do $$
declare
  v_table text;
  v_policy text;
begin
  foreach v_table in array array[
    'supplier_purchase_receipts',
    'supplier_purchase_receipt_items',
    'financial_accounts',
    'financial_movements',
    'supplier_payments',
    'product_cost_history',
    'financial_initial_balance_history'
  ] loop
    v_policy := 'cofundadoras_consultan_' || v_table;
    execute format('drop policy if exists %I on public.%I', v_policy, v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_active_cofounder())',
      v_policy, v_table
    );
    execute format('revoke all on public.%I from anon', v_table);
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated', v_table);
    execute format('grant select on public.%I to authenticated', v_table);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 8. Vista técnica de relaciones principales
-- ------------------------------------------------------------
create or replace view public.v_supplier_purchase_account_status
with (security_invoker = true)
as
select
  sr.id as supplier_request_id,
  sr.supplier_id,
  sr.purchase_date,
  sr.status as purchase_status,
  sr.receipt_status,
  sr.payment_status,
  sr.total_amount,
  coalesce(sum(sp.amount) filter (where sp.status='activo'), 0)::numeric(14,2) as active_payments,
  greatest(sr.total_amount - coalesce(sum(sp.amount) filter (where sp.status='activo'), 0), 0)::numeric(14,2) as calculated_balance_due,
  max(sp.payment_date) filter (where sp.status='activo') as last_payment_at
from public.supplier_requests sr
left join public.supplier_payments sp on sp.supplier_request_id=sr.id
group by sr.id, sr.supplier_id, sr.purchase_date, sr.status, sr.receipt_status,
         sr.payment_status, sr.total_amount;

grant select on public.v_supplier_purchase_account_status to authenticated;

comment on table public.supplier_purchase_receipts is 'Recepciones físicas de mercancía, separadas de la compra y del pago.';
comment on table public.financial_accounts is 'Cuentas reales de LIHEN, como Nequi y efectivo físico.';
comment on table public.financial_movements is 'Libro de movimientos de dinero; no sustituye movimientos de inventario.';
comment on table public.supplier_payments is 'Pagos parciales o completos hechos a proveedores.';
comment on table public.product_cost_history is 'Historial inmutable de costos producido por recepciones de proveedor.';

commit;
