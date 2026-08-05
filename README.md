# LIHEN Admin Pro

Centro operativo privado de LIHEN.CO para las dos cofundadoras.

## Funciones incluidas

- Autenticación real con Supabase y validación del perfil `cofundadora`.
- Dashboard ejecutivo con prioridades operativas.
- Pedidos con reserva automática de inventario y faltantes por conseguir.
- Descuentos manuales por porcentaje o valor fijo.
- Métodos de pago: efectivo contra entrega, Nequi, llave bancaria y transferencia.
- Inventario físico, reservado, libre y pendiente.
- Ajustes de inventario con motivo y trazabilidad.
- Productos, catálogo web e importación inicial desde `catalogo_maestro.csv`.
- Clientes, direcciones y contacto por WhatsApp.
- Proveedores, tiempos de entrega y solicitudes por WhatsApp.
- Comprobantes de pedido con identidad visual de LIHEN e impresión a PDF.
- Movimientos y auditoría.
- Reportes de ventas, ticket promedio y productos más solicitados.
- Diseño responsive para computador y celular.

## Publicación en GitHub Pages

1. Crear un repositorio privado o público para la interfaz, por ejemplo `lihen-admin`.
2. Subir **el contenido de esta carpeta**, no la carpeta contenedora.
3. En GitHub: `Settings > Pages > Deploy from a branch > main / root`.
4. La dirección esperada será parecida a:
   `https://lihen-co-admin.github.io/lihen-admin/`
5. En Supabase: `Authentication > URL Configuration`.
6. Cambiar `Site URL` por la dirección definitiva.
7. Agregar en `Redirect URLs`:
   `https://lihen-co-admin.github.io/lihen-admin/**`
8. Desde Authentication > Users enviar recuperación de contraseña a las dos cofundadoras para que el enlace ya llegue al sistema definitivo.

## Configuración de Supabase

La URL pública y la publishable key están en `js/config.js`. Nunca agregar una `secret key` ni `service_role` al navegador o a GitHub.

Las migraciones aplicadas están en `sql/`:

- `002_storage_and_security.sql`
- `003_order_inventory_operations.sql`
- `004_supplier_orders_and_payments.sql`
- `005_public_catalog_view.sql`

La estructura base (Migración 001) ya fue ejecutada directamente en el proyecto Supabase durante la configuración inicial.

## Carga inicial

1. Entrar al sistema.
2. Ir a **Inventario y catálogo**.
3. Pulsar **Importar catálogo CSV**.
4. Seleccionar `data/catalogo_maestro.csv`.
5. Realizar después una conciliación física usando **Movimientos > Registrar ajuste**.

## Seguridad

- Los comprobantes deben permanecer en el bucket privado.
- No subir contraseñas, secret keys ni capturas con tokens.
- Cada cofundadora debe usar su propia cuenta.
- Los datos de clientes y proveedores están protegidos mediante RLS.

## Actualización 2.0: edición e importaciones

Esta versión agrega edición de clientes, proveedores y productos; importación masiva del inventario Excel por SKU; importación de clientes/proveedores; validación de duplicados; plantillas y una identidad visual más cercana al catálogo público.

Antes de usar estas funciones ejecuta `sql/006_edicion_e_importaciones.sql` en Supabase.

Consulta `docs/GUIA_ACTUALIZACION_2_0.md` para el procedimiento completo.
