# Fase 24 — Integración de ventas y pedidos con Caja

Se conectaron las ventas rápidas y el cierre directo de pedidos con una cuenta financiera real. La usuaria debe seleccionar la cuenta que recibió el dinero; Nequi y Efectivo se sugieren automáticamente según el método de pago.

La migración `028_integracion_ventas_pedidos_caja_fase_24.sql` agrega relaciones entre ventas/pagos y cuentas/movimientos financieros, y expone RPC atómicas e idempotentes. La anulación de una venta rápida revierte tanto el inventario como el ingreso financiero, siempre que la cuenta tenga saldo suficiente.

No se altera el total de ventas para representar compras o egresos. Los saldos se construyen exclusivamente desde movimientos financieros trazables.
