# DIAGNÓSTICO_COMPRAS_PROVEEDORES_LIHEN — 2026-08-14

## Resultado ejecutivo

**GO** para corrección incremental. No se requiere reescribir el ADMIN.

La arquitectura actual ya separa compra, recepción, inventario, pago y caja mediante UI → Repository → RPC → PostgreSQL. Los problemas observados provienen de contratos desalineados entre capas y de una UX que deja la compra normal en borrador por defecto.

## 1. Error `supplier_request_status: "anulada"`

### Causa exacta localizada en el código

La versión posterior de `register_supplier_payment_atomic` compara el estado de una compra con:

```sql
p.status in ('cancelada','anulada')
```

Si `supplier_requests.status` es el enum `public.supplier_request_status` y ese enum no contiene `anulada`, PostgreSQL intenta convertir el literal a ese enum al ejecutar la función y produce exactamente:

`invalid input value for enum public.supplier_request_status: "anulada"`

La captura de producción confirma que `anulada` no es aceptado por el enum real.

### Corrección

La migración 046 crea `register_supplier_payment_v2_atomic` y compara `v_purchase.status::text = 'cancelada'`, sin convertir `anulada` al enum. Además reemplaza la firma antigua con un wrapper compatible que delega a V2.

## 2. Flujo de compra actual

Actualmente `js/supplier-purchases.js` presenta como acción principal **Guardar borrador**. Solo después de abrir la compra nuevamente se ofrece **Confirmar compra**. Los botones **Recibir mercancía** y **Registrar pago** se ocultan mientras el estado sea `borrador`.

### Corrección aplicada

Para compra actual se muestran:

- `Guardar borrador` como acción secundaria.
- `Confirmar compra` como acción principal.

Cuando se confirma desde el formulario, el frontend crea la compra y ejecuta la confirmación inmediatamente. Confirmar no aumenta stock físico ni descuenta caja.

## 3. Compra, recepción y pago siguen separados

Se conserva la separación:

- **Confirmar compra:** registra compromiso y deja la compra operativa. Puede aumentar `pending_stock` según la lógica existente, pero no `physical_stock`.
- **Recibir mercancía:** es el único flujo que incrementa el stock físico.
- **Registrar pago:** es el único flujo que puede afectar caja, y solo cuando la usuaria elige una cuenta LIHEN.

## 4. Desalineación del payload de recepción

La UI producía objetos con:

- `quantity_received`
- `final_unit_cost`

pero `receive_supplier_purchase_v2_atomic` espera:

- `quantity`
- `unit_cost`

El Repository ahora adapta explícitamente el contrato antes de llamar la RPC.

## 5. Pagos personales / externos

El modelo previo obligaba a cada pago a tener `financial_account_id` y generar `financial_movement_id`, por lo que todo pago necesariamente afectaba Nequi/Efectivo.

### Corrección aplicada

Migración 046:

- agrega `supplier_payments.payment_source` (`lihen` | `external`);
- permite `financial_account_id` y `financial_movement_id` nulos para pagos externos;
- crea RPC V2:
  - `lihen` → exige cuenta, valida saldo, crea egreso y descuenta caja;
  - `external` → registra pago/deuda sin movimiento de caja LIHEN.

La UI pide explícitamente **Origen del dinero** y muestra confirmación de impacto.

## 6. ST-006 del Excel

Se inspeccionó `Inventario_Actual_LIHEN_2026-08-14.xlsx`.

Fila ST-006:

- SKU: `ST-006`
- Línea: `Style`
- Categoría: `Online`
- Subcategoría: `Perfunme`
- Producto: `Fragancia LIHEN`
- Proveedor: `KJ Parfums`
- Costo: 2600
- Precio: 3000
- Stock: 0
- Visible: `No`
- Estado: `Activo`

El parser ya normalizaba `Activo` a `activo`. Se endureció el contrato para que estados de interfaz/Excel se conviertan siempre antes de llegar a PostgreSQL. También se corrigió la inconsistencia histórica `Inactivo` vs `oculto`: `Inactivo`, `Oculto` e `inactive` se normalizan al valor canónico `oculto` usado por la UI del producto.

Se añadió prueba específica con la fila ST-006: el plan la clasifica como **create**, sin errores, y el payload enviado a la RPC contiene `status: 'activo'`.

## 7. Módulo Reportes

### Decisión: **KEEP + FIX**

No se elimina porque aporta funciones útiles que no están concentradas en Caja:

- ingresos por pedidos y ventas rápidas;
- costo de ventas y utilidad bruta;
- ventas mensuales;
- productos vendidos;
- compras y cuentas por pagar;
- alertas financieras;
- saldos de caja.

### Errores encontrados

`report-repository.js` consultaba:

- `products.product_type` — columna inexistente;
- `supplier_request_items.requested_quantity` — nombre incompatible con el modelo actual;
- `supplier_request_items.received_quantity` — nombre incompatible con el modelo actual.

Se corrigió a:

- `category, subcategory`
- `quantity_requested`
- `quantity_received`

También se incluye `payment_source` en pagos.

## 8. Estados

No se modifica el enum real a ciegas. La migración 046 incluye consulta de diagnóstico para listar los valores reales de `supplier_request_status` y `product_status` antes de instalar.

Decisión canónica utilizada por el nuevo flujo:

- compra bloqueada: `cancelada`;
- borrador: `borrador`;
- confirmada: `confirmada`;
- recepción: `pendiente` / `parcial` / `completa`;
- pago: `pendiente` / `parcial` / `pagada`.

`anulada` no se utiliza como estado de `supplier_requests` en el código nuevo.

## 9. Archivos modificados

- `js/supplier-purchases.js`
- `js/repositories/supplier-purchase-repository.js`
- `js/repositories/report-repository.js`
- `js/services/report-service.js`
- `js/services/financial-alert-service.js`
- `js/services/inventory-workbook-service.js`
- `js/services/inventory-import-service.js`
- `js/inventory-export.js`
- `sql/046_compras_proveedor_pago_externo_y_estados.sql`
- `sql/046_ROLLBACK_compras_proveedor_pago_externo_y_estados.sql`
- `tests/supplier-purchase-flow-2026-08-14.test.js`

## 10. Riesgo

- Código frontend: **LOW**.
- Migración SQL: **MEDIUM** hasta validarla en Supabase real.
- Pérdida de datos: **LOW**; 046 no borra compras, pagos, inventario ni movimientos.
- Caja: **LOW** si se respeta el orden de despliegue y las pruebas controladas.

## 11. Pruebas locales

- `npm run check`: OK — 52 módulos.
- `npm test`: **161/161 pass, 0 fail**.
- Nuevas pruebas específicas: 12/12 pass.

## 12. Limitación honesta

El ZIP no contiene una definición inicial completa del enum `supplier_request_status`; por eso la lista completa de valores del enum real debe confirmarse en Supabase con el diagnóstico incluido en 046. La corrección no depende de inventar esos valores: evita el literal inválido y no altera el enum.
