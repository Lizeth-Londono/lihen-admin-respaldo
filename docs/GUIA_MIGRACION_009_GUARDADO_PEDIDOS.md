# Corrección 009 — guardado real al editar pedidos

## Causa que se evita

El frontend ya retiraba el producto de la lista local, pero la RPC activa en Supabase podía no coincidir con la versión del repositorio o podía existir una sobrecarga anterior. La corrección crea una función nueva, `update_order_atomic_v2`, para no depender de ninguna versión previa con el mismo nombre.

## Paso obligatorio

1. Abre `sql/009_corregir_guardado_edicion_pedidos.sql`.
2. Copia todo el contenido.
3. Ejecuta el archivo una sola vez en **Supabase → SQL Editor**.
4. Debe aparecer `Success. No rows returned`.
5. Sube los archivos a GitHub y espera el despliegue.

## Qué valida el frontend

Al guardar, la aplicación registra en la consola el payload y la respuesta RPC. Después consulta directamente `order_items` y compara producto, variante, cantidad y precio. El modal solo se cierra si lo almacenado coincide con la edición.

## Prueba clave

1. Abre un pedido con varios productos.
2. Elimina uno.
3. Pulsa **Guardar cambios**.
4. Cierra y recarga la página.
5. Abre nuevamente el pedido.
6. El producto eliminado no debe aparecer en el pedido, resumen, WhatsApp ni comprobante.

Si falla, abre las herramientas del navegador, entra a **Console** y copia el bloque que comienza con `[LIHEN] Guardar edición`.
