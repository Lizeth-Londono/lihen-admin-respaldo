# Corrección de edición de productos en pedidos

## Cambios

- La lista de productos queda visible debajo de la selección rápida y tiene desplazamiento propio.
- El editor usa un único arreglo como fuente de verdad.
- Agregar, sumar, restar, eliminar, vista previa y guardado usan el mismo estado.
- Un producto eliminado no se envía en `p_items`.
- Después de ejecutar `update_order_atomic`, el frontend vuelve a consultar `order_items` y solo muestra éxito cuando lo guardado coincide con el editor.

## Prueba recomendada

1. Abrir un pedido con varios productos.
2. Eliminar uno y confirmar.
3. Pulsar **Guardar cambios**.
4. Volver a abrir el pedido.
5. Confirmar que el producto no aparece y que el total cambió.
6. Abrir **Vista previa** y confirmar que usa la misma lista.

No requiere una migración adicional de Supabase: continúa usando la migración 008 ya ejecutada.
