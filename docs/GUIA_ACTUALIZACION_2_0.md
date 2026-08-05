# LIHEN Admin 2.0 — Guía de actualización

## Cambios incluidos

- Edición de clientes, proveedores y productos desde sus módulos.
- Validación de SKU repetido antes de crear o editar un producto.
- Importación masiva del archivo `Inventario_LIHEN_Corregido_Final.xlsx`.
- Importación de clientes y proveedores desde Excel o CSV.
- Vista previa y resumen antes de importar el inventario.
- Accesos rápidos desde el inicio.
- Estilo visual más claro y cercano al catálogo público de LIHEN.
- Plantillas CSV de ejemplo dentro de `data/plantillas`.

## Paso obligatorio en Supabase

Antes de usar la edición de estado de clientes y el control reforzado de duplicados, abre:

`Supabase → SQL Editor → New query`

Copia y ejecuta una sola vez:

`sql/006_edicion_e_importaciones.sql`

El resultado correcto es `Success. No rows returned`.

## Importar el inventario oficial

1. Ingresa a `Inventario y catálogo`.
2. Pulsa `Importar inventario`.
3. Selecciona `Inventario_LIHEN_Corregido_Final.xlsx`.
4. Revisa el resumen: filas válidas, nuevos, actualizaciones y SKU repetidos.
5. Si el archivo no tiene SKU repetidos, pulsa `Importar inventario`.

La plataforma reconoce las hojas `Beauty Care` y `Style` y toma:

- SKU
- categoría
- subcategoría
- producto
- marca
- proveedor
- costo real unitario
- precio sugerido LIHEN
- stock actual
- stock mínimo

Los productos se actualizan por SKU. Los que no existen se crean. Los proveedores no existentes quedan pendientes para ser registrados, evitando crear contactos incorrectos automáticamente.

## Editar registros

- Clientes: `Clientes → Editar`.
- Proveedores: `Proveedores → Editar`.
- Productos: `Inventario y catálogo → Editar`.

El stock físico no se modifica desde la edición del producto. Para eso se utiliza `Movimientos → Registrar ajuste`, conservando la trazabilidad.

## Importar clientes y proveedores

Dentro de cada módulo aparece el botón `Importar`.

- Clientes se identifican principalmente por WhatsApp.
- Proveedores se identifican principalmente por nombre comercial.
- Los registros existentes se actualizan y los nuevos se crean.

Las plantillas están en:

- `data/plantillas/plantilla_clientes.csv`
- `data/plantillas/plantilla_proveedores.csv`
- `data/plantillas/plantilla_productos_inventario.csv`

## Publicación

Después de reemplazar los archivos en la carpeta local:

```bash
git add .
git commit -m "Actualizar LIHEN Admin 2.0"
git pull --rebase origin main
git push
```

Espera uno o dos minutos y actualiza GitHub Pages con `Ctrl + F5`.
