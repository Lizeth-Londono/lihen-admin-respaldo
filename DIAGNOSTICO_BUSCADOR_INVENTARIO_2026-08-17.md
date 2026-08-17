# Diagnóstico — buscador de Inventario LIHEN

Fecha: 2026-08-17

## Resumen ejecutivo

La causa raíz está confirmada en el frontend de LIHEN Admin: `js/repositories/product-repository.js` limitaba la consulta de productos a **300 registros** con `limit(300)`.

La pantalla `Inventario y catálogo` construye su contador usando `state.products.length`, y el buscador filtra únicamente las filas que ya fueron renderizadas en el navegador. Por eso la interfaz mostraba exactamente **300 productos** y cualquier producto que quedara fuera de esos primeros 300 no podía aparecer en el buscador, aunque existiera en el inventario/base de datos.

El Excel `Inventario_Actual_LIHEN_2026-08-17 (2).xlsx` contiene datos hasta la fila 467 (fila 1 = encabezado), es decir **466 filas de producto**. Se verificaron productos posteriores al límite, por ejemplo `BC-301`, `BC-302`, `BC-303` y productos del final como `BC-453` y `ST-013`.

## Ruta del problema

1. `views.js` entra a Inventario y ejecuta `loadProducts()`.
2. `store.js` delega en `listProducts()`.
3. `product-repository.js` consultaba Supabase y terminaba con `.limit(300)`.
4. `state.products` quedaba truncado a un máximo de 300 productos.
5. `views.js` renderizaba exclusivamente `state.products` y mostraba `${state.products.length} productos`.
6. `main.js` filtraba las filas existentes del DOM; no hacía una nueva consulta a Supabase.
7. Resultado: un producto fuera de los primeros 300 era imposible de encontrar desde ese buscador.

## Causa raíz

Archivo: `js/repositories/product-repository.js`

Comportamiento anterior:

```js
export async function listProducts(search = '', limit = 300) {
  let query = supabase.from('products').select(PRODUCT_SELECT).order('name');
  if (search) query = query.ilike('name', `%${search}%`);
  return unwrap(await query.limit(limit), 'No fue posible cargar los productos.') || [];
}
```

El parámetro `limit = 300` era un límite artificial del catálogo administrativo.

## Corrección aplicada

### 1. Carga paginada completa

Se reemplazó el límite fijo por paginación con `.range(...)` en bloques de 200 productos hasta recibir una página incompleta.

Además se agregó orden estable por `name` + `id` para evitar saltos o duplicados entre páginas cuando varios productos tienen el mismo nombre.

Archivo modificado:

- `js/repositories/product-repository.js`

### 2. Búsqueda más completa

El buscador de Inventario ahora puede encontrar coincidencias por:

- nombre;
- SKU;
- Código catálogo;
- marca;
- categoría;
- subcategoría.

Cada fila de producto expone un `data-product-search` con esos términos normalizados.

Archivo modificado:

- `js/views.js`

### 3. Búsqueda + filtro de visibilidad combinados

Antes el buscador y el selector de visibilidad podían sobrescribir mutuamente el atributo `hidden` de las filas. Ahora ambos criterios se evalúan juntos mediante `applyProductFilters()`.

Archivo modificado:

- `js/main.js`

## Seguridad e integridad

Este hotfix solo modifica lectura, paginación, búsqueda y presentación de productos.

No modifica:

- stock;
- costos;
- precios;
- proveedores;
- visibilidad almacenada;
- estados almacenados;
- SKU;
- Código catálogo;
- pedidos;
- ventas rápidas;
- compras a proveedores.

No requiere migración SQL.

## Pruebas agregadas

Archivo nuevo:

- `tests/inventory-full-product-search-2026-08-17.test.js`

Valida que:

1. ya no exista `limit(300)` en el repositorio de productos;
2. exista paginación por `.range(...)`;
3. la paginación tenga orden estable `name` + `id`;
4. las filas incluyan nombre, SKU, código catálogo, marca, categoría y subcategoría en la búsqueda;
5. búsqueda y visibilidad se combinen sin pisarse.

## Resultado de pruebas locales

- `npm test`: **175 aprobadas / 0 fallidas**.
- `npm run check`: **53 módulos JavaScript verificados correctamente**.

## Validación pendiente en producción

El entorno de análisis no consulta directamente la base Supabase de producción, por lo que la comprobación final del total real almacenado debe hacerse al desplegar el cambio.

Después de publicar el hotfix, la pantalla ya no debería detenerse en 300. El contador debe reflejar el total que realmente devuelve `products` en Supabase.

Como control, buscar después del despliegue productos posteriores al antiguo corte, por ejemplo:

- `BC-301` — Mascarilla Regenerador Intenso 7 Oleos
- `BC-302` — Mascarilla WOW
- `BC-303` — Definidor de rizos
- `BC-453` — Set de Broncha
- `ST-013` — Aretes plateados pequeños

Si alguno de ellos no aparece después de que el contador supere 300, el siguiente diagnóstico debe verificar específicamente si ese registro existe en `public.products` en Supabase.

## Archivos modificados

- `js/repositories/product-repository.js`
- `js/views.js`
- `js/main.js`

## Archivo agregado

- `tests/inventory-full-product-search-2026-08-17.test.js`
- `DIAGNOSTICO_BUSCADOR_INVENTARIO_2026-08-17.md`

## Despliegue recomendado

```bash
git add js/repositories/product-repository.js js/views.js js/main.js tests/inventory-full-product-search-2026-08-17.test.js DIAGNOSTICO_BUSCADOR_INVENTARIO_2026-08-17.md
git status
git commit -m "fix: cargar inventario completo y ampliar buscador de productos"
git push origin main
```

Después del despliegue de GitHub Pages, hacer `Ctrl + Shift + R` y volver a abrir `Inventario y catálogo`.
