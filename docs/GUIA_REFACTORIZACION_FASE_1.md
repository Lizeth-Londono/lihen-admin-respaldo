# LIHEN Admin — Refactorización Fase 1 (bajo riesgo)

## Objetivo

Organizar el frontend sin cambiar las funciones de negocio, las tablas de Supabase, las RPC ni el diseño visual.

## Cambios realizados

### 1. Constantes centralizadas

Se creó `js/constants.js` para mantener en un solo lugar:

- navegación principal;
- estados de pedidos;
- nombres de métodos de pago de pedidos;
- nombres de métodos de pago de ventas rápidas.

Esto evita que una misma opción aparezca escrita de manera diferente en varios módulos.

### 2. Plantillas de autenticación separadas

Las vistas de ingreso y creación de contraseña se movieron de `js/ui.js` a `js/ui-auth.js`.

`js/ui.js` conserva su interfaz pública y sigue exportando `login` y `passwordSetup`, por lo que los módulos existentes no necesitan cambiar sus importaciones.

### 3. Cálculos de pedidos separados

Se creó `js/order-calculations.js` con funciones puras para:

- descuento porcentual;
- descuento de valor fijo;
- subtotal;
- unidades;
- domicilio;
- total.

El editor de pedidos usa ahora la misma función para la vista y para la construcción del borrador.

### 4. Mensajes de pedidos separados

Se creó `js/order-messages.js` para los mensajes de:

- resumen para confirmar;
- pedido confirmado.

Así `order-workflow.js` se concentra más en el flujo de edición.

### 5. Errores y botones en espera

Se creó `js/errors.js` para:

- convertir errores de Supabase en mensajes legibles;
- desactivar botones durante procesos asíncronos;
- restaurar el botón aunque ocurra un error.

Se aplicó inicialmente al acceso, creación de contraseña y recuperación de contraseña.

### 6. Eventos globales simplificados

`js/main.js` ahora utiliza un único manejador delegado para:

- navegación;
- menú móvil;
- cierre de sesión;
- acciones principales;
- apertura de pedidos;
- apertura de ventas rápidas;
- edición de clientes, proveedores y productos.

Se eliminaron enlaces duplicados de eventos que podían provocar doble ejecución después de volver a renderizar la interfaz.

## Archivos nuevos

- `js/constants.js`
- `js/errors.js`
- `js/order-calculations.js`
- `js/order-messages.js`
- `js/ui-auth.js`

## Archivos modificados

- `js/main.js`
- `js/ui.js`
- `js/order-workflow.js`
- `js/sales.js`
- `index.html`

## Base de datos

Esta fase no cambia Supabase. No se debe ejecutar una migración SQL.

## Pruebas técnicas realizadas

- validación de sintaxis de todos los archivos JavaScript con `node --check`;
- prueba de cálculo de pedido con descuento fijo;
- prueba de cálculo de pedido con descuento porcentual;
- comprobación de importaciones y rutas de módulos;
- comprobación de que el script principal usa una versión nueva para evitar caché.

## Pruebas manuales recomendadas

1. Iniciar sesión.
2. Abrir y cerrar el menú móvil.
3. Cambiar entre todas las opciones del menú.
4. Crear un pedido y verificar cálculos.
5. Editar un pedido.
6. Abrir el resumen de WhatsApp.
7. Crear una venta rápida.
8. Buscar productos, clientes y pedidos.
9. Cerrar sesión.
10. Probar recuperación de contraseña.
