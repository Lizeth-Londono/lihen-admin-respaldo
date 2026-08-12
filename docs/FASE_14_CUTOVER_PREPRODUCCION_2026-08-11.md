# Fase 14 — Cutover y preproducción LIHEN.CO

## Estado
Preparado localmente. No ejecutado contra Supabase producción desde esta sesión.

## Objetivo
Realizar un cambio controlado de catálogo estático a catálogo dinámico sin perder inventario, datos, seguridad ni posibilidad de rollback.

## Gate 0 — No empezar sin backup
Antes de ejecutar cualquier migración 039–044:

1. Exportar/respaldar la base Supabase.
2. Guardar una copia de los ZIP actuales desplegados.
3. Registrar los conteos actuales de `products`, `inventory`, `product_variants`, `product_images` e `inventory_movements`.
4. Ejecutar `sql/VERIFICACION_PRE_CUTOVER_FASE_14.sql`.
5. Resolver cualquier inconsistencia crítica antes de continuar.

## Gate 1 — Migraciones
Aplicar en orden:

1. 039
2. 040
3. 041
4. 042
5. 043
6. 044

No mezclar el despliegue de la WEB en este paso.

## Gate 2 — Verificación SQL
Ejecutar `sql/VERIFICACION_POST_CUTOVER_FASE_14.sql`.

Debe cumplirse:

- 0 columnas sensibles en `catalog_public`;
- 0 discrepancias de disponibilidad;
- funciones RPC nuevas presentes;
- `anon` sin acceso directo a tablas administrativas;
- catálogo público legible.

## Gate 3 — Configuración WEB en modo seguro
Configurar únicamente valores públicos:

```js
SUPABASE_URL: '<URL real del proyecto>',
SUPABASE_PUBLISHABLE_KEY: '<Publishable Key pública>',
CATALOG_SOURCE: 'auto',
CATALOG_FALLBACK_ON_EMPTY: true,
CATALOG_FALLBACK_ON_ERROR: true,
```

No colocar claves privadas de servidor.

## Gate 4 — Prueba controlada con 1–3 SKU
Elegir productos que ya tengan fotografía correcta.

Para cada SKU:

1. `status = activo`.
2. `visible_on_website = true`.
3. asignar/verificar precio.
4. verificar stock.
5. abrir WEB.
6. comprobar nombre, precio, imagen, disponibilidad y WhatsApp.

Después probar secuencialmente:

- cambio de precio;
- stock > 0 → 0;
- stock 0 → > 0;
- visible Sí → No;
- visible No → Sí.

Cada cambio debe reflejarse al refrescar la WEB **sin nuevo deploy**.

## Gate 5 — Seguridad desde Publishable Key
Desde el cliente público:

- `catalog_public`: lectura permitida;
- `products`: lectura directa denegada;
- `inventory`: lectura directa denegada;
- escritura: denegada.

## Gate 6 — Rollback funcional
Antes de declarar éxito, probar una vez en preproducción:

```text
CATALOG_SOURCE = static
```

La tienda debe volver al catálogo `products.js` sin romper Home, búsqueda, filtros, modal o WhatsApp.

Después regresar a:

```text
CATALOG_SOURCE = auto
```

## Gate 7 — Paso a Supabase estricto
Solo cuando todos los gates anteriores estén verdes:

```text
CATALOG_SOURCE = supabase
CATALOG_FALLBACK_ON_EMPTY = false
CATALOG_FALLBACK_ON_ERROR = true
```

Mantener fallback por error durante el primer periodo de producción.

## Criterios de aborto
Interrumpir el cutover y aplicar rollback si ocurre cualquiera:

- pérdida o duplicación de inventario;
- `catalog_public` expone costos/proveedores/stock interno;
- anon puede leer tablas administrativas;
- precio no coincide con ADMIN;
- disponibilidad no coincide con inventario;
- importación Excel deja cambios parciales;
- WEB queda vacía sin explicación;
- imágenes/variantes se multiplican por joins;
- localStorage/selección queda inutilizable de forma general.

## Rollback
Frontend inmediato:

```text
CATALOG_SOURCE = static
```

SQL, si fuera necesario, en orden inverso 044 → 039 usando los scripts `*_ROLLBACK_*`.

No revertir datos comerciales posteriores al cutover sin diagnóstico específico.
