# Carga inicial y futuras actualizaciones

1. Ejecuta `sql/007_permisos_y_carga_inicial.sql` en Supabase. Este script carga los 78 productos del Excel y 131 unidades físicas, actualizando por SKU sin duplicar.
2. En LIHEN Admin usa **Cargar inventario inicial** para repetir o verificar el cargue integrado.
3. Para archivos nuevos usa **Importar nuevo Excel**. El importador reconoce las hojas Beauty Care y Style y relaciona columnas por encabezado.
4. El campo SKU es la llave principal. Los existentes se actualizan y los nuevos se crean.
5. Después de editar un producto, el botón muestra “Guardando…”, y el sistema confirma con una alerta visible. Si RLS bloquea la operación, muestra un error dentro del formulario.
