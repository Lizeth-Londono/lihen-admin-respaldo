# Fase 25 — Revisión de criterios de aceptación

Fecha de revisión: 2026-08-06

## Alcance de esta certificación

Esta revisión se realizó sobre la copia de trabajo local del frontend y las migraciones SQL. Se ejecutaron las pruebas automatizadas y el verificador estático de módulos.

Resultados locales:

- 69 pruebas automatizadas aprobadas.
- 48 módulos JavaScript verificados.
- Rutas locales e importaciones válidas.
- Sin uso de `service_role` en el frontend.

Esta revisión **no sustituye** una prueba contra la base real de Supabase ni una prueba manual completa en GitHub Pages. Los criterios que dependen de datos reales, RLS efectivo, ejecución de RPC, consola del navegador o responsive visual quedan marcados como “requiere validación en entorno real”.

## Matriz de aceptación

| # | Criterio | Estado | Evidencia o condición pendiente |
|---|---|---|---|
| 1 | El proyecto inicia sin errores | Parcial | Los módulos cargan estáticamente y las importaciones son válidas. Requiere abrir la aplicación conectada al Supabase real y revisar consola/red. |
| 2 | El login continúa funcionando | Requiere entorno real | Depende de Supabase Auth, usuarios y políticas activas. |
| 3 | Los módulos actuales conservan su funcionamiento | Parcial | La suite base y la nueva suite pasan. Requiere prueba manual de regresión en navegador. |
| 4 | Los proveedores pueden registrar compras | Implementado localmente | UI, servicio, repositorio y RPC están presentes. Requiere ejecutar la migración y probar con datos reales. |
| 5 | Las compras admiten múltiples productos | Certificado localmente | Validación, consolidación de repetidos y cálculo de totales están cubiertos por pruebas. |
| 6 | La recepción actualiza el inventario una sola vez | Implementado localmente | El modelo y la idempotencia están presentes. Requiere prueba transaccional real en Supabase. |
| 7 | Los pagos descuentan la cuenta correcta | Implementado localmente | UI/RPC y validación de saldo están presentes. Requiere prueba con Nequi y efectivo reales. |
| 8 | Nequi y efectivo muestran saldos separados | Certificado localmente | La vista y el servicio separan ambas cuentas. El valor real depende de la migración y saldos configurados. |
| 9 | El dinero total coincide con las cuentas | Certificado a nivel de lógica | Se suma el saldo de cuentas activas configuradas. Requiere conciliación con datos reales. |
| 10 | Reportes separan ventas, ingresos, compras, pagos, flujo y utilidad | Certificado localmente | Cubierto por pruebas del servicio de reportes. |
| 11 | Compras pendientes aparecen como cuentas por pagar | Implementado localmente | El reporte usa el saldo pendiente. Requiere validar consultas contra el esquema real. |
| 12 | El inventario completo se puede exportar | Implementado localmente | Botón y exportador están presentes. Requiere probar descarga en navegador con todos los productos reales. |
| 13 | El Excel exportado puede reimportarse | Implementado localmente | Parser, vista previa y lote transaccional están presentes. Requiere prueba de ida y vuelta con archivo real. |
| 14 | Productos con stock cero también se exportan | Certificado a nivel de lógica | La exportación no filtra por stock. Requiere confirmar con datos reales. |
| 15 | La importación no duplica productos | Certificado localmente | Se identifica por ID/SKU y se detectan duplicados/conflictos. |
| 16 | No se borran productos ausentes del Excel | Certificado localmente | La importación procesa solo filas presentes y no contiene flujo de borrado por ausencia. |
| 17 | Operaciones sensibles tienen trazabilidad | Implementado localmente | Compras, recepciones, pagos, movimientos, importaciones e idempotencia conservan referencias. Requiere inspección de registros reales. |
| 18 | No existen claves privadas en el frontend | Certificado localmente | La búsqueda y pruebas no detectan `service_role`. |
| 19 | RLS continúa activo | Implementado en SQL | Las migraciones habilitan y fuerzan RLS. Requiere comprobarlo tras ejecutar el consolidado. |
| 20 | El proyecto puede desplegarse en GitHub Pages | Parcial | Sigue siendo una aplicación estática y no se agregó backend local. Requiere despliegue de prueba. |
| 21 | No aparecen errores rojos en consola | Requiere entorno real | Solo puede certificarse abriendo la aplicación y recorriendo los flujos. |
| 22 | No existen solicitudes fallidas sin manejar | Parcial | Existe manejo de errores y recuperación visual. Requiere revisar Network durante pruebas reales. |
| 23 | La interfaz funciona en computador y móvil | Parcial | CSS responsive, controles táctiles y accesibilidad están presentes. Requiere prueba visual en dispositivos/navegadores. |
| 24 | Los datos financieros no se duplican al recargar o guardar nuevamente | Implementado localmente | Claves idempotentes, restricciones únicas y envolturas RPC están presentes. Requiere repetir operaciones en Supabase real. |

## Resultado de la Fase 25

- **Certificados localmente:** 9 criterios.
- **Implementados, pendientes de validación real:** 10 criterios.
- **Parciales:** 5 criterios.
- **No implementados:** 0 criterios detectados en la revisión estática.

La Fase 25 queda cerrada como **revisión técnica local**, pero la aceptación de producción no debe declararse hasta ejecutar la migración consolidada y completar una prueba manual de extremo a extremo contra el Supabase real.

## Prueba obligatoria antes de publicar

1. Crear respaldo de la base.
2. Ejecutar `sql/supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql`.
3. Ejecutar `select public.validate_lihen_schema_coherence();` y exigir `ok = true`.
4. Configurar saldos reales de Nequi y efectivo.
5. Crear, confirmar y recibir una compra de prueba controlada.
6. Registrar un pago parcial y verificar un solo descuento.
7. Registrar una venta rápida y verificar un solo ingreso.
8. Anular la venta y verificar inventario y movimiento inverso.
9. Exportar el inventario, modificar una fila y reimportarlo.
10. Revisar consola, Network, reportes y responsive antes de publicar.
