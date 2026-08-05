# Investigación estática — LIHEN Admin

## Confirmado en el ZIP

1. `editorItems` es la fuente de verdad de la edición.
2. El botón Eliminar ejecuta `editorItems.splice(index, 1)`.
3. `payload` se construye después de eliminar, directamente desde `editorItems`.
4. La RPC llamada es `update_order_atomic` con nueve parámetros nombrados.
5. El frontend comprueba las líneas guardadas inmediatamente después de la RPC.
6. El archivo SQL 008 libera reservas, elimina todas las líneas antiguas y reconstruye `order_items` exclusivamente desde `p_items`.
7. En las migraciones incluidas no existe ningún trigger que restaure líneas.
8. El cliente de Supabase no implementa caché de consultas; `fetchFullOrder()` vuelve a consultar `order_items`.

## No verificable solo con el ZIP

- Qué contenido exacto llegó en un clic real a `payload`.
- La respuesta real de la RPC en el navegador.
- La definición actualmente desplegada en Supabase.
- Si existen sobrecargas antiguas de la función.
- Si hay triggers creados manualmente fuera de las migraciones.
- Si la transacción genera un error o rollback en producción.

## Hipótesis más fuerte

La base de datos desplegada no coincide con el archivo `008_edicion_pedidos_y_whatsapp.sql`, o existe más de una firma de `update_order_atomic`. La segunda posibilidad es un error de la RPC que no se está observando con suficiente detalle en la interfaz.
