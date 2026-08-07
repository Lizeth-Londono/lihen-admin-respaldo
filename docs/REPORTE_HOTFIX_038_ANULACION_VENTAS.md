# Reporte técnico — Hotfix 038 anulación de ventas

Fecha: 2026-08-07

## Diagnóstico de causa raíz

El frontend no era la causa del bloqueo. `js/sales.js` abre el modal, valida el motivo y llama correctamente al repositorio. `js/repositories/quick-sale-repository.js` invoca la RPC `cancel_quick_sale_financial_atomic_idempotent`.

La causa estaba en la versión de esa RPC definida por `sql/028_integracion_ventas_pedidos_caja_fase_24.sql` y también incluida en la migración consolidada. La función exigía que `quick_sales.financial_account_id` y `quick_sales.financial_movement_id` estuvieran presentes antes de ejecutar la anulación. Si cualquiera era `NULL`, levantaba inmediatamente la excepción `La venta no tiene un movimiento financiero asociado`.

Esto es incompatible con ventas históricas creadas antes de la capa financiera, y también con ventas cuyo movimiento existe pero cuyo enlace en `quick_sales` quedó incompleto.

## Riesgo adicional encontrado

La función financiera anterior tampoco verificaba `status='anulada'` antes de preparar una reversión. La RPC operativa base sí evita una segunda reposición de stock, pero un intento posterior con una clave de operación distinta podía entrar en una ruta financiera peligrosa. El hotfix agrega una barrera temprana para que una venta ya anulada no vuelva a tocar ni inventario ni caja.

## Solución aplicada

Se agregó `sql/038_hotfix_anulacion_ventas_legacy.sql` como capa final y segura.

Comportamientos:

- Venta ya anulada: retorna sin cambios.
- Movimiento financiero correctamente enlazado: se revierte una vez.
- Movimiento financiero existente pero vínculo roto: se localiza por `source_type/source_id`, se repara el enlace y se revierte.
- Venta antigua sin movimiento financiero real: se ejecuta la anulación operativa e inventario, pero no se crea un movimiento financiero ficticio.
- Movimiento original ya reversado: se completa únicamente la parte operativa, sin un segundo egreso.
- Saldo insuficiente para una reversión real: se conserva el bloqueo para evitar una operación contable parcial/incoherente.

## Atomicidad

La RPC financiera llama a la RPC operativa desde la misma ejecución PostgreSQL. Si una etapa lanza una excepción, la transacción completa de esa llamada se revierte. No se deja intencionalmente una venta anulada con reversión financiera incompleta.

## Eliminación de ventas

No se recomienda borrar las ventas. `quick_sale_items` depende de `quick_sales`, los movimientos de inventario y los movimientos financieros usan referencias a la venta, y los reportes dependen del historial. La estrategia adoptada conserva `status='anulada'`, fecha, usuario y motivo.

## Archivos agregados/modificados

- `sql/038_hotfix_anulacion_ventas_legacy.sql` — nueva RPC corregida y consultas de diagnóstico.
- `docs/GUIA_HOTFIX_038_ANULACION_VENTAS.md` — instalación y comportamiento esperado.
- `docs/REPORTE_HOTFIX_038_ANULACION_VENTAS.md` — este informe.
- `tests/cancel-quick-sale-legacy-2026-08-07.test.js` — pruebas estáticas de regresión.
- `sql/README.md` — instrucción para ejecutar el hotfix 038.
- `RELEASE_MANIFEST_SHA256.txt` — regenerado al final del paquete.

## Validación local

Se ejecutaron:

- `npm test`: 99 pruebas aprobadas, 0 fallos.
- `npm run check`: validación de módulos JavaScript.

La prueba definitiva contra datos reales requiere ejecutar el SQL 038 en el proyecto Supabase de LIHEN y probar una venta afectada, porque el ZIP no contiene acceso autenticado a la base de producción.
