# Supabase de LIHEN Admin

La base principal fue creada en el proyecto Supabase el 4 de agosto de 2026 mediante la migración `001_core_schema.sql`.

Orden restante:
1. Ejecutar `002_storage_and_security.sql`.
2. Crear las dos usuarias desde Authentication > Users.
3. Importar `data/catalogo_maestro.csv` desde la pantalla Inventario y catálogo.
4. Realizar conciliación física antes de cargar cantidades del Excel.

## 003_order_inventory_operations.sql

Agrega operaciones transaccionales para:

- Crear pedidos y reservar inventario sin duplicar unidades.
- Identificar automáticamente cantidades por conseguir.
- Cancelar pedidos y liberar reservas.
- Entregar pedidos y descontar stock físico.
- Ajustar inventario dejando trazabilidad.

Debe ejecutarse después de `002_storage_and_security.sql`.

- `004_supplier_orders_and_payments.sql`: solicitudes a proveedores, recepción y pagos.
- `005_public_catalog_view.sql`: vista pública para alimentar el catálogo.

- 008_edicion_pedidos_y_whatsapp.sql: edición transaccional, reservas diferenciales, auditoría y flujo WhatsApp.


## Migración 009

Ejecuta `009_corregir_guardado_edicion_pedidos.sql` para corregir la persistencia al agregar, modificar o eliminar productos de pedidos existentes. Esta migración crea la RPC `update_order_atomic_v2`.


## Migración 011 — Ventas rápidas
Ejecuta `011_ventas_rapidas_pos.sql` una sola vez para crear el módulo POS ligero, tablas, RLS y RPC transaccionales.

## Migraciones de ampliación LIHEN

Después de las migraciones base, ejecutar en orden `022` a `029`. La migración `029_coherencia_migraciones_fase_24.sql` es la capa final de compatibilidad entre los nombres de columnas usados durante la evolución de compras, caja, pagos y reportes. Al terminar, ejecutar:

```sql
select public.validate_lihen_schema_coherence();
```

## Instalación simplificada — archivo consolidado

Para una base LIHEN que ya tenga instaladas las migraciones históricas 001 a 013, puede ejecutarse un solo archivo:

`supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql`

Este archivo incluye, en orden, los bloques 022 a 029. No debe combinarse con una ejecución simultánea de esos mismos archivos individuales. Después de ejecutarlo, validar con:

```sql
select public.validate_lihen_schema_coherence();
```

Consulta `docs/GUIA_INSTALACION_MIGRACION_CONSOLIDADA.md` antes de aplicarlo en producción.
