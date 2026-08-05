# Integración del catálogo público

El archivo `catalogo-supabase.js` consulta la vista `catalog_public`, que solo expone datos comerciales autorizados.

Para una migración segura del catálogo actual:

1. Conservar temporalmente `js/data/products.js` como respaldo.
2. Importar `loadPublicProducts` en el punto de entrada del catálogo.
3. Cargar los productos antes de renderizar la tienda.
4. Si Supabase falla, usar el arreglo estático como respaldo durante la transición.
5. Validar imágenes, filtros, búsqueda, selección y WhatsApp antes de retirar el CSV.

No se exponen costos, stock interno, clientes, proveedores ni pedidos.
