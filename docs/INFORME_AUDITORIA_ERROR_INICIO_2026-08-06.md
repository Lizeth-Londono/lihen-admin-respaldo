# Informe técnico — error de inicio de LIHEN Admin

Fecha: 6 de agosto de 2026

## Resultado de la auditoría

Se encontró una causa raíz concreta en el frontend.

### Error crítico

- Archivo: `js/sales.js`
- Línea original: 2
- Importación incorrecta:

```js
import { QUICK_SALE_QUICK_SALE_PAYMENT_LABELS } from './constants.js';
```

- Exportación real disponible en `js/constants.js`:

```js
export const QUICK_SALE_PAYMENT_LABELS = Object.freeze({ ... });
```

El módulo `sales.js` solicitaba una exportación que no existe. En JavaScript ES Modules, una exportación nombrada inexistente impide evaluar el módulo. Como `js/main.js` importa `sales.js` durante el arranque, el navegador detenía todo el grafo de módulos antes de ejecutar `boot()`. Por ese motivo, después de ocho segundos aparecía el aviso “LIHEN Admin no pudo iniciar”.

## Corrección aplicada

La importación fue corregida a:

```js
import { QUICK_SALE_PAYMENT_LABELS } from './constants.js';
```

No fue necesario modificar la lógica de ventas rápidas, pedidos, inventario ni autenticación.

## Prevención agregada

Se fortaleció `scripts/check-modules.mjs`. Antes solo comprobaba que el archivo importado existiera. Ahora también valida:

- rutas de módulos locales;
- exportaciones nombradas;
- exportaciones `default`;
- nombres importados que no existen.

Con esto, una equivocación similar hace fallar `npm run check` antes del despliegue.

## Validaciones realizadas

- `npm run check`: aprobado en 36 módulos.
- `npm test`: 8 pruebas aprobadas, 0 fallidas.
- `node --check` sobre todos los archivos JavaScript: aprobado.
- Auditoría estática de imports y exports: sin inconsistencias restantes.

## Archivos modificados

- `js/sales.js`
- `scripts/check-modules.mjs`
- `docs/INFORME_AUDITORIA_ERROR_INICIO_2026-08-06.md`

## Impacto y riesgo

- Productos existentes: sin cambios.
- Ventas existentes: sin cambios.
- Pedidos existentes: sin cambios.
- Clientes y proveedores: sin cambios.
- Supabase: sin cambios.
- GitHub Pages: se corrige el arranque del frontend.

## Supabase

No se requiere ejecutar ninguna migración SQL. La migración 013 que ya fue aplicada puede permanecer tal como está. El fallo era exclusivamente una importación incorrecta del frontend.
