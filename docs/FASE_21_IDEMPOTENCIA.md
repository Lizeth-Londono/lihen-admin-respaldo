# Fase 21 — Idempotencia transversal

## Objetivo

Impedir que un doble clic, reintento de red, recarga o repetición accidental vuelva a ejecutar una operación sensible y duplique stock, ventas, pagos o movimientos.

## Implementación

Se añadió `operation_executions` como registro central de ejecuciones. Cada operación usa:

- tipo de operación;
- clave única generada en el navegador;
- usuario responsable;
- huella de los datos enviados;
- estado y resultado final.

PostgreSQL toma un bloqueo transaccional por tipo y clave. Si la misma clave llega otra vez con los mismos datos, devuelve el resultado anterior. Si llega con datos diferentes, se rechaza.

## Flujos protegidos físicamente en la copia actual

- creación de pedidos;
- creación de ventas rápidas;
- anulación de ventas rápidas;
- pago y entrega directa de pedidos;
- importación masiva de inventario, que ya tenía su propia clave idempotente.

El modelo de la fase 20 ya exige claves únicas en recepciones de proveedor, movimientos financieros y pagos a proveedores. Las RPC funcionales de esos módulos deberán usar esas claves cuando las fases 2 a 15 sean reconstruidas e integradas físicamente.

## Compatibilidad

Las funciones originales se conservan. El frontend pasa a utilizar envolturas idempotentes, lo cual evita romper módulos SQL históricos mientras se agrega protección contra reintentos.
