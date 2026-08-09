# Fase 10 — Validación final del scroll de modales

- Se aplicó un bloque CSS final y explícito para que `.modal-body` sea el único scroll vertical principal de los formularios altos.
- En Venta rápida se eliminó el scroll interno de `.sale-items-list` mediante una regla final específica.
- Las acciones de Venta rápida quedan `sticky` con `bottom: 0`.
- El editor de pedidos evita un segundo scroll vertical dentro del modal.
- `index.html` usa cache-busting `20260808-scroll-fix-final-v1` para CSS y JS.
- Se añadió una prueba de navegador real con Chromium que verifica `scrollHeight > clientHeight`, desplazamiento hacia abajo y arriba y acceso al botón Guardar.
- No se modificó lógica de Supabase ni reglas de inventario/caja/ventas.
