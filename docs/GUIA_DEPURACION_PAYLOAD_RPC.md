# Depuración del guardado de pedidos

## Causa raíz encontrada
La migración 009 instaló la función, pero su bloque de auditoría intentaba escribir en `audit_logs.old_data`. El diagnóstico real de Supabase confirmó que esa columna no existe. En PostgreSQL, el error ocurre al ejecutar la RPC y revierte toda la transacción; por eso el producto desaparecía visualmente, pero reaparecía al abrir el pedido.

## Pasos
1. Ejecutar `sql/010_corregir_auditoria_y_rollback_edicion.sql` en Supabase.
2. Debe mostrar `Success. No rows returned`.
3. Subir el frontend actualizado a GitHub.
4. Abrir DevTools > Console al guardar. Buscar `[LIHEN] Guardar edición`.
5. También queda disponible `window.__LIHEN_LAST_ORDER_SAVE__` con el último payload, respuesta RPC y verificación.

## Prueba
Eliminar un producto, guardar, recargar completamente y volver a abrir. La línea debe permanecer eliminada.
