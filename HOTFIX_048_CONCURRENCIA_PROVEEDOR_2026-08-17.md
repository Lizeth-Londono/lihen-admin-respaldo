# Hotfix 048 — concurrencia de proveedor en importación de inventario

## Causa confirmada
El mensaje `Conflicto de concurrencia ... campo supplier_name` se genera dentro de la RPC PostgreSQL `public.import_inventory_batch_atomic`, definida por la migración 043. Por eso un cambio solo en el frontend no puede eliminar el error mientras la función antigua siga instalada en Supabase.

## Cambios
1. Nueva migración `sql/048_hotfix_concurrencia_supplier_name_importacion.sql` que reemplaza la RPC y elimina únicamente el control optimista de `supplier_name`.
2. Se conserva el control de concurrencia para campos propios de `products` y para stock.
3. El frontend ya no envía `supplier_name` en actualizaciones cuando el proveedor no forma parte de los cambios reales de la fila.
4. Los productos nuevos siguen pudiendo asociar proveedor.

## Despliegue obligatorio
1. Ejecutar completa la migración 048 en Supabase SQL Editor.
2. Subir los cambios de frontend a GitHub.
3. Recargar el ADMIN con Ctrl+Shift+R.
4. Volver a generar la vista previa e importar.

## Validación local
`npm test`: 171 pruebas aprobadas, 0 fallidas.
