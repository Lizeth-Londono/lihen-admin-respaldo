# DIAGNÓSTICO — BUSCADOR GLOBAL DE PRODUCTOS LIHEN ADMIN

Fecha: 2026-08-17
Proyecto base: `LIHEN_ADMIN_PRO_FIX_BUSCADOR_INVENTARIO_COMPLETO_2026-08-17`

## Resultado

Se implementó un buscador escribible/autocomplete reutilizable para seleccionar productos por nombre o SKU sin recorrer listas nativas de cientos de opciones.

## Diagnóstico previo

- **Nueva venta rápida** (`js/sales.js`) usaba `#saleProduct` como `<select>` con todos los productos.
- **Crear pedido LIHEN** (`js/order-workflow.js`) usaba `#quickProduct` como `<select>` con todos los productos.
- **Nueva compra a proveedor** (`js/supplier-purchases.js`) creaba un `<select name="product_id">` completo por cada fila de compra.
- **Inventario y catálogo** ya tenía un campo de texto que busca sobre nombre, SKU, código catálogo, marca, categoría y subcategoría; se conservó esa solución y la carga paginada de todo el catálogo.

Los tres selectores nativos eran la causa de la lista gigante mostrada por el navegador. No era un problema de Supabase ni de SQL.

## Solución implementada

Se creó `js/components/product-search.js`, un componente reutilizable tipo combobox/autocomplete que:

- busca localmente sobre `state.products`;
- busca por `name`, `sku`, `catalog_code`, `brand`, `category` y `subcategory`;
- prioriza visualmente nombre + SKU;
- ignora mayúsculas/minúsculas y tildes;
- muestra máximo 20 resultados simultáneos, sin limitar el universo real de búsqueda;
- muestra stock disponible y, cuando aplica, precio de venta;
- permite `ArrowDown`, `ArrowUp`, `Enter` y `Escape`;
- expone roles ARIA `combobox`, `listbox` y `option`;
- muestra estado “No encontramos productos…” cuando no hay coincidencias;
- guarda el identificador real `product.id`, nunca el texto escrito.

## Integraciones

### Nueva venta rápida

Se reemplazó el selector por un buscador escribible. Al seleccionar un producto:

- conserva `product.id`;
- carga `sale_price`;
- obtiene `available_stock`;
- mantiene las validaciones existentes de cantidad contra stock;
- mantiene intacta la creación de la venta, el descuento de inventario y la lógica financiera.

### Crear pedido LIHEN

Se reemplazó el selector por el mismo componente. Al seleccionar:

- carga precio de venta;
- conserva el ID;
- mantiene `addProduct(...)`, reservas, cantidades, edición y guardado existentes.

### Nueva compra a proveedor

Cada fila nueva obtiene una instancia independiente del buscador. El ID seleccionado queda almacenado en un `input type="hidden" name="product_id"` propio de esa fila.

No se mezclan selecciones entre filas y se conserva la lógica actual de cantidad y `quoted_unit_cost`.

La versión previa mostraba todos los productos en compras a proveedor; esta implementación mantiene exactamente ese alcance y no altera relaciones proveedor-producto.

### Inventario y catálogo

Se conserva el buscador textual existente, que ya permite nombre y SKU y trabaja sobre el catálogo completo cargado con paginación.

## Archivos modificados

- `js/sales.js`
- `js/order-workflow.js`
- `js/supplier-purchases.js`
- `css/app.css`

## Archivos nuevos

- `js/components/product-search.js`
- `tests/product-search-global-2026-08-17.test.js`
- `DIAGNOSTICO_BUSCADOR_PRODUCTOS_GLOBAL_2026-08-17.md`

## SQL / Supabase

**No se requiere ejecutar ningún SQL.**

Esta mejora es exclusivamente de frontend/UX y reutiliza `state.products`, que ya se carga desde Supabase con la paginación implementada en el arreglo anterior. No se modificaron tablas, vistas, RPC, RLS, funciones ni migraciones.

## Seguridad de negocio

No se modificó la lógica de:

- stock;
- reservas;
- movimientos;
- ventas;
- pedidos;
- compras;
- pagos;
- caja;
- costos;
- precios maestros;
- proveedores;
- importación Excel;
- código catálogo.

## Validaciones ejecutadas

Comandos:

```bash
npm test
npm run check
```

Resultado local:

- **183 pruebas aprobadas**
- **0 fallidas**
- **54 módulos JavaScript verificados**
- rutas locales e importaciones verificadas

Las pruebas nuevas verifican búsqueda por SKU, nombre, tildes, mayúsculas, límite visual de 20, integración en venta rápida, pedidos, compras, accesibilidad y persistencia del buscador de Inventario.

## Pruebas recomendadas después de publicar

1. Venta rápida: escribir `BC-359`, seleccionar `ACEITE DE CASTOR`, verificar precio/stock y agregar.
2. Pedido LIHEN: escribir `BC-085`, seleccionar `ACONDICIONADOR CERAMIDA` y agregar.
3. Compra a proveedor: crear dos filas, seleccionar productos distintos por SKU y confirmar que cada fila conserva su selección.
4. Inventario: buscar `BC-452` y un fragmento de nombre.
5. Probar un producto posterior al antiguo registro 300 para confirmar que sigue disponible.

## Publicación GitHub

Después de reemplazar los archivos del proyecto:

```bash
git add js/components/product-search.js js/sales.js js/order-workflow.js js/supplier-purchases.js css/app.css tests/product-search-global-2026-08-17.test.js DIAGNOSTICO_BUSCADOR_PRODUCTOS_GLOBAL_2026-08-17.md
git status
git commit -m "feat: agregar buscador global de productos por nombre y SKU"
git push origin main
```

Después del despliegue de GitHub Pages, realizar una recarga fuerte con `Ctrl + Shift + R`.
