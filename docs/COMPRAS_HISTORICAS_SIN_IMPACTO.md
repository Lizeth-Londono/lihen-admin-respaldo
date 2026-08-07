# Compras históricas sin impacto actual

La opción **Compra histórica** registra compras antiguas y asocia sus productos con el proveedor existente.

Reglas:

- No aumenta ni disminuye inventario.
- No modifica stock pendiente o reservado.
- No descuenta Nequi, efectivo ni otras cuentas.
- No crea movimientos financieros actuales.
- No crea productos: exige seleccionar productos existentes.
- Conserva cantidades, costos, fecha, pago y referencia como información histórica.
- Las compras históricas quedan excluidas de los totales financieros actuales.

Para instalar en una base que ya recibió la migración consolidada anterior, ejecute únicamente:

`sql/030_compras_historicas_sin_impacto.sql`
