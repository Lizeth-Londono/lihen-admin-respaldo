# Implementación ADMIN → Supabase → WEB — 2026-08-12

## Resultado

La integración se mantiene con dos aplicaciones independientes y el mismo proyecto Supabase. ADMIN administra el write model; WEB consume exclusivamente `catalog_public`.

## Cambios ADMIN

- Nueva migración `sql/045_integracion_admin_web_catalog_contract.sql`.
- Rollback `sql/045_ROLLBACK_integracion_admin_web_catalog_contract.sql`.
- `catalog_public` queda preparado para publicar solo productos:
  - activos;
  - `visible_on_website = true`;
  - con al menos una imagen pública válida.
- Disponibilidad pública derivada del inventario como `Disponible` / `Agotado`, sin cantidades.
- Revocaciones anon sobre tablas administrativas preservadas.
- Nuevo producto queda **oculto por defecto**.
- Nuevo/editar producto permite registrar `main_image_url` pública.
- Tabla ADMIN diferencia `Oculto`, `Inactivo`, `Pendiente foto` y `Publicado`.
- `product-repository` incluye `product_images` para evaluar preparación pública.
- Edición de producto usa `product-repository` para lookup/update principales.
- Se eliminó `data/inventario_inicial.json` del artefacto porque era una filtración administrativa y causaba la regresión de seguridad.

## Cambios WEB

- Se conserva `Catalog Repository → Adapter → Service → Storefront`.
- El Adapter ignora cualquier cantidad exacta que pudiera añadirse accidentalmente al payload público.
- Se añade `PUBLIC_CATALOG_CONTRACT.md`.
- `products.js` continúa como fallback transitorio; no es fuente maestra.

## Pruebas locales

- ADMIN: 149/149.
- ADMIN `npm run check`: OK.
- WEB: 22/22.
- WEB `npm run check`: OK.

## Limitación del entorno de esta ejecución

No fue posible resolver DNS hacia el host Supabase desde el entorno de ejecución, por lo que **no se aplicó la migración 045 ni se realizaron escrituras remotas**. Esto es deliberadamente seguro.

## Paso manual obligatorio en Supabase

1. Abrir SQL Editor en el proyecto Supabase usado por ADMIN/WEB.
2. Confirmar que 044 ya está instalada y que el esquema contiene `products`, `inventory`, `product_variants`, `product_images` y `catalog_public`.
3. Ejecutar `sql/045_integracion_admin_web_catalog_contract.sql`.
4. Ejecutar las consultas de verificación incluidas al final del archivo.
5. Desde la WEB validar:
   - producto activo + visible + foto aparece;
   - visible = No desaparece;
   - sin foto no aparece;
   - stock 0 aparece como Agotado si sigue publicado;
   - cambios de precio se reflejan al recargar;
   - costos/proveedores/cantidades internas no aparecen.
6. Si la verificación falla, ejecutar `sql/045_ROLLBACK_integracion_admin_web_catalog_contract.sql`.

## Cutover

Mantener `CATALOG_SOURCE: 'auto'` y fallback activo durante la validación inicial. Cuando Supabase haya demostrado estabilidad en producción, retirar gradualmente el fallback estático como fuente operativa.
