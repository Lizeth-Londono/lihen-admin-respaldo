# LIHEN Admin — Refactorización acumulada (Fases 1 a 4)

Esta versión conserva el comportamiento y la apariencia de LIHEN Admin, pero organiza el código para reducir errores al seguir creciendo.

## Fase 1 — Bajo riesgo

- Constantes de navegación, estados y medios de pago centralizadas.
- Autenticación visual separada de `ui.js`.
- Cálculos y mensajes de pedidos extraídos a módulos pequeños.
- Manejo uniforme de errores y botones pendientes.
- Un solo controlador principal de clics.

## Fase 2 — Acceso a datos

Se agregó `js/repositories/` para centralizar el acceso principal a Supabase:

- autenticación y perfiles;
- productos;
- pedidos y sus RPC;
- clientes;
- proveedores;
- inventario;
- ventas rápidas;
- dashboard;
- reportes.

`store.js` ahora coordina estado y repositorios en vez de construir directamente todas las consultas.

Las transacciones críticas de pedidos y ventas rápidas quedaron encapsuladas en repositorios. Los formularios e importadores heredados conservan sus operaciones originales para evitar alterar sus flujos en esta fase acumulativa.

## Fase 3 — Reglas del negocio

- Strategy para descuentos en `discount-service.js`.
- State para permisos y acciones de pedidos en `order-state-service.js`.
- Servicio único para normalizar y comparar payloads de pedidos.
- Servicio único para teléfonos y URLs de WhatsApp.
- Servicios puros para construir dashboard y reportes.
- Command Bus para las acciones globales.
- Event Bus para notificaciones internas y futuros refrescos desacoplados.

## Fase 4 — Pruebas

Se agregó una base de pruebas sin instalar dependencias adicionales:

```bash
npm test
npm run check
```

Las pruebas cubren:

- descuentos y totales;
- normalización y comparación del payload de pedidos;
- reglas de estados;
- normalización de teléfonos colombianos;
- creación de enlaces de WhatsApp;
- existencia de todas las importaciones locales.

## Resultado automatizado

- 8 pruebas aprobadas.
- 36 módulos JavaScript revisados.
- Todas las importaciones locales encontradas.
- Todos los archivos JavaScript pasan validación de sintaxis.

## Validación manual recomendada

Después de publicar en GitHub Pages:

1. Iniciar y cerrar sesión.
2. Abrir y cerrar menú móvil.
3. Crear y editar un pedido.
4. Eliminar un producto y comprobar persistencia.
5. Crear una venta rápida.
6. Abrir WhatsApp desde un pedido.
7. Abrir un comprobante.
8. Importar un archivo conocido en modo de prueba.
9. Revisar dashboard y reportes.

## Supabase

Esta refactorización no incluye migraciones nuevas ni cambios de tablas. No se debe ejecutar SQL adicional por estas fases.
