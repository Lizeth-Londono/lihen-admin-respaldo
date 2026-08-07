# FASE 26 — Preparación de entregables finales

## Estado

Esta fase prepara los archivos de entrega, pero no certifica todavía el despliegue contra el Supabase real. La entrega final del ZIP debe hacerse únicamente después de ejecutar la migración consolidada en un entorno de respaldo o prueba y completar la validación descrita en la Fase 25.

## Entregables preparados

### 1. Proyecto actualizado

La copia de trabajo contiene el frontend actualizado, servicios, repositorios, pruebas, documentación y migraciones. El nombre previsto para el paquete final es:

`LIHEN_ADMIN_PRO_ACTUALIZADO.zip`

El ZIP no se genera en esta etapa para evitar presentar como validado un proyecto que todavía no ha sido probado contra la base real de Supabase.

### 2. Migración SQL consolidada

Archivo:

`sql/supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql`

Incluye los bloques 022 a 029 en el orden correcto, con modelo de datos, importación transaccional, seguridad, idempotencia, compras, caja, pagos, transferencias, reversiones, integración de ventas y diagnóstico de coherencia.

### 3. Guía de instalación

Archivo principal:

`docs/GUIA_INSTALACION_MIGRACION_CONSOLIDADA.md`

Incluye respaldo, ejecución, diagnóstico, saldos iniciales, prueba controlada, publicación y recuperación ante errores.

### 4. Informe técnico

Archivo:

`docs/INFORME_TECNICO_FINAL_LIHEN_ADMIN_PRO.md`

Resume arquitectura, cambios, decisiones, seguridad, pruebas, riesgos y limitaciones.

### 5. Lista de cambios

Archivo:

`docs/LISTA_CAMBIOS_LIHEN_ADMIN_PRO.md`

Relaciona archivos creados o modificados con la funcionalidad que soportan.

## Validaciones locales ejecutadas

- `npm test`: 72 de 72 pruebas aprobadas.
- `npm run check`: 48 módulos JavaScript verificados.
- Rutas locales válidas.
- Importaciones y exportaciones ES Modules válidas.
- Sin uso de `service_role` en el frontend.

## Validaciones pendientes antes del ZIP final

1. Ejecutar la migración consolidada contra una copia o entorno de prueba de Supabase.
2. Ejecutar `select public.validate_lihen_schema_coherence();`.
3. Confirmar `ok = true`, sin columnas ni funciones faltantes.
4. Probar compra, confirmación, recepción, pago y anulación.
5. Probar saldo inicial, ingreso, egreso, transferencia y reversión.
6. Probar venta rápida y pago/entrega de pedido conectados con caja.
7. Probar exportación e importación del inventario de extremo a extremo.
8. Revisar consola y pestaña Network sin errores rojos ni solicitudes fallidas.
9. Probar vista móvil y escritorio.
10. Publicar en un entorno de prueba de GitHub Pages antes de producción.
