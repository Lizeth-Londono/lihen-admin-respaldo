# Corrección del error de inicio de LIHEN Admin

## Causa observada en consola

El navegador reportó que `js/sales.js` solicitaba una exportación inexistente llamada:

`QUICK_SALE_QUICK_SALE_PAYMENT_LABELS`

El nombre correcto exportado por `js/constants.js` es:

`QUICK_SALE_PAYMENT_LABELS`

## Estado del proyecto entregado

Se verificó que `js/sales.js` importa y utiliza el nombre correcto:

```js
import { QUICK_SALE_PAYMENT_LABELS } from './constants.js';
```

También se confirmó que `js/constants.js` exporta esa constante.

## Validaciones ejecutadas

- `npm test`: 8 pruebas aprobadas.
- `npm run check`: 36 módulos JavaScript revisados; rutas locales e importaciones/exportaciones válidas.

## Recomendación de publicación

Reemplazar los archivos del repositorio por el contenido de este ZIP, confirmar que `js/sales.js` quedó actualizado, hacer commit y push, esperar el despliegue de GitHub Pages y recargar con Ctrl + F5.
