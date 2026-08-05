# LIHEN Admin — mejora de edición, resumen y comprobante

## Cambios
- El editor vuelve a consultar el pedido completo antes de mostrarlo, incluyendo `order_items`.
- Los productos existentes se cargan al editar.
- Selector rápido más amplio y adaptable.
- Botones `+`, `−` y `Eliminar` por producto.
- Un producto repetido aumenta la cantidad y no crea una fila duplicada.
- Totales, unidades y cantidad de referencias se recalculan en vivo.
- Vista previa del resumen antes de abrir WhatsApp.
- Acciones compactas en el detalle del pedido.
- El comprobante final solo se habilita para pedidos entregados y pagados.
- Mensaje final de agradecimiento actualizado a la versión aprobada por LIHEN.

## Pruebas técnicas realizadas
- Validación de sintaxis JavaScript con `node --check`.
- Verificación de importaciones y selectores utilizados en los módulos modificados.
- Verificación de caché de `index.html` actualizada.

## Pruebas que deben hacerse conectadas a Supabase
1. Abrir el pedido existente y comprobar que aparecen todos sus productos.
2. Agregar un producto nuevo.
3. Agregar uno repetido y comprobar que suma la cantidad.
4. Aumentar y disminuir cantidad.
5. Eliminar y cancelar la edición sin guardar.
6. Guardar y verificar total e inventario.
7. Revisar la vista previa y abrir WhatsApp.
8. Marcar un pedido como entregado y pagado antes de generar el comprobante final.
