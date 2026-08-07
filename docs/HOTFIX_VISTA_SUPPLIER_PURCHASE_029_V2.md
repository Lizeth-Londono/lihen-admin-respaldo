# HOTFIX V2 — Vista de conciliación de compras

Se corrigieron las dos definiciones de `public.v_supplier_purchase_account_status`.

La migración consolidada contenía una primera definición con `CREATE OR REPLACE VIEW`. PostgreSQL no permite quitar, renombrar o reordenar columnas de una vista existente usando esa instrucción. Ahora, antes de cada recreación, se ejecuta:

```sql
drop view if exists public.v_supplier_purchase_account_status;
```

Después se crea nuevamente la vista con el esquema esperado. El cambio no elimina compras, pagos ni proveedores porque la vista no almacena datos.
