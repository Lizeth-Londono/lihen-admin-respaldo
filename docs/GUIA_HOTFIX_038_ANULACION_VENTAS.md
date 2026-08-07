# LIHEN Admin — Hotfix 038: anulación de ventas antiguas

## Causa raíz

La interfaz llama a la RPC `cancel_quick_sale_financial_atomic_idempotent`. La versión anterior abortaba inmediatamente cuando `quick_sales.financial_account_id` o `quick_sales.financial_movement_id` estaban vacíos. Esto dejó imposibles de anular ventas creadas antes de la integración financiera o registros cuyo vínculo financiero quedó incompleto.

El mensaje visible era:

> La venta no tiene un movimiento financiero asociado

No era un problema del modal ni del botón. El bloqueo estaba en la función PostgreSQL/Supabase.

## Qué cambia

`sql/038_hotfix_anulacion_ventas_legacy.sql` reemplaza únicamente la RPC de anulación financiera y conserva la arquitectura actual.

La nueva lógica:

1. Bloquea la venta con `FOR UPDATE`.
2. Si ya está anulada, termina sin tocar stock ni caja otra vez.
3. Si la venta tiene un movimiento financiero enlazado, lo usa.
4. Si el enlace está incompleto, busca un movimiento financiero real por `source_type='quick_sale'` y `source_id` y repara el vínculo.
5. Si realmente nunca existió movimiento financiero, trata la venta como histórica/legacy: repone inventario y la marca anulada sin inventar un movimiento de caja.
6. Si existe movimiento financiero activo, crea una sola reversión y marca el movimiento original como reversado.
7. Todo ocurre dentro de una única transacción PostgreSQL. Si una operación falla, los cambios de esa llamada se revierten.

## Por qué no se eliminan ventas

No se recomienda ejecutar `DELETE FROM quick_sales` ni vaciar las ventas. Las ventas son parte del historial de inventario, caja, reportes y auditoría. Una venta anulada debe seguir existiendo con `status='anulada'`, `cancelled_at`, `cancelled_by` y `cancellation_reason`.

## Instalación en la base actual

1. Abre Supabase.
2. Ve a **SQL Editor**.
3. Abre el archivo `sql/038_hotfix_anulacion_ventas_legacy.sql` de este ZIP.
4. Copia su contenido completo.
5. Ejecuta el script una sola vez.
6. Revisa las consultas de diagnóstico que aparecen al final.
7. Regresa a LIHEN Admin, actualiza con `Ctrl + F5` y prueba una venta antigua.

No necesitas borrar ventas ni volver a ejecutar las migraciones 001–037.

## Resultado esperado

- Venta con movimiento financiero: repone stock, registra egreso de reversión, marca el ingreso original como reversado y deja la venta como anulada.
- Venta sin movimiento financiero real: repone stock y deja la venta como anulada; no crea un movimiento financiero ficticio.
- Segundo intento sobre la misma venta: no vuelve a sumar stock ni vuelve a descontar caja.

## Nota sobre saldo insuficiente

Para una venta que sí tuvo ingreso financiero, se conserva la validación de saldo disponible. Si la cuenta ya no tiene suficiente saldo, el sistema no hará una anulación parcial. Esto protege la coherencia entre caja e inventario. Primero deberá conciliarse el saldo de esa cuenta.
