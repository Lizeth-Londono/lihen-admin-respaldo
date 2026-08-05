# Pruebas realizadas

## Validaciones automáticas

- Sintaxis verificada con `node --check` para todos los archivos JavaScript del proyecto.
- Confirmación de que `index.html` carga `app.css`, SheetJS y `main.js` en el orden correcto.
- Revisión del Excel oficial: hojas `Beauty Care`, `Style`, `Configuración` y `Movimientos`.
- Verificación del encabezado real del inventario y de las posiciones usadas por el importador.
- Revisión del CSV maestro separado por punto y coma.

## Flujos revisados en código

- Creación manual de cliente, proveedor y producto.
- Edición de cliente, proveedor y producto.
- Advertencia de SKU duplicado.
- Importación de inventario por SKU.
- Creación o actualización de inventario físico.
- Importación de clientes y proveedores.
- Conservación del flujo de pedidos existente.
- Registro de auditoría en acciones de edición e importación, cuando la tabla lo permite.

## Pruebas pendientes en el proyecto real

Estas requieren la base de datos Supabase de LIHEN y deben hacerse después de ejecutar la Migración 006:

1. Importar una copia de prueba del Excel con 2 o 3 productos.
2. Editar un cliente y confirmar que no se crea un duplicado.
3. Editar un proveedor.
4. Editar un producto y comprobar el bloqueo del SKU repetido.
5. Importar clientes y proveedores usando las plantillas.
6. Crear un pedido y confirmar que el inventario importado aparece en el selector.

Se recomienda hacer primero una prueba con una copia reducida del archivo y luego importar el archivo completo.
