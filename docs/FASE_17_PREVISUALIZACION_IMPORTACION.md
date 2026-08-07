# Fase 17 — Previsualización avanzada y filas rechazadas

Esta fase amplía la importación de inventario con una revisión previa detallada antes de aplicar cambios.

## Resultado

La vista previa clasifica cada fila como crear, actualizar, sin cambios o error. También resume cambios de stock, costo, precio y visibilidad.

Las advertencias permiten continuar, pero los errores bloquean la importación. Cada error muestra fila, SKU, campo afectado, valor recibido, motivo y corrección esperada.

La usuaria puede descargar un archivo Excel llamado `*_FILAS_RECHAZADAS.xlsx`, corregir la información y cargar nuevamente la plantilla.

## Seguridad

- No se aplican cambios mientras existan errores.
- El resumen contempla todas las filas, aunque la tabla muestre solo las primeras 100.
- Los errores estructurados se generan desde el servicio de dominio, no desde el HTML.
- La descarga no contiene macros ni fórmulas.

## Pendiente

La aplicación transaccional y por lotes corresponde a la Fase 18.
