-- ============================================================
-- LIHEN ADMIN — FASE 21
-- Idempotencia transversal para operaciones sensibles
-- ============================================================
-- Esta migración no reemplaza las restricciones únicas ya existentes.
-- Añade un registro central de ejecución y RPC idempotentes para los
-- flujos disponibles en el proyecto base.

begin;

create table if not exists public.operation_executions (
  id uuid primary key default gen_random_uuid(),
  operation_type text not null,
  operation_key text not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'procesando' check (status in ('procesando','completada','fallida')),
  request_fingerprint text,
  result jsonb,
  error_message text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(operation_type, operation_key)
);

create index if not exists operation_executions_actor_date_idx
  on public.operation_executions(actor_id, created_at desc);
create index if not exists operation_executions_status_date_idx
  on public.operation_executions(status, created_at desc);

alter table public.operation_executions enable row level security;
alter table public.operation_executions force row level security;

drop policy if exists "cofundadoras_consultan_operation_executions" on public.operation_executions;
create policy "cofundadoras_consultan_operation_executions"
on public.operation_executions for select to authenticated
using (public.is_active_cofounder());

revoke all on public.operation_executions from anon;
revoke insert, update, delete, truncate, references, trigger on public.operation_executions from authenticated;
grant select on public.operation_executions to authenticated;

create or replace function public.assert_operation_key(p_operation_key text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text := trim(coalesce(p_operation_key,''));
begin
  if char_length(v_key) < 12 or char_length(v_key) > 200 then
    raise exception 'La clave de operación debe tener entre 12 y 200 caracteres';
  end if;
  if v_key !~ '^[A-Za-z0-9:_-]+$' then
    raise exception 'La clave de operación contiene caracteres no permitidos';
  end if;
  return v_key;
end;
$$;

create or replace function public.begin_idempotent_operation(
  p_operation_type text,
  p_operation_key text,
  p_request_fingerprint text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_type text := trim(coalesce(p_operation_type,''));
  v_key text := public.assert_operation_key(p_operation_key);
  v_existing public.operation_executions;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if char_length(v_type) < 3 or char_length(v_type) > 80 then raise exception 'Tipo de operación inválido'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_type || ':' || v_key, 0));

  select * into v_existing
  from public.operation_executions
  where operation_type=v_type and operation_key=v_key
  for update;

  if found then
    if v_existing.actor_id <> v_user_id then
      raise exception 'La clave de operación ya pertenece a otro usuario';
    end if;
    if coalesce(v_existing.request_fingerprint,'') <> coalesce(p_request_fingerprint,'') then
      raise exception 'La clave de operación ya fue utilizada con datos diferentes';
    end if;
    return jsonb_build_object(
      'execution_id',v_existing.id,
      'existing',true,
      'status',v_existing.status,
      'result',v_existing.result
    );
  end if;

  insert into public.operation_executions(operation_type,operation_key,actor_id,request_fingerprint)
  values(v_type,v_key,v_user_id,p_request_fingerprint)
  returning * into v_existing;

  return jsonb_build_object('execution_id',v_existing.id,'existing',false,'status','procesando');
end;
$$;

create or replace function public.complete_idempotent_operation(
  p_execution_id uuid,
  p_result jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.operation_executions
  set status='completada', result=coalesce(p_result,'{}'::jsonb), error_message=null, completed_at=now()
  where id=p_execution_id and actor_id=auth.uid();
  if not found then raise exception 'Ejecución idempotente no encontrada'; end if;
end;
$$;

-- Pedido nuevo idempotente.
create or replace function public.create_order_atomic_idempotent(
  p_operation_key text,
  p_customer_id uuid,
  p_delivery_address_id uuid default null,
  p_payment_method text default 'sin_definir',
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_delivery_cost numeric default 0,
  p_discount_reason text default null,
  p_customer_notes text default null,
  p_internal_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_begin jsonb;
  v_execution_id uuid;
  v_order public.orders;
  v_fingerprint text;
begin
  v_fingerprint := md5(jsonb_build_object(
    'customer_id',p_customer_id,'delivery_address_id',p_delivery_address_id,
    'payment_method',p_payment_method,'discount_type',p_discount_type,
    'discount_value',p_discount_value,'delivery_cost',p_delivery_cost,
    'discount_reason',p_discount_reason,'customer_notes',p_customer_notes,
    'internal_notes',p_internal_notes,'items',p_items
  )::text);
  v_begin := public.begin_idempotent_operation('crear_pedido',p_operation_key,v_fingerprint);
  v_execution_id := (v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    select * into v_order from public.orders where id=(v_begin->'result'->>'order_id')::uuid;
    return v_order;
  end if;
  v_order := public.create_order_atomic(p_customer_id,p_delivery_address_id,p_payment_method,p_discount_type,p_discount_value,p_delivery_cost,p_discount_reason,p_customer_notes,p_internal_notes,p_items);
  perform public.complete_idempotent_operation(v_execution_id,jsonb_build_object('order_id',v_order.id));
  return v_order;
end;
$$;

-- Venta rápida idempotente.
create or replace function public.create_quick_sale_atomic_idempotent(
  p_operation_key text,
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
  v_begin jsonb; v_execution_id uuid; v_result jsonb; v_fingerprint text; v_sale_id uuid;
begin
  v_fingerprint := md5(jsonb_build_object('customer_id',p_customer_id,'payment_method',p_payment_method,'payment_reference',p_payment_reference,'discount_type',p_discount_type,'discount_value',p_discount_value,'notes',p_notes,'items',p_items)::text);
  v_begin := public.begin_idempotent_operation('crear_venta_rapida',p_operation_key,v_fingerprint);
  v_execution_id := (v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    v_sale_id := (v_begin->'result'->>'sale_id')::uuid;
    return jsonb_build_object('sale',(select to_jsonb(s) from public.quick_sales s where s.id=v_sale_id),'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_sale_id),'idempotent',true);
  end if;
  v_result := public.create_quick_sale_atomic(p_customer_id,p_payment_method,p_payment_reference,p_discount_type,p_discount_value,p_notes,p_items);
  v_sale_id := (v_result->'sale'->>'id')::uuid;
  perform public.complete_idempotent_operation(v_execution_id,jsonb_build_object('sale_id',v_sale_id));
  return v_result || jsonb_build_object('idempotent',false);
end;
$$;

-- Anulación de venta rápida idempotente.
create or replace function public.cancel_quick_sale_atomic_idempotent(p_operation_key text,p_sale_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_begin jsonb; v_execution_id uuid; v_result jsonb; v_fingerprint text;
begin
  v_fingerprint:=md5(jsonb_build_object('sale_id',p_sale_id,'reason',p_reason)::text);
  v_begin:=public.begin_idempotent_operation('anular_venta_rapida',p_operation_key,v_fingerprint);
  v_execution_id:=(v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    return coalesce(v_begin->'result','{}'::jsonb)||jsonb_build_object('idempotent',true);
  end if;
  v_result:=public.cancel_quick_sale_atomic(p_sale_id,p_reason);
  perform public.complete_idempotent_operation(v_execution_id,v_result);
  return v_result||jsonb_build_object('idempotent',false);
end; $$;

-- Pago y entrega directa idempotente.
create or replace function public.close_order_direct_atomic_idempotent(
  p_operation_key text,p_order_id uuid,p_payment_method text,p_reason text,p_reference_number text default null,p_notes text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_begin jsonb; v_execution_id uuid; v_result jsonb; v_fingerprint text;
begin
  v_fingerprint:=md5(jsonb_build_object('order_id',p_order_id,'payment_method',p_payment_method,'reason',p_reason,'reference_number',p_reference_number,'notes',p_notes)::text);
  v_begin:=public.begin_idempotent_operation('cerrar_pedido_directo',p_operation_key,v_fingerprint);
  v_execution_id:=(v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    return coalesce(v_begin->'result','{}'::jsonb)||jsonb_build_object('idempotent',true);
  end if;
  v_result:=public.close_order_direct_atomic(p_order_id,p_payment_method,p_reason,p_reference_number,p_notes);
  perform public.complete_idempotent_operation(v_execution_id,v_result);
  return v_result||jsonb_build_object('idempotent',false);
end; $$;

revoke all on function public.assert_operation_key(text) from public, anon, authenticated;
revoke all on function public.begin_idempotent_operation(text,text,text) from public, anon, authenticated;
revoke all on function public.complete_idempotent_operation(uuid,jsonb) from public, anon, authenticated;

revoke all on function public.create_order_atomic_idempotent(text,uuid,uuid,text,text,numeric,numeric,text,text,text,jsonb) from public, anon;
grant execute on function public.create_order_atomic_idempotent(text,uuid,uuid,text,text,numeric,numeric,text,text,text,jsonb) to authenticated;
revoke all on function public.create_quick_sale_atomic_idempotent(text,uuid,text,text,text,numeric,text,jsonb) from public, anon;
grant execute on function public.create_quick_sale_atomic_idempotent(text,uuid,text,text,text,numeric,text,jsonb) to authenticated;
revoke all on function public.cancel_quick_sale_atomic_idempotent(text,uuid,text) from public, anon;
grant execute on function public.cancel_quick_sale_atomic_idempotent(text,uuid,text) to authenticated;
revoke all on function public.close_order_direct_atomic_idempotent(text,uuid,text,text,text,text) from public, anon;
grant execute on function public.close_order_direct_atomic_idempotent(text,uuid,text,text,text,text) to authenticated;

comment on table public.operation_executions is 'Registro central de claves idempotentes para impedir que un reintento repita efectos de negocio.';

commit;
