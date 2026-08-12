# Fase 15 — Cierre del release final LIHEN.CO

**Fecha:** 2026-08-11  
**Estado:** CIERRE LOCAL COMPLETADO  
**ZIP final:** todavía no generado en esta fase.

## 1. Resultado

El release acumulado de la integración ADMIN → Supabase → WEB queda cerrado localmente y listo para empaquetado final.

## 2. Pruebas finales reejecutadas

### LIHEN_ADMIN_PRO
- `npm test`: 134 aprobadas, 0 fallos.
- `npm run check`: 52 módulos/rutas/importaciones verificados.

### LIHEN_WEB_RENACER
- pruebas Fases 10–12: 15 aprobadas, 0 fallos.
- `npm run check:js`: correcto.
- `npm run check`: 100 JS, 12 HTML, 12 migraciones SQL del proyecto WEB, 298 referencias de imágenes.
- `npm run products:check`: catálogo fallback válido.
- `npm run products:check:internal`: catálogo interno válido.

## 3. Manifest SHA-256

`RELEASE_INTEGRACION_ADMIN_WEB_SHA256.txt` fue verificado después de las pruebas finales.

Resultado:
- ADMIN: 21 archivos del release verificados, 0 diferencias.
- WEB: 12 archivos del release verificados, 0 diferencias.

## 4. Migraciones del release

Aplicación:
1. `039_catalog_public_inventario_dinamico.sql`
2. `040_creacion_producto_atomica.sql`
3. `041_integridad_inventario_fase_7.sql`
4. `042_movimientos_inventario_fase_8.sql`
5. `043_importacion_inventario_trazabilidad_fase_9.sql`
6. `044_seguridad_catalogo_publico_fase_12.sql`

Rollback: orden inverso.

## 5. Estado funcional

Queda implementado localmente:
- Supabase como fuente maestra objetivo.
- Excel como importación/exportación, no como segunda base.
- creación atómica de productos.
- integridad de inventario.
- movimientos append-only.
- importación Excel atómica, idempotente y con concurrencia optimista.
- `catalog_public` con disponibilidad derivada del inventario.
- frontera pública sin costos ni proveedores.
- Repository + Adapter + Service en la WEB.
- fallback temporal a `products.js`.
- configuración `auto | supabase | static`.
- rollback SQL y rollback funcional del frontend.
- scripts PRE/POST cutover.

## 6. Riesgos que siguen dependiendo del entorno real

No se considera completado en producción hasta ejecutar:
- backup real de Supabase;
- migraciones 039–044;
- verificación PRE/POST;
- prueba con Publishable Key real;
- prueba ADMIN → Supabase → WEB con 1–3 SKU;
- verificación de GitHub Pages real.

## 7. Gate final antes de producción

Primera activación:

```text
CATALOG_SOURCE = auto
CATALOG_FALLBACK_ON_EMPTY = true
CATALOG_FALLBACK_ON_ERROR = true
```

Solo después de validar la base real:

```text
CATALOG_SOURCE = supabase
```

## 8. Conclusión

**Cierre local del release: APROBADO.**

La siguiente acción es empaquetar los dos proyectos finales sin modificar el contenido aprobado y generar el inventario/checksum de los ZIP resultantes.
