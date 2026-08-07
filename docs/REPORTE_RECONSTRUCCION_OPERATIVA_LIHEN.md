# Reporte de reconstrucción operativa LIHEN — 07/08/2026

## Resultado de la auditoría

Se auditó el proyecto `LIHEN_ADMIN_PRO` y el archivo `Inventario_Actual_LIHEN_2026-08-07.xlsx`.

### Hallazgo 1 — Reportes
La causa raíz del error visible en Reportes es una inconsistencia de nombre de columna: `quick_sale_items` fue creada con la FK canónica `sale_id`, pero `report-repository.js` y `report-service.js` consultaban/usaban `quick_sale_id`. Se corrigió todo el módulo para utilizar `sale_id`.

### Hallazgo 2 — cierre directo de pedidos
La función anterior `close_order_direct_atomic` marcaba un pedido como entregado y pagado, pero no ejecutaba la salida física del inventario reservado. Esto podía dejar pedidos entregados con unidades todavía reservadas. La migración 034 redefine el cierre para ejecutar `deliver_order_atomic` antes de completar el pago/entrega.

### Hallazgo 3 — punto de corte financiero
Los saldos actuales de Caja y cuentas deben mantenerse como línea base real. La reconstrucción no cambia `financial_accounts.current_balance`. Los movimientos asociados a las transacciones antiguas se conservan para auditoría, pero se marcan fuera de reportes operativos para evitar doble contabilización visual.

### Hallazgo 4 — reconstrucción sin borrar historial
No se eliminan Ventas rápidas ni Pedidos. Los registros existentes se archivan mediante `reconstruction_archived=true` después de restaurar su efecto de inventario. Así se conserva trazabilidad y el flujo operativo queda limpio para volver a registrar la historia correctamente.

## Auditoría del Excel

El Excel contiene 85 productos y 19 columnas. No se detectaron SKU duplicados. La relación `Stock disponible = Stock actual - Stock reservado` es consistente en las 85 filas.

Totales observados en el archivo:
- Stock actual: 79 unidades.
- Stock reservado: 8 unidades.
- Stock disponible: 71 unidades.

Se detectó un producto que requiere revisión manual porque tiene costo y precio en cero:
- `BC-013` — `Bloom fix fijador` — Costo real unitario: 0 — Precio sugerido LIHEN: 0.

La reconstrucción no cambia costos ni precios maestros.

## Archivos principales modificados

- `js/repositories/report-repository.js`
- `js/services/report-service.js`
- `js/repositories/quick-sale-repository.js`
- `js/repositories/order-repository.js`
- `js/sales.js`
- `js/order-workflow.js`
- `sql/034_reconstruccion_operativa_controlada.sql`
- `sql/035_restaurar_stock_transacciones_existentes.sql`
- `sql/036_respaldo_pre_reconstruccion.sql`
- `tests/reconstruction-operational-2026-08-07.test.js`

## Lógica final

### Venta rápida actual
Descuenta inventario y suma el dinero a la cuenta financiera seleccionada.

### Venta rápida histórica de reconstrucción
Descuenta inventario restaurado, usa precio maestro y no modifica Caja y cuentas.

### Pedido actual
Reserva inventario. Al registrar pago y entrega, consume la reserva y registra el ingreso financiero.

### Pedido histórico ya vendido
Se registra como entregado/pagado, consume inventario y no modifica Caja y cuentas.

### Compra histórica a proveedor
Permanece sin impacto en inventario ni caja, porque el stock de esas compras ya está incorporado en el punto de partida restaurado.

### Compra nueva a proveedor
La recepción aumenta inventario. El pago disminuye la cuenta financiera elegida.

## Seguridad de la restauración

La restauración se deriva de los registros reales de Ventas rápidas y de los movimientos de inventario de Pedidos. Las ventas anuladas no se restauran otra vez. En pedidos, se reponen salidas físicas y se liberan reservas pendientes según el efecto neto de `reserva_pedido`, `liberacion_reserva` y `salida_venta`.

La operación usa una clave única de reconstrucción. Repetir la misma clave devuelve el resultado anterior y no duplica stock.

## Limitación importante

No se dispone de conexión directa a la base Supabase de producción desde esta revisión. Por eso las pruebas realizadas son de código, módulos, lógica y migraciones locales. Antes de aplicar la restauración se debe ejecutar la previsualización del SQL 035 y comprobar las cantidades reales que Supabase devuelva.


## Corrección 07-08-2026 — ejecución desde Supabase SQL Editor

Se detectó que `apply_operational_reconstruction(...)` rechazaba el SQL Editor con `P0001: Acceso no autorizado` porque `auth.uid()` es nulo fuera de una sesión de la aplicación. La versión corregida de `034_reconstruccion_operativa_controlada.sql` admite exclusivamente una sesión administrativa `postgres` del SQL Editor y atribuye la auditoría a una cofundadora activa. Para bases donde el 034 anterior ya fue instalado, ejecutar `sql/037_hotfix_reconstruccion_sql_editor.sql` antes de repetir el PASO C del 035. El hotfix no modifica Caja ni inventario por sí mismo y no concede acceso a `anon`.
