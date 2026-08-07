# Actualización del importador para Inventario_Actual_LIHEN_2026-08-07.xlsx

## Archivo analizado

- Plantilla: `LIHEN-INVENTARIO-V1`
- Hojas: `Instrucciones` e `Inventario`
- Productos: 85
- Columnas: 19
- Líneas: 71 Beauty Care y 14 Style
- Proveedores referenciados: Glow Belleza & Accesorios y Un Mundo para Ellas
- SKU duplicados detectados en el archivo: 0
- ID internos duplicados detectados en el archivo: 0
- Stocks inferiores al reservado: 0
- Diferencias entre stock disponible y físico menos reservado: 0

Se detectó un producto con costo y precio en cero (`BC-013`, Bloom fix fijador). No se corrige ni se inventa ningún valor automáticamente; la vista previa permitirá revisarlo.

## Cambios realizados

1. El importador reconoce la hoja única `Inventario` además de las hojas heredadas Beauty Care, Style y Otros.
2. Se validan la versión `LIHEN-INVENTARIO-V1` y los encabezados oficiales.
3. Se leen correctamente `Costo real unitario` y `Precio sugerido LIHEN` tal como aparecen en el archivo descargado.
4. Los stocks decimales se rechazan; ya no se redondean silenciosamente.
5. Los valores no reconocidos de visibilidad se muestran como error.
6. `Stock reservado`, `Stock disponible` y `Stock pendiente` son informativos y nunca se sobrescriben.
7. Se bloquea un stock físico propuesto inferior al stock reservado real.
8. El proveedor se compara con proveedores activos y no reemplaza automáticamente el proveedor preferido existente.
9. Los cambios de costo provenientes del Excel quedan en `product_cost_import_history`.
10. La clave idempotente depende del contenido real del lote y evita colisiones entre archivos con valores distintos.
11. La exportación vuelve a producir la misma estructura de 19 columnas y toma `Stock mínimo` y `Estado producto` desde los campos correctos.

## Migración

Si Supabase ya tiene instaladas las migraciones hasta la 031, ejecutar únicamente:

`sql/032_compatibilidad_plantilla_inventario_2026_08_07.sql`

La migración no importa el Excel ni cambia datos por sí sola. Solo prepara y refuerza la importación segura.

## Flujo recomendado

1. Hacer respaldo de Supabase.
2. Ejecutar la migración 032.
3. Publicar el frontend actualizado.
4. Abrir Inventario y catálogo → Importar nuevo Excel.
5. Cargar `Inventario_Actual_LIHEN_2026-08-07.xlsx`.
6. Revisar la vista previa.
7. No aplicar si hay errores.
8. Confirmar únicamente los cambios intencionales.
9. Exportar el inventario nuevamente.
10. Reimportar el archivo recién exportado y comprobar que todas las filas aparezcan sin cambios.
