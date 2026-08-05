-- LIHEN ADMIN - DIAGNÓSTICO DE EDICIÓN DE PEDIDOS
-- Este archivo NO modifica datos.
-- Cambia únicamente el número de pedido en la sección PARAMETROS si necesitas revisar otro.

-- ============================================================
-- PARÁMETROS
-- ============================================================
create temporary table if not exists _lihen_diagnostico_parametros (
  order_number text primary key
) on commit preserve rows;

truncate table _lihen_diagnostico_parametros;

insert into _lihen_diagnostico_parametros(order_number)
values ('LH-2026-00001');

-- ============================================================
-- 1. FUNCIONES update_order_atomic Y update_order_atomic_v2
-- ============================================================
select
  n.nspname as schema_name,
  p.oid,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_function_arguments(p.oid) as full_arguments,
  pg_get_function_result(p.oid) as result_type,
  p.prosecdef as security_definer,
  p.proconfig as function_config,
  pg_get_userbyid(p.proowner) as owner
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('update_order_atomic', 'update_order_atomic_v2')
order by p.proname, p.oid;

-- ============================================================
-- 2. DEFINICIÓN EXACTA DE LAS FUNCIONES
-- ============================================================
select
  p.oid,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('update_order_atomic', 'update_order_atomic_v2')
order by p.proname, p.oid;

-- ============================================================
-- 3. TRIGGERS SOBRE orders Y order_items
-- ============================================================
select
  event_object_schema,
  event_object_table,
  trigger_name,
  action_timing,
  event_manipulation,
  action_statement
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table in ('orders', 'order_items')
order by event_object_table, trigger_name, event_manipulation;

select
  c.relname as table_name,
  t.tgname as trigger_name,
  t.tgenabled,
  pg_get_triggerdef(t.oid, true) as trigger_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('orders', 'order_items')
  and not t.tgisinternal
order by c.relname, t.tgname;

-- ============================================================
-- 4. RLS Y POLÍTICAS
-- ============================================================
select
  n.nspname as schemaname,
  c.relname as tablename,
  c.relrowsecurity as rowsecurity,
  c.relforcerowsecurity as force_rowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('orders', 'order_items', 'inventory', 'inventory_movements', 'audit_logs')
order by c.relname;

select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('orders', 'order_items', 'inventory', 'inventory_movements', 'audit_logs')
order by tablename, policyname;

-- ============================================================
-- 5. PRIVILEGIOS DE LAS RPC
-- ============================================================
select
  routine_schema,
  routine_name,
  grantee,
  privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in ('update_order_atomic', 'update_order_atomic_v2')
order by routine_name, grantee, privilege_type;

-- ============================================================
-- 6. PEDIDO ENCONTRADO POR NÚMERO
-- ============================================================
select
  o.id,
  o.order_number,
  o.customer_id,
  o.status,
  o.payment_method,
  o.payment_status,
  o.subtotal,
  o.discount_type,
  o.discount_value,
  o.discount_amount,
  o.delivery_cost,
  o.total,
  o.updated_at
from public.orders o
join _lihen_diagnostico_parametros p
  on p.order_number = o.order_number;

-- ============================================================
-- 7. LÍNEAS REALES GUARDADAS EN order_items
-- ============================================================
select
  oi.id,
  oi.order_id,
  oi.product_id,
  oi.variant_id,
  oi.product_name_snapshot,
  oi.variant_snapshot,
  oi.quantity,
  oi.unit_price,
  oi.line_total,
  oi.quantity_from_stock,
  oi.quantity_to_source,
  oi.quantity_reserved,
  oi.created_at
from public.order_items oi
join public.orders o on o.id = oi.order_id
join _lihen_diagnostico_parametros p on p.order_number = o.order_number
order by oi.created_at, oi.id;

-- ============================================================
-- 8. CONTEO Y TOTALES CALCULADOS DESDE LAS LÍNEAS
-- ============================================================
select
  o.order_number,
  count(oi.id) as lineas_guardadas,
  coalesce(sum(oi.quantity), 0) as unidades_guardadas,
  coalesce(sum(oi.line_total), 0) as subtotal_desde_lineas,
  o.subtotal as subtotal_encabezado,
  o.discount_amount,
  o.delivery_cost,
  o.total as total_encabezado
from public.orders o
join _lihen_diagnostico_parametros p on p.order_number = o.order_number
left join public.order_items oi on oi.order_id = o.id
group by
  o.id,
  o.order_number,
  o.subtotal,
  o.discount_amount,
  o.delivery_cost,
  o.total;

-- ============================================================
-- 9. MOVIMIENTOS DE INVENTARIO DEL PEDIDO
-- ============================================================
select
  im.id,
  im.inventory_id,
  im.movement_type,
  im.quantity,
  im.physical_before,
  im.physical_after,
  im.reserved_before,
  im.reserved_after,
  im.reason,
  im.performed_by,
  im.created_at
from public.inventory_movements im
join public.orders o on o.id = im.order_id
join _lihen_diagnostico_parametros p on p.order_number = o.order_number
order by im.created_at desc
limit 50;

-- ============================================================
-- 10. AUDITORÍA DEL PEDIDO
-- ============================================================
select
  al.id,
  al.user_id,
  al.action,
  al.entity_type,
  al.entity_id,
  al.old_data,
  al.new_data,
  al.details,
  al.created_at
from public.audit_logs al
join public.orders o on o.id::text = al.entity_id
join _lihen_diagnostico_parametros p on p.order_number = o.order_number
where al.entity_type = 'orders'
order by al.created_at desc
limit 30;

-- ============================================================
-- 11. DUPLICADOS POR PRODUCTO Y VARIANTE
-- ============================================================
select
  oi.product_id,
  oi.variant_id,
  count(*) as rows_count,
  sum(oi.quantity) as total_quantity
from public.order_items oi
join public.orders o on o.id = oi.order_id
join _lihen_diagnostico_parametros p on p.order_number = o.order_number
group by oi.product_id, oi.variant_id
having count(*) > 1;

-- ============================================================
-- 12. RESERVAS ACTUALES DE LOS PRODUCTOS DEL PEDIDO
-- ============================================================
select
  oi.product_name_snapshot,
  oi.product_id,
  oi.variant_id,
  oi.quantity,
  oi.quantity_reserved as reserva_en_linea,
  i.physical_stock,
  i.reserved_stock as reserva_total_inventario,
  greatest(0, i.physical_stock - i.reserved_stock) as disponible_actual
from public.order_items oi
join public.orders o on o.id = oi.order_id
join _lihen_diagnostico_parametros p on p.order_number = o.order_number
left join public.inventory i
  on i.product_id = oi.product_id
 and i.variant_id is not distinct from oi.variant_id
order by oi.product_name_snapshot;
