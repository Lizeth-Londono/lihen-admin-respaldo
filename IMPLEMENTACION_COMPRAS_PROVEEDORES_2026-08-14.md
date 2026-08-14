# Implementación — Compras a proveedor, pagos externos, ST-006 y Reportes

## Qué cambia

### Nueva compra

La compra normal ya no obliga a pasar por borrador:

`Nueva compra → Confirmar compra → Recibir mercancía / Registrar pago`

`Guardar borrador` permanece disponible como acción secundaria.

### Recepción

Recibir mercancía sigue siendo independiente y es el único paso que aumenta `physical_stock`.

### Pago

Registrar pago pregunta el origen:

1. **Cuenta de LIHEN**: selecciona Nequi/Efectivo, muestra saldo actual y saldo posterior, y solo tras confirmar crea el egreso.
2. **Dinero personal / externo**: reduce la deuda con proveedor, pero no modifica Nequi ni efectivo LIHEN.

### Reportes

Se conserva y repara. Ya no consulta `products.product_type` ni aliases de cantidades obsoletos.

### ST-006 / importación Excel

`Activo` se normaliza a `activo`. `Inactivo`/`Oculto` se normaliza a `oculto`. Los valores desconocidos se rechazan en la vista previa antes de PostgreSQL.

## Orden de despliegue

1. Hacer respaldo de Supabase.
2. En SQL Editor ejecutar primero las consultas de diagnóstico comentadas al inicio de `046_compras_proveedor_pago_externo_y_estados.sql`.
3. Confirmar que el estado real de compras usa `cancelada` y revisar los enums listados.
4. Ejecutar `046_compras_proveedor_pago_externo_y_estados.sql`.
5. Ejecutar las consultas de verificación al final del archivo.
6. Desplegar el ZIP corregido del ADMIN.
7. Recargar con Ctrl+F5.

## Smoke test obligatorio

### Caso A — compra sin pago

- Crear compra por $11.900.
- Pulsar Confirmar compra.
- Verificar que Nequi y Efectivo no cambian.
- Deben aparecer `Recibir mercancía` y `Registrar pago`.

### Caso B — recepción

- Recibir las unidades.
- Verificar que solo aumenta inventario físico.
- Caja permanece sin cambios.

### Caso C — pago Nequi

- Registrar pago.
- Origen: Cuenta de LIHEN.
- Elegir Nequi.
- Confirmar saldo posterior.
- Verificar un único egreso y disminución exacta de Nequi.

### Caso D — pago personal

- Nueva compra.
- Registrar pago.
- Origen: Dinero personal / externo.
- Confirmar.
- Verificar que `balance_due` baja y que Nequi/Efectivo no cambian.
- Verificar `supplier_payments.payment_source='external'` y ambos vínculos financieros nulos.

### Caso E — ST-006

- Importar `Inventario_Actual_LIHEN_2026-08-14.xlsx`.
- La vista previa debe mostrar ST-006 como producto nuevo, `status=activo`, sin error de enum.
- Confirmar importación.
- Verificar que ST-006 exista y tenga inventario inicial 0.

### Caso F — Reportes

- Abrir Reportes.
- Debe cargar sin `column products.product_type does not exist`.

## Rollback

`046_ROLLBACK_compras_proveedor_pago_externo_y_estados.sql` bloquea el rollback si ya existen pagos externos, porque convertirlos automáticamente en salidas de caja sería contablemente incorrecto.

## Pruebas locales del release

- `npm run check`: OK.
- `npm test`: 161/161 OK.
