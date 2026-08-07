# Importación y exportación masiva de compras

## Instalación
Si ya ejecutaste las migraciones hasta la 030, ejecuta únicamente `sql/031_importacion_exportacion_masiva_compras_proveedores.sql` en Supabase SQL Editor.

## Uso
En Proveedores aparecen tres acciones: **Importar compras**, **Exportar consolidado** y **Plantilla vacía**.

La plantilla usa las hojas `Compras`, `Productos de compra` y `Pagos`. Las compras históricas deben indicar impacto de inventario y financiero en **No**. Las compras actuales pueden crear borradores, confirmar, recibir mercancía y registrar pagos según los estados y datos incluidos.

Antes de aplicar se muestra una vista previa. Si existen errores críticos, el botón queda bloqueado y se puede descargar el archivo de filas rechazadas.
