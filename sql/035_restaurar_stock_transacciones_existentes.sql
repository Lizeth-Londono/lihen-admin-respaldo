-- ============================================================
-- LIHEN ADMIN — 035
-- EJECUCIÓN CONTROLADA DE RECONSTRUCCIÓN
-- Requiere haber ejecutado primero 034_reconstruccion_operativa_controlada.sql
-- Si 034 ya se había instalado antes de la corrección del 07-08-2026 y el
-- PASO C devuelve 'Acceso no autorizado' desde SQL Editor, ejecutar primero:
--   037_hotfix_reconstruccion_sql_editor.sql
-- y luego volver a este PASO C.
-- ============================================================

-- PASO A — PREVISUALIZAR. NO MODIFICA DATOS.
select * from public.preview_operational_reconstruction();

-- PASO B — controles adicionales. NO MODIFICAN DATOS.
select
  (select count(*) from public.quick_sales where coalesce(reconstruction_archived,false)=false) as ventas_rapidas_a_archivar,
  (select count(*) from public.orders where coalesce(reconstruction_archived,false)=false) as pedidos_a_archivar,
  (select coalesce(sum(current_balance),0) from public.financial_accounts where active=true) as dinero_actual_antes,
  (select coalesce(sum(physical_stock),0) from public.inventory) as unidades_fisicas_antes,
  (select coalesce(sum(reserved_stock),0) from public.inventory) as unidades_reservadas_antes;

-- PASO C — EJECUTAR SOLO DESPUÉS DE REVISAR LOS PASOS A Y B.
-- Ejecutar desde Supabase SQL Editor con Role = postgres, o desde la app con
-- una sesión autenticada de cofundadora activa. El hotfix 037 mantiene esta
-- restricción y no habilita el RPC para anon.
-- Cambia la clave si fuera necesario, pero NO reutilices otra clave para una
-- segunda reconstrucción. La función es idempotente con la misma clave.
--
-- select public.apply_operational_reconstruction(
--   'LIHEN-RECONSTRUCCION-2026-08-07-V1',
--   'Corte operativo LIHEN 07-08-2026: conservar Caja y devolver impacto de ventas/pedidos al inventario'
-- );

-- PASO D — VERIFICACIÓN DESPUÉS DE EJECUTAR C.
select * from public.operational_reconstruction_runs order by created_at desc limit 5;
select
  (select coalesce(sum(current_balance),0) from public.financial_accounts where active=true) as dinero_actual_despues,
  (select coalesce(sum(physical_stock),0) from public.inventory) as unidades_fisicas_despues,
  (select coalesce(sum(reserved_stock),0) from public.inventory) as unidades_reservadas_despues;

-- Debe cumplirse: Caja y cuentas NO cambia por la reconstrucción.
-- Los registros previos quedan archivados, no eliminados.
select count(*) as ventas_archivadas from public.quick_sales where reconstruction_archived=true;
select count(*) as pedidos_archivados from public.orders where reconstruction_archived=true;
