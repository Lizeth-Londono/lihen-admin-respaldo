# Fase 18 — Importación segura y transaccional

La importación de inventario dejó de ejecutar escrituras producto por producto desde el navegador. La interfaz envía un único lote validado a la RPC `import_inventory_batch_atomic`.

## Garantías

- Una sola transacción PostgreSQL para productos, inventario, relaciones con proveedores, movimientos, lote y auditoría.
- Si una fila falla, se revierte el lote completo.
- Clave de operación única para impedir dobles importaciones por doble clic o reintento de red.
- Registro del lote en `import_batches` y detalle aplicado en `import_batch_rows`.
- Cada cambio de stock genera un movimiento `ajuste_positivo` o `ajuste_negativo`.
- No se permite reducir el stock por debajo de las unidades reservadas.
- Los productos ausentes del archivo no se eliminan.
- Las filas sin cambios se contabilizan, pero no se vuelven a escribir.

## Instalación

Ejecutar `sql/022_importacion_inventario_transaccional_fase_18.sql` en Supabase SQL Editor después de las migraciones 006 y 007.
