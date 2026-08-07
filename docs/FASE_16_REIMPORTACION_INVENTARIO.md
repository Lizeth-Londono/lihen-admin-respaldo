# Fase 16 — Reimportación segura del inventario

## Alcance implementado

La importación de inventario ahora identifica cada producto en este orden:

1. ID interno válido.
2. SKU único.
3. Producto nuevo cuando ninguno coincide.

## Reglas

- Un ID y un SKU que apunten a productos distintos bloquean la fila.
- Un ID inexistente puede usar el SKU como respaldo y genera advertencia.
- Los SKU duplicados dentro del mismo archivo se bloquean.
- Un producto nuevo exige SKU y nombre.
- Las celdas vacías no se convierten automáticamente en cero.
- Los productos que no aparecen en el Excel no se eliminan ni se desactivan.
- La vista previa diferencia: crear, actualizar, sin cambios y error.
- Los campos no incluidos o vacíos conservan su valor actual al actualizar.

## Archivos

- `js/services/inventory-import-service.js`
- `js/imports.js`
- `tests/inventory-import-service.test.js`

## Limitación pendiente

La aplicación de los cambios sigue realizándose registro por registro desde el frontend. La transacción por lote, el registro detallado de filas y la descarga de errores corresponden a las fases 17 y 18.
