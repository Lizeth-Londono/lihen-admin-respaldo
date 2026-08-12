# Fase 18 — Operación y mantenimiento post-cutover

Esta fase no introduce cambios de esquema. Define cómo operar LIHEN.CO una vez activada la integración ADMIN → Supabase → WEB.

## Rutina diaria

1. Revisar errores visibles en ADMIN y WEB.
2. Verificar productos con stock 0 y productos ocultos.
3. Revisar movimientos recientes cuando haya diferencias de inventario.
4. No editar `products.js` como fuente maestra.
5. No modificar `reserved_stock`, `available_stock` ni `pending_stock` desde Excel.

## Rutina semanal

- Ejecutar `sql/MONITOREO_OPERATIVO_FASE_18.sql`.
- Revisar SKU duplicados y códigos de catálogo duplicados.
- Revisar productos visibles con precio o datos incompletos.
- Confirmar que `catalog_public` no exponga campos privados.
- Revisar lotes de importación y movimientos recientes.

## Cambios de catálogo

El flujo esperado es:

```text
ADMIN / Excel
→ validación
→ Supabase
→ catalog_public
→ WEB
```

No se requiere redeploy por cambios de precio, stock, descripción, estado o visibilidad.

## Incidente de WEB

Si Supabase o el contrato público presenta problemas:

```text
CATALOG_SOURCE = static
```

Mantener el catálogo estático únicamente como contingencia.

## Incidente de inventario

1. Detener importaciones nuevas.
2. Ejecutar el monitor de Fase 18.
3. Identificar el SKU y sus movimientos.
4. No corregir directamente la bitácora.
5. Ajustar inventario mediante la operación administrativa/RPC autorizada.
6. Conservar evidencia del antes y después.

## Retiro de fallback

No retirar `products.js` hasta tener estabilidad real comprobada. Al retirarlo, conservar un backup etiquetado del último fallback funcional.
