# Auditoría responsive de modales y navegación — 2026-08-08

## Causa raíz

El componente global `.modal` limitaba su altura y ocultaba el desbordamiento (`max-height` + `overflow:hidden`), mientras `.modal-body` tenía `overflow:auto`. Sin embargo, `.modal` no era un contenedor flex/grid con una región central encogible. En formularios altos, `.modal-body` conservaba su altura intrínseca y la parte inferior podía quedar recortada antes de que apareciera un scroll útil.

## Corrección aplicada

- `.modal` ahora es un contenedor flex vertical limitado por `100dvh`.
- `header` y `footer` quedan fuera de la región desplazable.
- `.modal-body` usa `flex:1`, `min-height:0` y `overflow-y:auto`.
- La venta rápida mantiene sus acciones con `position:sticky` dentro del área desplazable.
- El `body` queda bloqueado mientras un modal esté abierto y recupera el scroll al cerrarse.
- Las confirmaciones críticas adoptan el mismo patrón header/body/footer.
- La navegación lateral permite scroll interno sin perder el footer del usuario.

## Alcance auditado

El proyecto centraliza los formularios emergentes a través de `modal()` en `js/ui.js`; se localizaron usos en pedidos, ventas rápidas, inventario, proveedores/compras, clientes, comprobantes, importaciones y caja/cuentas. La corrección del componente base cubre esos consumidores sin alterar sus reglas de negocio.

También se revisó `confirmation-service.js`, que usa una capa independiente, y la barra lateral global.

## Cambios de lógica de negocio

No se modificaron consultas, RPC, tablas, payloads, cálculos, stock, caja, anulaciones, reportes ni reglas de Supabase. Los cambios se limitan a comportamiento de interfaz, scroll y estado visual de overlays.

## Validación local

- Suite `node --test tests/*.test.js`.
- Comprobación de módulos con `node scripts/check-modules.mjs`.
- Test específico `responsive-modal-audit-2026-08-08.test.js` para evitar regresiones en flex/scroll/body-lock/sidebar.

La validación local no sustituye una prueba manual final en GitHub Pages con la sesión real de Supabase y tamaños físicos de navegador.
