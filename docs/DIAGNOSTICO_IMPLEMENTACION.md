# Diagnóstico e implementación

## Estructura revisada

La aplicación es un frontend estático en JavaScript modular publicado con GitHub Pages y conectado directamente a Supabase. Los módulos principales son:

- `js/main.js`: navegación y eventos.
- `js/views.js`: vistas del panel.
- `js/forms.js`: altas manuales y pedidos.
- `js/store.js`: consultas y estado.
- `js/supabase.js`: cliente de Supabase.
- `css/app.css`: identidad visual.

## Problemas encontrados

1. Los botones de edición estaban dibujados en algunos módulos, pero no tenían flujo operativo.
2. No existía importador para el Excel de inventario con SKU.
3. El importador existente solo atendía el CSV del catálogo público y no conciliaba stock.
4. Los módulos de clientes y proveedores no tenían cargue masivo.
5. El estilo administrativo era más oscuro y pesado que el catálogo público.
6. La validación de SKU dependía únicamente de la base de datos y no mostraba una advertencia clara antes de guardar.

## Archivos modificados o agregados

- `index.html`
- `css/app.css`
- `js/main.js`
- `js/views.js`
- `js/forms.js`
- `js/editors.js` — nuevo
- `js/imports.js` — nuevo
- `sql/006_edicion_e_importaciones.sql` — nuevo
- `data/plantillas/*` — nuevos
- `docs/*` — nuevos

## Alcance implementado

- Edición completa de cliente, proveedor y producto.
- Importación masiva del inventario oficial por SKU.
- Importación de clientes y proveedores.
- Protección visual y SQL frente a SKU, código de catálogo y WhatsApp duplicados.
- Vista previa del inventario antes de guardar.
- Conservación del ingreso manual para trabajo desde celular.
- Rediseño más claro, cálido y alineado con la página pública.

## Limitaciones conscientes

- Los proveedores del Excel que aún no existan no se crean automáticamente: quedan pendientes de revisión.
- La importación de inventario iguala el stock físico al valor del Excel. Debe ejecutarse sobre un conteo actualizado.
- Las imágenes del catálogo no se importan desde el Excel de inventario porque ese archivo no contiene rutas de imagen.
- La sincronización final del catálogo público con Supabase continúa separada hasta que el catálogo deje de depender del CSV.
