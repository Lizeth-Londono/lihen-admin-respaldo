-- LIHEN ADMIN - Consolidación funcional real de fases 2 a 15
begin;

alter table if exists public.supplier_requests
  add column if not exists purchase_date date default current_date,
  add column if not exists invoice_number text,
  add column if not exists due_date date,
  add column if not exists reception_status text default 'pendiente',
  add column if not exists payment_status text default 'pendiente',
  add column if not exists subtotal numeric(14,2) default 0,
  add column if not exists discount_amount numeric(14,2) default 0,
  add column if not exists tax_amount numeric(14,2) default 0,
  add column if not exists freight_amount numeric(14,2) default 0,
  add column if not exists total_amount numeric(14,2) default 0,
  add column if not exists amount_paid numeric(14,2) default 0,
  add column if not exists balance_due numeric(14,2) default 0,
  add column if not exists operation_key text;

create unique index if not exists ux_supplier_requests_operation_key
  on public.supplier_requests(operation_key) where operation_key is not null;

create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_type text not null default 'otro' check (account_type in ('billetera_digital','efectivo','banco','otro')),
  currency_code text not null default 'COP' check (currency_code='COP'),
  initial_balance numeric(14,2) not null default 0 check (initial_balance >= 0),
  current_balance numeric(14,2) not null default 0,
  initial_balance_date date,
  initial_balance_configured boolean not null default false,
  active boolean not null default true,
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.financial_movements (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  movement_type text not null check (movement_type in ('saldo_inicial','ingreso','egreso','ajuste_positivo','ajuste_negativo','transferencia_entrada','transferencia_salida','reversion')),
  amount numeric(14,2) not null check (amount > 0),
  balance_before numeric(14,2) not null,
  balance_after numeric(14,2) not null,
  category text not null,
  description text,
  source_type text,
  source_id uuid,
  reference_number text,
  operation_key text not null unique,
  transfer_group_id uuid,
  reversal_of_id uuid references public.financial_movements(id) on delete restrict,
  status text not null default 'activo' check (status in ('activo','reversado')),
  occurred_at timestamptz not null default now(),
  performed_by uuid default auth.uid(),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_request_id uuid not null references public.supplier_requests(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  financial_movement_id uuid unique references public.financial_movements(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null,
  reference_number text,
  notes text,
  status text not null default 'activo' check (status in ('activo','anulado')),
  operation_key text not null unique,
  payment_date timestamptz not null default now(),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

insert into public.financial_accounts(code,name,account_type)
values ('nequi','Nequi','billetera_digital'),('efectivo','Efectivo físico','efectivo')
on conflict (code) do nothing;

create or replace function public.create_supplier_purchase_atomic(
  p_supplier_id uuid,
  p_purchase_date date,
  p_expected_date date,
  p_invoice_number text,
  p_due_date date,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_freight_amount numeric,
  p_notes text,
  p_items jsonb,
  p_operation_key text
) returns public.supplier_requests
language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid := auth.uid(); v_purchase public.supplier_requests; v_item jsonb;
  v_subtotal numeric(14,2) := 0; v_total numeric(14,2); v_qty int; v_cost numeric(14,2); v_product uuid;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if coalesce(length(trim(p_operation_key)),0) < 12 then raise exception 'Clave de operación inválida'; end if;
  select * into v_purchase from public.supplier_requests where operation_key=p_operation_key;
  if found then return v_purchase; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and active=true) then raise exception 'Proveedor no encontrado o inactivo'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'La compra debe incluir productos'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product=(v_item->>'product_id')::uuid; v_qty=(v_item->>'quantity_requested')::int; v_cost=(v_item->>'quoted_unit_cost')::numeric;
    if v_qty<=0 or v_cost<0 then raise exception 'Cantidad o costo inválido'; end if;
    if not exists(select 1 from public.products where id=v_product) then raise exception 'Producto no encontrado'; end if;
    v_subtotal := v_subtotal + v_qty*v_cost;
  end loop;
  v_total := greatest(0,v_subtotal-coalesce(p_discount_amount,0)+coalesce(p_tax_amount,0)+coalesce(p_freight_amount,0));
  insert into public.supplier_requests(supplier_id,status,purchase_date,expected_date,invoice_number,due_date,reception_status,payment_status,subtotal,discount_amount,tax_amount,freight_amount,total_amount,amount_paid,balance_due,notes,operation_key,created_by,updated_by)
  values(p_supplier_id,'borrador',coalesce(p_purchase_date,current_date),p_expected_date,nullif(trim(p_invoice_number),''),p_due_date,'pendiente','pendiente',v_subtotal,coalesce(p_discount_amount,0),coalesce(p_tax_amount,0),coalesce(p_freight_amount,0),v_total,0,v_total,p_notes,p_operation_key,v_user,v_user)
  returning * into v_purchase;
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into public.supplier_request_items(supplier_request_id,product_id,quantity_requested,quoted_unit_cost)
    values(v_purchase.id,(v_item->>'product_id')::uuid,(v_item->>'quantity_requested')::int,(v_item->>'quoted_unit_cost')::numeric);
  end loop;
  return v_purchase;
end $$;

create or replace function public.confirm_supplier_purchase_atomic(p_supplier_request_id uuid,p_operation_key text)
returns public.supplier_requests language plpgsql security definer set search_path=''
as $$ declare v public.supplier_requests; v_user uuid:=auth.uid(); begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  select * into v from public.supplier_requests where id=p_supplier_request_id for update;
  if not found then raise exception 'Compra no encontrada'; end if;
  if v.status<>'borrador' then return v; end if;
  update public.supplier_requests set status='confirmada',updated_by=v_user where id=v.id returning * into v;
  update public.inventory i set pending_stock=i.pending_stock+sri.quantity_requested,updated_by=v_user
  from public.supplier_request_items sri where sri.supplier_request_id=v.id and i.product_id=sri.product_id and i.variant_id is not distinct from sri.variant_id;
  return v;
end $$;

create or replace function public.configure_initial_balance_atomic(p_account_id uuid,p_amount numeric,p_effective_date date,p_reason text,p_operation_key text)
returns public.financial_accounts language plpgsql security definer set search_path=''
as $$ declare v public.financial_accounts; v_user uuid:=auth.uid(); begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 if p_amount<0 then raise exception 'Saldo inválido'; end if;
 select * into v from public.financial_accounts where id=p_account_id for update;
 if not found or not v.active then raise exception 'Cuenta no disponible'; end if;
 if v.initial_balance_configured then raise exception 'El saldo inicial ya fue configurado'; end if;
 update public.financial_accounts set initial_balance=p_amount,current_balance=p_amount,initial_balance_date=p_effective_date,initial_balance_configured=true,updated_by=v_user,updated_at=now() where id=v.id returning * into v;
 if p_amount>0 then insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,occurred_at) values(v.id,'saldo_inicial',p_amount,0,p_amount,'saldo_inicial',p_reason,p_operation_key,v_user,coalesce(p_effective_date,current_date)::timestamptz); end if;
 return v;
end $$;

create or replace function public.register_financial_movement_atomic(p_account_id uuid,p_movement_type text,p_amount numeric,p_category text,p_description text,p_occurred_at timestamptz,p_operation_key text)
returns public.financial_movements language plpgsql security definer set search_path=''
as $$ declare a public.financial_accounts; m public.financial_movements; delta numeric; begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 select * into m from public.financial_movements where operation_key=p_operation_key; if found then return m; end if;
 if p_amount<=0 then raise exception 'El valor debe ser mayor que cero'; end if;
 select * into a from public.financial_accounts where id=p_account_id for update;
 if not found or not a.active or not a.initial_balance_configured then raise exception 'Cuenta no disponible o sin saldo inicial'; end if;
 delta := case when p_movement_type in ('ingreso','ajuste_positivo') then p_amount when p_movement_type in ('egreso','ajuste_negativo') then -p_amount else null end;
 if delta is null then raise exception 'Tipo de movimiento no permitido'; end if;
 if a.current_balance+delta<0 then raise exception 'Saldo insuficiente'; end if;
 insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,occurred_at)
 values(a.id,p_movement_type,p_amount,a.current_balance,a.current_balance+delta,p_category,p_description,p_operation_key,auth.uid(),coalesce(p_occurred_at,now())) returning * into m;
 update public.financial_accounts set current_balance=m.balance_after,updated_by=auth.uid(),updated_at=now() where id=a.id;
 return m;
end $$;

create or replace function public.register_supplier_payment_atomic(p_supplier_request_id uuid,p_account_id uuid,p_amount numeric,p_payment_method text,p_paid_at timestamptz,p_reference_number text,p_notes text,p_operation_key text)
returns public.supplier_payments language plpgsql security definer set search_path=''
as $$ declare p public.supplier_requests; a public.financial_accounts; m public.financial_movements; result public.supplier_payments; new_paid numeric; begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 select * into result from public.supplier_payments where operation_key=p_operation_key; if found then return result; end if;
 select * into p from public.supplier_requests where id=p_supplier_request_id for update; if not found or p.status='cancelada' then raise exception 'Compra no disponible'; end if;
 if p_amount<=0 or p_amount>p.balance_due then raise exception 'Pago inválido o superior al saldo pendiente'; end if;
 select * into a from public.financial_accounts where id=p_account_id for update; if not found or a.current_balance<p_amount then raise exception 'Saldo insuficiente'; end if;
 insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,source_type,source_id,operation_key,performed_by,occurred_at)
 values(a.id,'egreso',p_amount,a.current_balance,a.current_balance-p_amount,'pago_proveedor','Pago a proveedor','supplier_request',p.id,p_operation_key||':mov',auth.uid(),coalesce(p_paid_at,now())) returning * into m;
 update public.financial_accounts set current_balance=m.balance_after,updated_at=now(),updated_by=auth.uid() where id=a.id;
 insert into public.supplier_payments(supplier_request_id,supplier_id,financial_account_id,financial_movement_id,amount,payment_method,reference_number,notes,operation_key,payment_date,created_by)
 values(p.id,p.supplier_id,a.id,m.id,p_amount,p_payment_method,p_reference_number,p_notes,p_operation_key,coalesce(p_paid_at,now()),auth.uid()) returning * into result;
 new_paid:=p.amount_paid+p_amount;
 update public.supplier_requests set amount_paid=new_paid,balance_due=greatest(0,total_amount-new_paid),payment_status=case when new_paid>=total_amount then 'pagada' else 'parcial' end,updated_by=auth.uid() where id=p.id;
 return result;
end $$;

alter table public.financial_accounts enable row level security;
alter table public.financial_movements enable row level security;
alter table public.supplier_payments enable row level security;

drop policy if exists financial_accounts_read on public.financial_accounts;
create policy financial_accounts_read on public.financial_accounts for select to authenticated using(public.is_active_cofounder());
drop policy if exists financial_movements_read on public.financial_movements;
create policy financial_movements_read on public.financial_movements for select to authenticated using(public.is_active_cofounder());
drop policy if exists supplier_payments_read on public.supplier_payments;
create policy supplier_payments_read on public.supplier_payments for select to authenticated using(public.is_active_cofounder());

revoke all on public.financial_accounts,public.financial_movements,public.supplier_payments from anon;
revoke insert,update,delete on public.financial_accounts,public.financial_movements,public.supplier_payments from authenticated;
grant select on public.financial_accounts,public.financial_movements,public.supplier_payments to authenticated;
grant execute on function public.create_supplier_purchase_atomic(uuid,date,date,text,date,numeric,numeric,numeric,text,jsonb,text) to authenticated;
grant execute on function public.confirm_supplier_purchase_atomic(uuid,text) to authenticated;
grant execute on function public.configure_initial_balance_atomic(uuid,numeric,date,text,text) to authenticated;
grant execute on function public.register_financial_movement_atomic(uuid,text,numeric,text,text,timestamptz,text) to authenticated;
grant execute on function public.register_supplier_payment_atomic(uuid,uuid,numeric,text,timestamptz,text,text,text) to authenticated;

commit;
