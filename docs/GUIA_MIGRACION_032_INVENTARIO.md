# Guía de instalación — Migración 032

1. Realice una copia de seguridad de la base de datos.
2. En Supabase, abra SQL Editor.
3. Copie todo el contenido de `sql/032_compatibilidad_plantilla_inventario_2026_08_07.sql`.
4. Ejecútelo una sola vez.
5. El resultado esperado es `Success. No rows returned`.
6. Suba el proyecto actualizado a GitHub y espere la publicación de GitHub Pages.
7. Actualice la aplicación con Ctrl + F5.
8. Pruebe primero la importación sin cambios y revise la vista previa antes de confirmar.

No vuelva a ejecutar las migraciones 022 a 031 si ya fueron instaladas.
