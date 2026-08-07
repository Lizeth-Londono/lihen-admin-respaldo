# Fase 23 — Confirmaciones obligatorias

## Objetivo

Evitar que una acción sensible se ejecute por error. La confirmación debe resumir el impacto real antes de aplicar cambios en Supabase, inventario, pagos o reportes.

## Implementación

Se creó `js/services/confirmation-service.js`, un componente reutilizable que:

- usa un diálogo accesible `role="alertdialog"`;
- muestra título, explicación y resumen de impacto;
- admite tonos `primary`, `warning` y `danger`;
- devuelve una promesa booleana;
- permite cancelar con botón, clic fuera o tecla Escape;
- devuelve el foco al control original;
- escapa todo el texto dinámico.

## Flujos conectados en la copia actual

- Importación masiva de inventario.
- Carga del inventario inicial integrado.
- Importación de proveedores.
- Importación de clientes.
- Anulación de ventas rápidas.
- Registro directo de pago y entrega de pedidos.

## Alcance futuro obligatorio

Cuando se reconstruyan físicamente las fases 2 a 15, este mismo servicio debe conectarse con:

- confirmación de compras a proveedores;
- recepción parcial o completa;
- registro y anulación de pagos a proveedores;
- ajustes financieros;
- corrección de saldos iniciales;
- transferencias entre cuentas;
- cambios masivos de costo y precio.

## Regla

La confirmación visual no reemplaza las validaciones, la idempotencia ni las transacciones de PostgreSQL. Solo añade una barrera explícita antes de ejecutar la operación.
