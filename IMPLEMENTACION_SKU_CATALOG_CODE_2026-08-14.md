# LIHEN ADMIN — Hotfix SKU sugerido y Código catálogo

## Objetivo

1. Al crear un producto, sugerir automáticamente el siguiente SKU según la línea:
   - Beauty Care -> BC-###
   - Style -> ST-###
2. Mantener el SKU editable para casos excepcionales.
3. Tratar Código catálogo como un identificador público opcional y distinto del SKU interno.
4. Bloquear en la vista previa del Excel códigos catálogo repetidos dentro del archivo o ya usados por otro producto.
5. Convertir Código catálogo vacío a NULL.
6. Mantener `products_catalog_code_key`; no se elimina ni se relaja.

## Diagnóstico confirmado

La base de producción no presenta duplicados persistidos de `catalog_code`. El fallo `products_catalog_code_key` ocurre al intentar procesar un lote que propone repetir un código antes de guardar. Por eso la solución se implementa en la frontera de importación y se añade una defensa PostgreSQL con mensaje legible.

## UX del nuevo producto

Al abrir "Nuevo producto" el sistema carga productos actuales y calcula el máximo por prefijo. Si Beauty Care tiene hasta BC-081 propone BC-082; si Style tiene hasta ST-005 propone ST-006. Al cambiar Línea, la sugerencia cambia mientras la usuaria no haya sustituido manualmente el SKU.

## Importación Excel

Antes de habilitar "Importar inventario" se validan:
- SKU duplicado en el archivo.
- Código catálogo duplicado en el archivo.
- Código catálogo ya asignado a otro producto en Supabase.
- Código catálogo vacío -> NULL.

Cualquier conflicto aparece en la vista previa y bloquea el lote antes de llamar a PostgreSQL.

## Migración 047

Agrega un trigger defensivo que normaliza cadenas vacías a NULL y genera un mensaje amigable si un código ya pertenece a otro producto. No toca la restricción única existente.
