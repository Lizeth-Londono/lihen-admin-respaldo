# LIHEN Admin — Pedidos, edición y WhatsApp

1. Ejecuta `sql/008_edicion_pedidos_y_whatsapp.sql` en Supabase una sola vez.
2. En Nuevo pedido usa la zona superior para agregar productos consecutivamente.
3. Abre un pedido y usa **Editar pedido** para agregar, quitar o cambiar cantidades, precios, descuento, domicilio, pago, notas o estado.
4. Los pedidos entregados y cancelados quedan bloqueados para proteger el inventario.
5. **Enviar resumen para confirmar** abre el WhatsApp del cliente con el mensaje completo. Debes tener iniciada la cuenta corporativa de LIHEN en WhatsApp Web.
6. Los enlaces oficiales están en Configuración y en los comprobantes.

La edición recalcula las reservas dentro de una función SQL transaccional y deja auditoría.
