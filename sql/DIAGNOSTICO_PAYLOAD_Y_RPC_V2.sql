-- LIHEN ADMIN - DIAGNÓSTICO V2 (SOLO LECTURA)
-- Compatible con la tabla audit_logs real, sin referencia a old_data.

-- 1) Confirma las funciones instaladas y su definición real.
select
  p.oid,
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as result_type,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('update_order_atomic','update_order_atomic_v2')
order by p.proname,p.oid;

-- 2) Confirma las columnas reales de auditoría.
select column_name,data_type,is_nullable
from information_schema.columns
where table_schema='public' and table_name='audit_logs'
order by ordinal_position;

-- 3) Triggers que podrían alterar pedidos o líneas.
select
  event_object_table as table_name,
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
from information_schema.triggers
where trigger_schema='public'
  and event_object_table in ('orders','order_items','inventory','inventory_movements')
order by event_object_table,trigger_name,event_manipulation;

-- 4) Productos actuales del pedido de prueba.
with target as (
  select id,order_number from public.orders where order_number='LH-2026-00001' limit 1
)
select t.order_number,oi.id,oi.product_id,oi.variant_id,oi.product_name_snapshot,
       oi.quantity,oi.unit_price,oi.line_total,oi.quantity_reserved,oi.created_at
from target t
join public.order_items oi on oi.order_id=t.id
order by oi.created_at,oi.id;

-- 5) Duplicados reales del pedido.
with target as (
  select id from public.orders where order_number='LH-2026-00001' limit 1
)
select oi.product_id,oi.variant_id,count(*) as rows_count,sum(oi.quantity) as total_quantity
from public.order_items oi
join target t on t.id=oi.order_id
group by oi.product_id,oi.variant_id
having count(*)>1;

-- 6) Últimas auditorías (solo columnas que sí existen en este proyecto).
with target as (
  select id from public.orders where order_number='LH-2026-00001' limit 1
)
select al.id,al.user_id,al.action,al.entity_type,al.entity_id,al.new_data,al.details,al.created_at
from public.audit_logs al
join target t on al.entity_id=t.id::text
order by al.created_at desc
limit 20;
