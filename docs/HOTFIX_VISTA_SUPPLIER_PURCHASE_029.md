# Hotfix migración 029

Se corrigió la recreación de la vista `public.v_supplier_purchase_account_status`.

PostgreSQL no permite cambiar el nombre u orden de columnas de una vista existente mediante `CREATE OR REPLACE VIEW`. La migración ahora ejecuta primero:

```sql
drop view if exists public.v_supplier_purchase_account_status;
```

y luego crea nuevamente la vista con su estructura actualizada. El cambio no elimina datos de compras, proveedores ni pagos porque una vista no almacena esos registros.
