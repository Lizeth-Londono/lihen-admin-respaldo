# Revisión final del paquete LIHEN_ADMIN_PRO

## Resultado local

- 75 pruebas automatizadas aprobadas.
- 48 módulos JavaScript verificados.
- Rutas locales e importaciones verificadas.
- No se detectaron archivos temporales, logs ni claves privadas `service_role`.
- El paquete excluye el historial `.git` y `node_modules`.

## Archivo SQL principal

Para una instalación normal sobre la base histórica de LIHEN (migraciones 001 a 013 ya aplicadas), usar:

`sql/supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql`

No ejecutar además los archivos 022 a 029 por separado, porque ya están integrados en el consolidado.

## Verificación obligatoria en Supabase

Después de ejecutar la migración, correr:

```sql
select public.validate_lihen_schema_coherence();
```

Debe devolver `ok: true`, sin columnas ni funciones faltantes.

## Limitación de certificación

Las pruebas locales no sustituyen una prueba contra el proyecto Supabase real. Antes de publicar, se debe validar login, RLS, compras, recepciones, pagos, movimientos, ventas, pedidos, reportes, exportación e importación, consola y red.

## Integridad del paquete

`RELEASE_MANIFEST_SHA256.txt` contiene el hash SHA-256 de cada archivo incluido.
