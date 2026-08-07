# Fase 24 — Coherencia de migraciones 024 a 029

## Hallazgo

La revisión conjunta detectó que las migraciones 024 y 026 representaban algunas columnas con nombres diferentes:

- `receipt_status` y `reception_status`.
- `financial_account_id` y `account_id` en pagos a proveedores.
- `payment_date` y `paid_at`.
- `currency_code` y `currency`.
- La tabla de movimientos creada en 024 no incluía `performed_by`, mientras las RPC posteriores sí lo utilizaban.
- La restricción inicial de `movement_type` no admitía `saldo_inicial`.

Aplicar los archivos sin una capa de compatibilidad podía provocar errores al ejecutar pagos, transferencias, saldos iniciales o reportes.

## Corrección

La migración `029_coherencia_migraciones_fase_24.sql`:

1. Establece `reception_status` como nombre canónico y mantiene sincronizado el alias histórico `receipt_status`.
2. Normaliza los tipos de cuenta a `billetera_digital`, `efectivo`, `banco` u `otro`.
3. Completa las columnas utilizadas por movimientos, transferencias y reversiones.
4. Migra los pagos históricos hacia `financial_account_id` y `payment_date` sin borrar los alias antiguos.
5. Recompila la vista de conciliación de compras y pagos.
6. Crea `validate_lihen_schema_coherence()`, que informa columnas o RPC faltantes.

## Orden recomendado

Para una instalación nueva, ejecutar las migraciones numéricamente y finalizar con 029.

Para una base donde ya se aplicaron algunas fases, ejecutar primero una copia de seguridad y después 029. La migración es idempotente y no inserta operaciones financieras falsas.

## Verificación en Supabase

Después de ejecutar 029:

```sql
select public.validate_lihen_schema_coherence();
```

El resultado esperado debe contener:

```json
{
  "ok": true,
  "missing_columns": [],
  "missing_functions": []
}
```

Esta verificación confirma estructura y firmas, pero no reemplaza las pruebas funcionales con datos de ensayo.
