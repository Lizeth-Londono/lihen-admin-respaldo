# Fase 19 — Seguridad, permisos, restricciones, índices y RLS

## Alcance real

Esta fase endurece la parte físicamente consolidada en la copia de trabajo actual: el flujo de importación de inventario implementado en las fases 16, 17 y 18. No afirma proteger módulos de compras, caja o pagos que aún no están presentes en esta misma copia.

## Cambios aplicados

- RLS habilitado y forzado en `import_batches` e `import_batch_rows`.
- Lectura limitada a cofundadoras activas autenticadas.
- Escritura directa retirada a `authenticated` y `anon`.
- La RPC `import_inventory_batch_atomic` queda como único canal autorizado de escritura.
- Ejecución de RPC retirada a `public` y `anon`.
- `search_path` vacío y tiempo máximo de ejecución de 120 segundos.
- Restricciones para conteos, estados, JSON, tamaños y coherencia de errores.
- Unicidad de `(batch_id, row_number)`.
- Índices para historial por fecha, usuario, estado, lote y SKU.
- Validador reutilizable de identidad, tamaño y estructura del lote.
- Comprobación de que el frontend utiliza una clave publicable y no una `service_role`.

## Decisiones de seguridad

La aplicación se despliega en GitHub Pages, por lo que todo valor incluido en JavaScript es público. La clave publicable de Supabase puede estar en el cliente; una clave `service_role` nunca debe estar allí.

Las operaciones masivas se mantienen detrás de funciones `SECURITY DEFINER`, pero cada función valida `public.is_active_cofounder()` antes de actuar. Las tablas de trazabilidad no aceptan escrituras directas desde el navegador.

## Aplicación

Ejecutar en Supabase SQL Editor después de la migración 022:

```text
sql/023_seguridad_supabase_fase_19.sql
```

Antes de producción, realizar copia de seguridad y comprobar que `is_active_cofounder()` existe y representa correctamente los roles activos de LIHEN.

## Limitación

No se dispone dentro del ZIP de la migración base `001_core_schema.sql`, por lo que no es posible verificar offline todas las políticas, llaves foráneas, enums y privilegios reales de la base activa. Esta migración es defensiva, pero debe probarse primero en un entorno de ensayo conectado a una copia del esquema real.
