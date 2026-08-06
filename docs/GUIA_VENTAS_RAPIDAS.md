# Ventas rápidas LIHEN

1. Ejecuta `sql/011_ventas_rapidas_pos.sql` en Supabase.
2. Publica el frontend actualizado en GitHub Pages.
3. En el menú abre **Ventas rápidas** y pulsa **Nueva venta rápida**.
4. El cliente puede quedar como **Consumidor final**.
5. Selecciona productos, pago y referencia opcional.
6. Al guardar, el stock físico se descuenta inmediatamente y queda un movimiento `ajuste_negativo` con la razón de la venta.
7. Abre una venta para imprimir o enviar el comprobante si el cliente tiene teléfono.
8. La anulación mediante RPC devuelve el stock y conserva auditoría; no borra registros.
