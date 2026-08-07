-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 034
-- Reconstrucción operativa controlada + históricos + corrección
-- de entrega de pedidos + exclusión de reportes de línea base.
--
-- IMPORTANTE: esta migración INSTALA la infraestructura. No ejecuta
-- la restauración de stock. La restauración se ejecuta con 035.
-- ============================================================

begin;

-- 1) Metadatos para conservar historial sin borrarlo.
alter table public.quick_sales
  add column if not exists is_historical boolean not null default false,
  add column if not exists inventory_impact boolean not null default true,
  add column if not exists financial_impact boolean not null default true,
  add column if not exists historical_occurred_at timestamptz,
  add column if not exists historical_source_reference text,
  add column if not exists reconstruction_archived boolean not null default false,
  add column if not exists reconstruction_run_id uuid;

alter table public.orders
  add column if not exists is_historical boolean not null default false,
  add column if not exists inventory_impact boolean not null default true,
  add column if not exists financial_impact boolean not null default true,
  add column if not exists historical_occurred_at timestamptz,
  add column if not exists historical_source_reference text,
  add column if not exists reconstruction_archived boolean not null default false,
  add column if not exists reconstruction_run_id uuid;

alter table public.financial_movements
  add column if not exists reporting_excluded boolean not null default false,
  add column if not exists reporting_exclusion_reason text;

create table if not exists public.operational_reconstruction_runs (
  id uuid primary key default gen_random_uuid(),
  operation_key text not null unique,
  status text not null default 'preparada' check (status in ('preparada','aplicada','fallida')),
  description text,
  preview_snapshot jsonb not null default '[]'::jsonb,
  quick_sales_archived integer not null default 0,
  orders_archived integer not null default 0,
  physical_units_restored integer not null default 0,
  reserved_units_released integer not null default 0,
  financial_accounts_changed boolean not null default false,
  created_by uuid not null references public.profiles(id),
  applied_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  applied_at timestamptz
);

alter table public.operational_reconstruction_runs enable row level security;
drop policy if exists "cofundadoras_consultan_reconstrucciones" on public.operational_reconstruction_runs;
create policy "cofundadoras_consultan_reconstrucciones"
on public.operational_reconstruction_runs for select to authenticated
using (public.is_active_cofounder());
grant select on public.operational_reconstruction_runs to authenticated;

create index if not exists quick_sales_reconstruction_archived_idx
  on public.quick_sales(reconstruction_archived, created_at desc);
create index if not exists orders_reconstruction_archived_idx
  on public.orders(reconstruction_archived, created_at desc);
create index if not exists financial_movements_reporting_excluded_idx
  on public.financial_movements(reporting_excluded, occurred_at desc);

-- FK diferidas hasta que exista la tabla de reconstrucción.
do $$
begin
  if not exists(select 1 from pg_constraint where conname='quick_sales_reconstruction_run_fk') then
    alter table public.quick_sales add constraint quick_sales_reconstruction_run_fk
      foreign key(reconstruction_run_id) references public.operational_reconstruction_runs(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='orders_reconstruction_run_fk') then
    alter table public.orders add constraint orders_reconstruction_run_fk
      foreign key(reconstruction_run_id) references public.operational_reconstruction_runs(id) on delete restrict;
  end if;
end $$;

-- 2) Vista previa: calcula exactamente qué se restaurará sin modificar datos.
create or replace function public.preview_operational_reconstruction()
returns table(
  inventory_id uuid,
  product_id uuid,
  sku text,
  product_name text,
  physical_stock integer,
  reserved_stock integer,
  quick_sale_units_to_restore bigint,
  order_physical_units_to_restore bigint,
  order_reserved_units_to_release bigint,
  resulting_physical_stock bigint,
  resulting_reserved_stock bigint
)
language sql
security definer
set search_path=''
as $$
with quick_restore as (
  select i.id inventory_id, sum(qsi.quantity)::bigint qty
  from public.quick_sales qs
  join public.quick_sale_items qsi on qsi.sale_id=qs.id
  join public.inventory i on i.product_id=qsi.product_id
    and ((i.variant_id is null and qsi.variant_id is null) or i.variant_id=qsi.variant_id)
  where qs.status='completada' and coalesce(qs.reconstruction_archived,false)=false
  group by i.id
), order_effects as (
  select im.inventory_id,
    coalesce(sum(case when im.movement_type='salida_venta' then im.quantity else 0 end),0)::bigint physical_restore,
    greatest(0,
      coalesce(sum(case when im.movement_type='reserva_pedido' then im.quantity else 0 end),0)
      - coalesce(sum(case when im.movement_type='liberacion_reserva' then im.quantity else 0 end),0)
      - coalesce(sum(case when im.movement_type='salida_venta' then im.quantity else 0 end),0)
    )::bigint reservation_release
  from public.inventory_movements im
  join public.orders o on o.id=im.order_id
  where im.order_id is not null
    and coalesce(o.reconstruction_archived,false)=false
    and o.status <> 'cancelado'::public.order_status
  group by im.inventory_id
), affected as (
  select inventory_id from quick_restore
  union
  select inventory_id from order_effects
)
select
  i.id,
  i.product_id,
  p.sku,
  p.name,
  i.physical_stock,
  i.reserved_stock,
  coalesce(q.qty,0),
  coalesce(oe.physical_restore,0),
  least(i.reserved_stock::bigint,coalesce(oe.reservation_release,0)),
  i.physical_stock::bigint + coalesce(q.qty,0) + coalesce(oe.physical_restore,0),
  greatest(0,i.reserved_stock::bigint - least(i.reserved_stock::bigint,coalesce(oe.reservation_release,0)))
from affected a
join public.inventory i on i.id=a.inventory_id
join public.products p on p.id=i.product_id
left join quick_restore q on q.inventory_id=i.id
left join order_effects oe on oe.inventory_id=i.id
order by p.name, p.sku;
$$;

revoke all on function public.preview_operational_reconstruction() from public,anon;
grant execute on function public.preview_operational_reconstruction() to authenticated;

-- 3) Aplicación idempotente de la restauración.
create or replace function public.apply_operational_reconstruction(
  p_operation_key text,
  p_description text default 'Restauración de ventas y pedidos previos al corte operativo'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_sql_editor_admin boolean := (auth.uid() is null and session_user = 'postgres');
  v_run public.operational_reconstruction_runs;
  v_row record;
  v_inventory public.inventory;
  v_qs_count integer := 0;
  v_order_count integer := 0;
  v_physical bigint := 0;
  v_reserved bigint := 0;
  v_preview jsonb;
begin
  -- Desde la aplicación se exige una cofundadora activa. Desde Supabase SQL
  -- Editor se permite exclusivamente la sesión postgres y se atribuye la
  -- operación a la primera cofundadora activa para conservar las FK/auditoría.
  if v_sql_editor_admin then
    select id into v_user
    from public.profiles
    where active=true and role='cofundadora'
    order by created_at
    limit 1;

    if v_user is null then
      raise exception 'No existe una cofundadora activa para atribuir la reconstrucción';
    end if;
  elsif not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if coalesce(length(trim(p_operation_key)),0) < 12 then raise exception 'Clave de operación inválida'; end if;

  select * into v_run from public.operational_reconstruction_runs where operation_key=p_operation_key for update;
  if found then
    if v_run.status='aplicada' then
      return jsonb_build_object('run',to_jsonb(v_run),'idempotent',true);
    end if;
    raise exception 'Existe una reconstrucción con esta clave en estado %',v_run.status;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    into v_preview
  from public.preview_operational_reconstruction() x;

  insert into public.operational_reconstruction_runs(operation_key,status,description,preview_snapshot,created_by)
  values(p_operation_key,'preparada',p_description,v_preview,v_user)
  returning * into v_run;

  -- Restaurar unidades físicas de ventas rápidas completadas.
  for v_row in
    select i.id inventory_id, sum(qsi.quantity)::integer qty,
           string_agg(distinct qs.sale_number, ', ' order by qs.sale_number) refs
    from public.quick_sales qs
    join public.quick_sale_items qsi on qsi.sale_id=qs.id
    join public.inventory i on i.product_id=qsi.product_id
      and ((i.variant_id is null and qsi.variant_id is null) or i.variant_id=qsi.variant_id)
    where qs.status='completada' and coalesce(qs.reconstruction_archived,false)=false
    group by i.id
  loop
    select * into v_inventory from public.inventory where id=v_row.inventory_id for update;
    insert into public.inventory_movements(
      inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
    ) values(
      v_inventory.id,'ajuste_positivo',v_row.qty,v_inventory.physical_stock,v_inventory.physical_stock+v_row.qty,
      v_inventory.reserved_stock,v_inventory.reserved_stock,
      'Reconstrucción operativa '||v_run.id::text||' · devolución de ventas rápidas: '||left(v_row.refs,400),v_user
    );
    update public.inventory set physical_stock=physical_stock+v_row.qty,updated_by=v_user where id=v_inventory.id;
    v_physical := v_physical + v_row.qty;
  end loop;

  -- Restaurar efecto neto de pedidos: ventas entregadas vuelven a físico y
  -- reservas aún abiertas se liberan. Se deriva de inventory_movements para
  -- soportar ediciones, recepciones y cierres directos antiguos.
  for v_row in
    select im.inventory_id,
      coalesce(sum(case when im.movement_type='salida_venta' then im.quantity else 0 end),0)::integer physical_restore,
      greatest(0,
        coalesce(sum(case when im.movement_type='reserva_pedido' then im.quantity else 0 end),0)
        - coalesce(sum(case when im.movement_type='liberacion_reserva' then im.quantity else 0 end),0)
        - coalesce(sum(case when im.movement_type='salida_venta' then im.quantity else 0 end),0)
      )::integer reservation_release,
      string_agg(distinct o.order_number, ', ' order by o.order_number) refs
    from public.inventory_movements im
    join public.orders o on o.id=im.order_id
    where im.order_id is not null
      and coalesce(o.reconstruction_archived,false)=false
      and o.status <> 'cancelado'::public.order_status
    group by im.inventory_id
  loop
    select * into v_inventory from public.inventory where id=v_row.inventory_id for update;

    if v_row.physical_restore > 0 then
      insert into public.inventory_movements(
        inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
      ) values(
        v_inventory.id,'ajuste_positivo',v_row.physical_restore,
        v_inventory.physical_stock,v_inventory.physical_stock+v_row.physical_restore,
        v_inventory.reserved_stock,v_inventory.reserved_stock,
        'Reconstrucción operativa '||v_run.id::text||' · devolución de pedidos: '||left(v_row.refs,400),v_user
      );
      update public.inventory set physical_stock=physical_stock+v_row.physical_restore,updated_by=v_user where id=v_inventory.id;
      v_physical := v_physical + v_row.physical_restore;
      select * into v_inventory from public.inventory where id=v_row.inventory_id for update;
    end if;

    if v_row.reservation_release > 0 then
      if v_inventory.reserved_stock < v_row.reservation_release then
        raise exception 'Inconsistencia: reserva actual % menor que reserva a liberar % en inventario %',v_inventory.reserved_stock,v_row.reservation_release,v_inventory.id;
      end if;
      insert into public.inventory_movements(
        inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
      ) values(
        v_inventory.id,'liberacion_reserva',v_row.reservation_release,
        v_inventory.physical_stock,v_inventory.physical_stock,
        v_inventory.reserved_stock,v_inventory.reserved_stock-v_row.reservation_release,
        'Reconstrucción operativa '||v_run.id::text||' · liberación de reservas de pedidos: '||left(v_row.refs,400),v_user
      );
      update public.inventory set reserved_stock=reserved_stock-v_row.reservation_release,updated_by=v_user where id=v_inventory.id;
      v_reserved := v_reserved + v_row.reservation_release;
    end if;
  end loop;

  select count(*) into v_qs_count from public.quick_sales where coalesce(reconstruction_archived,false)=false;
  select count(*) into v_order_count from public.orders where coalesce(reconstruction_archived,false)=false;

  -- Conservar registros antiguos, pero archivarlos del flujo operativo.
  update public.quick_sales
     set reconstruction_archived=true,reconstruction_run_id=v_run.id
   where coalesce(reconstruction_archived,false)=false;

  update public.orders
     set reconstruction_archived=true,reconstruction_run_id=v_run.id
   where coalesce(reconstruction_archived,false)=false;

  -- NO tocar saldos. Solo excluir de reportes los movimientos financieros
  -- asociados a registros archivados para evitar doble contabilización visual.
  update public.financial_movements fm
     set reporting_excluded=true,
         reporting_exclusion_reason='Incluido en saldo de corte; transacción archivada por reconstrucción '||v_run.id::text
   where coalesce(fm.reporting_excluded,false)=false
     and (
       (fm.source_type='quick_sale' and exists(select 1 from public.quick_sales qs where qs.id=fm.source_id and qs.reconstruction_run_id=v_run.id))
       or
       (fm.source_type='order' and exists(select 1 from public.orders o where o.id=fm.source_id and o.reconstruction_run_id=v_run.id))
     );

  update public.operational_reconstruction_runs
     set status='aplicada',quick_sales_archived=v_qs_count,orders_archived=v_order_count,
         physical_units_restored=v_physical,reserved_units_released=v_reserved,
         financial_accounts_changed=false,applied_by=v_user,applied_at=now()
   where id=v_run.id
   returning * into v_run;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(v_user,'reconstruccion_operativa','operational_reconstruction_runs',v_run.id::text,to_jsonb(v_run),
    jsonb_build_object('financial_accounts_changed',false,'preview',v_preview));

  return jsonb_build_object('run',to_jsonb(v_run),'idempotent',false);
exception when others then
  -- La transacción completa hace rollback, por lo cual nunca quedan saldos o
  -- inventarios a medias.
  raise;
end;
$$;

revoke all on function public.apply_operational_reconstruction(text,text) from public,anon;
grant execute on function public.apply_operational_reconstruction(text,text) to authenticated;

-- 4) Venta histórica de reconstrucción: AFECTA INVENTARIO, NO AFECTA CAJA.
create or replace function public.create_historical_quick_sale_inventory_atomic_idempotent(
  p_operation_key text,
  p_customer_id uuid default null,
  p_payment_method text default 'efectivo',
  p_occurred_at timestamptz default now(),
  p_payment_reference text default null,
  p_notes text default null,
  p_source_reference text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
  v_sale_id uuid;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_occurred_at > now() + interval '5 minutes' then raise exception 'La fecha histórica no puede estar en el futuro'; end if;

  -- Precio histórico se guarda por línea; no se altera products.sale_price.
  v_result := public.create_quick_sale_atomic_idempotent(
    p_operation_key,p_customer_id,p_payment_method,p_payment_reference,
    'ninguno',0,concat_ws(E'\n',p_notes,'[Histórica de reconstrucción: afecta inventario, no caja]'),p_items
  );
  v_sale_id := (v_result->'sale'->>'id')::uuid;

  update public.quick_sales
     set is_historical=true,inventory_impact=true,financial_impact=false,
         historical_occurred_at=p_occurred_at,historical_source_reference=nullif(trim(p_source_reference),''),
         created_at=p_occurred_at,updated_at=now()
   where id=v_sale_id;

  return jsonb_build_object(
    'sale',(select to_jsonb(s) from public.quick_sales s where s.id=v_sale_id),
    'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_sale_id),
    'idempotent',coalesce((v_result->>'idempotent')::boolean,false)
  );
end;
$$;

revoke all on function public.create_historical_quick_sale_inventory_atomic_idempotent(text,uuid,text,timestamptz,text,text,text,jsonb) from public,anon;
grant execute on function public.create_historical_quick_sale_inventory_atomic_idempotent(text,uuid,text,timestamptz,text,text,text,jsonb) to authenticated;

-- 5) Pedido histórico vendido: crea pedido, consume inventario y registra pago
-- informativo, pero NO genera movimiento financiero.
create or replace function public.create_historical_order_inventory_atomic_idempotent(
  p_operation_key text,
  p_customer_id uuid,
  p_payment_method text,
  p_occurred_at timestamptz,
  p_delivery_cost numeric default 0,
  p_notes text default null,
  p_source_reference text default null,
  p_items jsonb default '[]'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order public.orders;
  v_close jsonb;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_occurred_at > now() + interval '5 minutes' then raise exception 'La fecha histórica no puede estar en el futuro'; end if;

  v_order := public.create_order_atomic_idempotent(
    p_operation_key||':pedido',p_customer_id,null,p_payment_method,'ninguno',0,p_delivery_cost,
    null,null,concat_ws(E'\n',p_notes,'[Histórico de reconstrucción: afecta inventario, no caja]'),p_items
  );

  if exists(select 1 from public.order_items where order_id=v_order.id and quantity_reserved < quantity) then
    raise exception 'No hay stock suficiente para reconstruir este pedido histórico. Registra/valida primero las compras históricas correspondientes.';
  end if;

  v_close := public.close_order_direct_atomic_idempotent(
    p_operation_key||':cierre',v_order.id,p_payment_method,
    'Registro histórico de reconstrucción operativa',null,'Sin impacto financiero actual'
  );

  update public.orders
     set is_historical=true,inventory_impact=true,financial_impact=false,
         historical_occurred_at=p_occurred_at,historical_source_reference=nullif(trim(p_source_reference),''),
         created_at=p_occurred_at,confirmed_at=p_occurred_at,delivered_at=p_occurred_at,updated_at=now()
   where id=v_order.id
   returning * into v_order;

  update public.payments
     set payment_date=p_occurred_at
   where order_id=v_order.id and financial_movement_id is null;

  return v_order;
end;
$$;

revoke all on function public.create_historical_order_inventory_atomic_idempotent(text,uuid,text,timestamptz,numeric,text,text,jsonb) from public,anon;
grant execute on function public.create_historical_order_inventory_atomic_idempotent(text,uuid,text,timestamptz,numeric,text,text,jsonb) to authenticated;

-- 6) Corrección de cierre directo: entregar debe consumir inventario reservado.
-- La versión anterior cambiaba el estado a entregado sin ejecutar salida_venta.
create or replace function public.close_order_direct_atomic(
  p_order_id uuid,
  p_payment_method text,
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
  v_user_id uuid := auth.uid();
  v_order public.orders;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_note text;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if v_reason is null or char_length(v_reason)<10 then raise exception 'Debes registrar un motivo claro de al menos 10 caracteres'; end if;
  if p_payment_method is null or p_payment_method='sin_definir' then raise exception 'Selecciona el método de pago'; end if;

  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if v_order.status='cancelado' then raise exception 'No se puede cerrar como entregado un pedido cancelado'; end if;

  -- Si aún no está entregado, consumir primero la reserva de inventario.
  if v_order.status <> 'entregado' then
    v_order := public.deliver_order_atomic(p_order_id);
  end if;

  v_note := concat_ws(E'\n',nullif(trim(coalesce(v_order.internal_notes,'')),''),'[Cierre directo] '||v_reason,nullif(trim(coalesce(p_notes,'')),''));

  update public.orders
     set payment_method=p_payment_method::public.payment_method,
         payment_status='pagado'::public.payment_status,
         status='entregado'::public.order_status,
         confirmed_at=coalesce(confirmed_at,now()),delivered_at=coalesce(delivered_at,now()),
         summary_skipped=true,confirmation_skipped=true,
         workflow_override_reason=v_reason,workflow_override_at=now(),workflow_override_by=v_user_id,
         internal_notes=v_note,updated_by=v_user_id
   where id=p_order_id returning * into v_order;

  if not exists(select 1 from public.payments p where p.order_id=p_order_id and p.status='pagado'::public.payment_status and p.amount=v_order.total) then
    insert into public.payments(order_id,method,status,amount,reference_number,payment_date,notes,registered_by)
    values(p_order_id,p_payment_method::public.payment_method,'pagado'::public.payment_status,v_order.total,
      nullif(trim(coalesce(p_reference_number,'')),''),now(),'Pago registrado mediante cierre directo. Motivo: '||v_reason,v_user_id);
  end if;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(v_user_id,'cerrar_pedido_sin_confirmacion','orders',p_order_id::text,to_jsonb(v_order),
    jsonb_build_object('reason',v_reason,'inventory_consumed',true,'payment_method',p_payment_method));

  return jsonb_build_object('order',to_jsonb(v_order),'inventory_consumed',true,'reason',v_reason);
end;
$$;

revoke all on function public.close_order_direct_atomic(uuid,text,text,text,text) from public,anon;
grant execute on function public.close_order_direct_atomic(uuid,text,text,text,text) to authenticated;

commit;
