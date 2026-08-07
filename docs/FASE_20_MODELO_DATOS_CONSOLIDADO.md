# Fase 20 — Modelo de datos consolidado

## Objetivo

Consolidar un modelo que respete el esquema actual de LIHEN y mantenga separados cinco hechos de negocio distintos:

1. compra o solicitud al proveedor;
2. recepción física de mercancía;
3. movimiento de inventario;
4. pago al proveedor;
5. movimiento de dinero.

## Decisión principal

No se creó una segunda tabla de encabezado llamada `supplier_purchases`. El proyecto ya utiliza `supplier_requests` y `supplier_request_items`; duplicarlas habría creado dos fuentes de verdad. La migración 024 amplía esas tablas para que puedan representar una compra formal sin perder compatibilidad con los flujos actuales.

## Entidades consolidadas

### Existentes adaptadas

- `supplier_requests`: encabezado de compra/solicitud.
- `supplier_request_items`: productos y cantidades de la compra.
- `inventory`: existencias físicas, reservadas y pendientes.
- `inventory_movements`: trazabilidad de cada cambio de inventario.
- `products`, `suppliers`, `supplier_products`, `profiles`.
- `import_batches`, `import_batch_rows`.

### Nuevas

- `supplier_purchase_receipts`
- `supplier_purchase_receipt_items`
- `financial_accounts`
- `financial_movements`
- `supplier_payments`
- `product_cost_history`
- `financial_initial_balance_history`

## Relaciones principales

```text
suppliers
  └── supplier_requests
        ├── supplier_request_items ── products
        ├── supplier_purchase_receipts
        │     └── supplier_purchase_receipt_items
        │            ├── inventory
        │            └── inventory_movements
        └── supplier_payments
               ├── financial_accounts
               └── financial_movements

products
  └── product_cost_history
```

## Reglas de integridad

- Una recepción pertenece a una sola compra.
- Un detalle de recepción pertenece a un detalle de compra.
- Una recepción no puede repetir el mismo detalle dentro del mismo evento.
- Un pago pertenece a una compra y a su proveedor.
- Cada pago posee un movimiento financiero único.
- Las claves de operación son únicas para idempotencia.
- No se permite borrar en cascada historia financiera o de inventario.
- Los importes y cantidades operativas no pueden ser negativos.
- El historial de costos se vincula con el detalle de recepción que lo originó.

## Seguridad

Las nuevas tablas permiten lectura a cofundadoras activas. La escritura directa queda retirada para usuarios autenticados y debe realizarse mediante funciones RPC transaccionales en las fases funcionales correspondientes.

No se crea ninguna cuenta con saldo, compra, recepción ni pago ficticio.

## Limitación conocida

El ZIP no incluye la migración base `001_core_schema.sql`. La migración 024 parte de las tablas que las migraciones existentes ya utilizan. Antes de ejecutarla en producción se debe respaldar la base y verificar que las migraciones base 002–013 estén aplicadas.
