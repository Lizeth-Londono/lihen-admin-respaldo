# Lista de cambios — LIHEN_ADMIN_PRO

## Frontend principal

| Archivo | Cambio | Funcionalidad relacionada |
|---|---|---|
| `js/main.js` | Nuevas acciones, eventos y navegación | Compras, caja, importación y exportación |
| `js/views.js` | Nuevas vistas, tarjetas y acciones | Proveedores, caja y reportes |
| `js/store.js` | Estado adicional | Cuentas, movimientos y filtros |
| `css/app.css` | Estados, modales, responsive y accesibilidad | Experiencia de usuario |
| `js/ui.js` | Foco, estados de carga y accesibilidad | Operaciones críticas |
| `js/errors.js` | Recuperación y mensajes de error | Manejo de fallos |

## Compras a proveedores

| Archivo | Cambio | Funcionalidad relacionada |
|---|---|---|
| `js/supplier-purchases.js` | Formularios e historial | Compra, confirmación, recepción y pago |
| `js/services/supplier-purchase-service.js` | Reglas y cálculos | Validación y totales |
| `js/repositories/supplier-purchase-repository.js` | RPC y consultas | Persistencia de compras |

## Caja y movimientos

| Archivo | Cambio | Funcionalidad relacionada |
|---|---|---|
| `js/financial-accounts.js` | Interfaz de cuentas y movimientos | Nequi, efectivo, transferencias y reversiones |
| `js/services/financial-account-service.js` | Validaciones y resúmenes | Saldos y movimientos |
| `js/repositories/financial-account-repository.js` | Consultas y RPC | Persistencia financiera |
| `js/services/financial-alert-service.js` | Reglas de alertas | Vencimientos y diferencias |

## Inventario y Excel

| Archivo | Cambio | Funcionalidad relacionada |
|---|---|---|
| `js/inventory-export.js` | Generación de Excel | Exportación completa |
| `js/imports.js` | Vista previa y ejecución por lote | Importación segura |
| `js/services/inventory-import-service.js` | Identificación, validación y plan | ID/SKU y errores |
| `js/repositories/inventory-import-repository.js` | RPC transaccional | Aplicación atómica |

## Ventas, pedidos y reportes

| Archivo | Cambio | Funcionalidad relacionada |
|---|---|---|
| `js/sales.js` | Selección de cuenta | Venta rápida y anulación financiera |
| `js/order-workflow.js` | Cuenta receptora | Pago y entrega |
| `js/repositories/quick-sale-repository.js` | RPC idempotente | Ventas rápidas |
| `js/repositories/order-repository.js` | RPC idempotente | Pedidos |
| `js/repositories/report-repository.js` | Fuentes financieras | Reportes consolidados |
| `js/services/report-service.js` | Cálculos financieros | Flujo, saldos y utilidad |

## Servicios transversales

| Archivo | Cambio | Funcionalidad relacionada |
|---|---|---|
| `js/services/confirmation-service.js` | Confirmaciones accesibles | Operaciones delicadas |
| `js/services/operation-key-service.js` | Claves únicas | Idempotencia |

## Base de datos

| Archivo | Cambio | Funcionalidad relacionada |
|---|---|---|
| `sql/022_...sql` | Importación transaccional | Inventario |
| `sql/023_...sql` | RLS y permisos | Seguridad |
| `sql/024_...sql` | Modelo consolidado | Compras y finanzas |
| `sql/025_...sql` | Registro idempotente | Operaciones críticas |
| `sql/026_...sql` | Consolidación funcional | Compras, caja y pagos |
| `sql/027_...sql` | Transferencias y reversión | Caja |
| `sql/028_...sql` | Ventas y pedidos con caja | Ingresos |
| `sql/029_...sql` | Compatibilidad final | Coherencia de esquema |
| `sql/supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql` | Instalación única | Entrega final |

## Pruebas

Se agregaron pruebas para importación, seguridad, modelo, idempotencia, experiencia de usuario, confirmaciones, compras, caja, reportes, ventas, pedidos, coherencia SQL y aceptación.
