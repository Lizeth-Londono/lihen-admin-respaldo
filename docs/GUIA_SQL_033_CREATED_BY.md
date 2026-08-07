# Corrección SQL 033 — `financial_movements.created_by`

## Problema corregido

Al configurar el saldo inicial de **Efectivo físico** o **Nequi**, Supabase mostraba:

```text
null value in column "created_by" of relation "financial_movements" violates not-null constraint
```

La función de saldo inicial registraba `performed_by`, pero no enviaba `created_by`, que es obligatorio en la base.

## Qué ejecutar en Supabase

1. Abre **Supabase → SQL Editor**.
2. Crea una consulta nueva.
3. Abre el archivo:

```text
sql/033_corregir_created_by_movimientos_financieros.sql
```

4. Copia todo el contenido, pégalo y pulsa **Run**.
5. Debe aparecer:

```text
Success. No rows returned
```

## Verificación

Ejecuta:

```sql
select
  column_name,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'financial_movements'
  and column_name = 'created_by';
```

Debe mostrar `is_nullable = NO` y un valor por defecto que contenga `auth.uid()`.

## Después

1. Actualiza la app con `Ctrl + F5`.
2. Configura primero una cuenta con un valor pequeño de prueba o con el saldo real.
3. Comprueba que el saldo y el movimiento inicial aparezcan una sola vez.

No vuelvas a ejecutar las migraciones 026-032. Solo ejecuta la 033.
