# LIHEN Admin — Pago y entrega directa / anulación de ventas

## Actualización obligatoria de Supabase

Ejecuta una sola vez:

`sql/013_anulacion_ventas_y_cierre_directo_pedidos.sql`

Debe finalizar con `Success. No rows returned`.

## Registrar un pedido ya pagado y entregado

1. Abre el pedido.
2. Pulsa **Pago y entrega**.
3. Selecciona el método de pago.
4. Escribe obligatoriamente por qué no se enviaron el resumen y la confirmación.
5. Confirma.
6. El pedido queda como **Entregado** y el pago como **Pagado**.
7. Se abre el comprobante final para descargarlo como PDF o enviarlo por WhatsApp.

Este flujo no marca el pedido como cancelado, porque la compra sí se realizó.

## Anular una venta rápida

1. Entra a **Ventas rápidas** y abre la venta.
2. Pulsa **Anular venta**.
3. Escribe un motivo de al menos ocho caracteres.
4. Confirma la acción.
5. El sistema conserva la venta como anulada y devuelve las unidades al stock.

La venta no se elimina de la base de datos, para mantener la trazabilidad.
