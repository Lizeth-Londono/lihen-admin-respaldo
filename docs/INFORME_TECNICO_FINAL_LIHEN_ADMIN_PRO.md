# Informe técnico final — LIHEN_ADMIN_PRO

## 1. Objetivo

Ampliar el sistema administrativo de LIHEN.CO para gestionar compras a proveedores, recepción de mercancía, pagos, cuentas financieras, movimientos de dinero, reportes, exportación e importación segura del inventario, manteniendo JavaScript ES Modules, Supabase y compatibilidad con GitHub Pages.

## 2. Arquitectura resultante

La aplicación conserva una arquitectura frontend estática con módulos ES, separando:

- Vistas e interacción.
- Servicios de reglas de negocio.
- Repositorios de acceso a Supabase.
- Funciones RPC PostgreSQL para operaciones transaccionales.
- Pruebas unitarias y comprobación de módulos.

Las operaciones críticas usan idempotencia y funciones atómicas en la base de datos.

## 3. Funcionalidades incorporadas

### Proveedores y compras

- Compras en borrador.
- Múltiples productos por compra.
- Totales con descuento, impuestos y flete.
- Confirmación de compra.
- Recepciones parciales o completas.
- Historial y saldo pendiente.

### Inventario

- Entrada por recepción de mercancía.
- Control de stock físico, reservado y pendiente.
- Movimientos trazables.
- Importación transaccional por lote.
- Identificación por ID interno y SKU.
- Vista previa y archivo de filas rechazadas.
- Exportación del inventario, incluidos productos con stock cero.

### Caja y cuentas

- Nequi y efectivo físico.
- Saldos iniciales.
- Ingresos, egresos y ajustes.
- Transferencias entre cuentas.
- Reversiones con trazabilidad.
- Protección contra saldo insuficiente.

### Pagos a proveedores

- Pagos parciales o completos.
- Descuento de la cuenta seleccionada.
- Relación con movimiento financiero.
- Prevención de sobrepagos y duplicados.

### Ventas y pedidos

- Venta rápida vinculada con la cuenta receptora.
- Pago y entrega de pedidos vinculado con caja.
- Anulación financiera e inventario coordinados.

### Reportes

- Ventas registradas.
- Ingresos cobrados.
- Compras.
- Pagos a proveedores.
- Flujo neto.
- Dinero disponible.
- Nequi y efectivo separados.
- Cuentas por pagar.
- Utilidad bruta estimada.
- Alertas financieras.

## 4. Modelo de datos

Se reutiliza `supplier_requests` como encabezado de compra para evitar dos fuentes de verdad. Se incorporan o amplían entidades para:

- Detalles de compra.
- Recepciones y detalles de recepción.
- Cuentas financieras.
- Movimientos financieros.
- Pagos a proveedores.
- Historial de costos.
- Historial de saldos iniciales.
- Lotes y filas de importación.
- Ejecuciones idempotentes.

## 5. Seguridad

- RLS habilitado y reforzado en tablas nuevas.
- Escritura directa restringida para operaciones críticas.
- RPC limitadas a usuarios autenticados y autorizados.
- Sin `service_role` en el navegador.
- Validaciones también en PostgreSQL.
- Restricciones, índices y llaves foráneas.

## 6. Idempotencia

Se evita duplicar:

- Pedidos.
- Ventas rápidas.
- Anulaciones.
- Cierres directos.
- Importaciones.
- Recepciones.
- Pagos.
- Movimientos financieros.

## 7. Experiencia de usuario

- Confirmaciones antes de operaciones delicadas.
- Botones deshabilitados durante procesos.
- Estados de carga, éxito, advertencia y error.
- Modales accesibles y administración de foco.
- Diseño responsive conservando la identidad visual de LIHEN.CO.

## 8. Archivos SQL principales

- `022_importacion_inventario_transaccional_fase_18.sql`
- `023_seguridad_supabase_fase_19.sql`
- `024_modelo_datos_consolidado_fase_20.sql`
- `025_idempotencia_operaciones_fase_21.sql`
- `026_consolidacion_funcional_fases_2_15.sql`
- `027_transferencias_reversiones_fase_24.sql`
- `028_integracion_ventas_pedidos_caja_fase_24.sql`
- `029_coherencia_migraciones_fase_24.sql`
- `supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql`

## 9. Pruebas locales

Resultado ejecutado el 6 de agosto de 2026:

- 72 pruebas aprobadas.
- 0 fallos.
- 48 módulos JavaScript verificados.
- Rutas locales e importaciones correctas.

## 10. Riesgos y limitaciones

- El esquema histórico `001_core_schema.sql` no está incluido en el proyecto, por lo que la comprobación definitiva depende del Supabase real.
- Las pruebas locales no reemplazan una prueba de integración contra la base activa.
- La utilidad bruta es estimada mientras no exista costo histórico exacto por unidad vendida.
- La publicación final debe realizarse primero en un entorno de prueba.

## 11. Condición de entrega final

El ZIP final debe generarse después de:

1. Ejecutar la migración consolidada en Supabase de prueba o respaldo.
2. Obtener `ok: true` en `validate_lihen_schema_coherence()`.
3. Completar las pruebas controladas de negocio.
4. Revisar consola y red.
5. Confirmar funcionamiento móvil y en GitHub Pages.
