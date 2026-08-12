# Fase 13 — Release Candidate local y aceptación técnica

**Fecha:** 2026-08-11  
**Estado:** RELEASE CANDIDATE LOCAL  
**Producción Supabase:** NO modificada desde esta sesión.  
**ZIP final:** NO generado / NO entregado.

## 1. Propósito

Esta fase consolida y verifica localmente los cambios acumulados de la integración:

```text
Excel
  ↓
LIHEN_ADMIN_PRO
  ↓
Supabase
  ↓
catalog_public
  ↓
LIHEN_WEB_RENACER
```

No agrega una nueva arquitectura. Su función es comprobar que el conjunto acumulado de Fases 5–12 forma un release coherente antes del cutover real.

## 2. Resultados de aceptación local

### ADMIN

```text
npm test
→ 134 pruebas aprobadas
→ 0 fallos

npm run check
→ 52 módulos JavaScript/rutas/importaciones verificados
```

### WEB

```text
Pruebas Fases 10–12
→ 15 pruebas aprobadas
→ 0 fallos

npm run check:js
→ sin errores de sintaxis

npm run check
→ 100 archivos JavaScript
→ 12 HTML
→ 12 migraciones SQL del proyecto WEB
→ 298 referencias de imágenes revisadas

npm run products:check
→ 177 productos
→ 94 visibles
→ 83 ocultos
→ catálogo fallback válido

npm run products:check:internal
→ 177 registros
→ 85 con SKU
→ 85 con ID interno
→ catálogo interno válido
```

## 3. Escaneo de secretos

Se revisaron archivos activos buscando patrones de credenciales privilegiadas. No se detectó una clave privada real incrustada en el código de la integración. Las apariciones textuales de nombres de secretos encontradas están en documentación, pruebas o validadores que explican que esas claves están prohibidas.

La configuración entregable de la WEB conserva placeholders para `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`.

## 4. Migraciones y orden de aplicación

```text
039_catalog_public_inventario_dinamico.sql
040_creacion_producto_atomica.sql
041_integridad_inventario_fase_7.sql
042_movimientos_inventario_fase_8.sql
043_importacion_inventario_trazabilidad_fase_9.sql
044_seguridad_catalogo_publico_fase_12.sql
```

Aplicar únicamente después de backup y sobre una base que ya tenga el historial previo esperado.

## 5. Orden de rollback

```text
044_ROLLBACK_seguridad_catalogo_publico_fase_12.sql
043_ROLLBACK_importacion_inventario_trazabilidad_fase_9.sql
042_ROLLBACK_movimientos_inventario_fase_8.sql
041_ROLLBACK_integridad_inventario_fase_7.sql
040_ROLLBACK_creacion_producto_atomica.sql
039_ROLLBACK_catalog_public_inventario_dinamico.sql
```

## 6. Invariantes verificadas

- Supabase permanece como fuente operativa objetivo.
- Excel no se convierte en segunda base de producción.
- `products.js` queda como fallback temporal.
- La WEB consulta catálogo a través de `CatalogRepository`.
- `CatalogRepository` consulta `catalog_public`, no tablas administrativas.
- Precio público proviene de `sale_price`.
- Disponibilidad pública se deriva del inventario.
- Producto agotado puede seguir publicado.
- Producto oculto/inactivo no debe exponerse.
- Costos y proveedor no forman parte del contrato público.
- La importación Excel sigue siendo transaccional.
- El preview obsoleto no debe pisar silenciosamente cambios concurrentes.
- Los movimientos quedan protegidos contra escritura directa del navegador.
- La WEB dispone de rollback funcional a fuente estática.

## 7. Riesgos que no pueden cerrarse localmente

Todavía falta verificar en Supabase real/preproducción:

1. ejecución real de migraciones 039–044;
2. grants/RLS reales;
3. `SELECT catalog_public` con Publishable Key;
4. bloqueo de lectura directa a `inventory/products` desde la WEB;
5. imágenes y variantes reales;
6. actualización ADMIN → Supabase → WEB sin deploy;
7. concurrencia de inventario con operaciones reales.

## 8. Gate de publicación

No pasar aún a modo estricto `CATALOG_SOURCE = supabase` hasta completar preproducción.

Configuración inicial recomendada:

```text
CATALOG_SOURCE = auto
CATALOG_FALLBACK_ON_EMPTY = true
CATALOG_FALLBACK_ON_ERROR = true
```

## 9. Manifest SHA-256

Se generó `RELEASE_INTEGRACION_ADMIN_WEB_SHA256.txt` en ambos proyectos para detectar cambios accidentales antes del empaquetado final.

## 10. Decisión

**Release Candidate local: APROBADO.**

Esto certifica las pruebas y contratos locales; no afirma que Supabase de producción esté migrado ni que GitHub Pages esté actualizado.

## 11. Siguiente fase

Preparar el cutover/preproducción con:

1. backup;
2. diagnósticos pre-SQL;
3. verificación post-SQL;
4. Publishable Key final;
5. prueba controlada con 1–3 SKU;
6. ADMIN → Supabase → WEB;
7. prueba de rollback;
8. después, empaquetado final.

No se genera ZIP en esta fase.
