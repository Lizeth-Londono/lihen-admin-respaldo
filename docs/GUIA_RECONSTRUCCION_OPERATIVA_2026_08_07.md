# Guía de aplicación — Reconstrucción operativa LIHEN

No subas primero el frontend nuevo. Aplica el SQL en este orden para evitar que el frontend consulte columnas que aún no existen.

## 1. Respaldo
En Supabase → SQL Editor, abre y ejecuta completo:

`sql/036_respaldo_pre_reconstruccion.sql`

Confirma que el resultado final muestre filas para products, inventory, orders, quick_sales, financial_accounts y financial_movements.

## 2. Instalar la migración 034
Ejecuta completo:

`sql/034_reconstruccion_operativa_controlada.sql`

Este paso todavía NO devuelve stock. Solo instala columnas, funciones, históricos y la corrección del cierre directo.

## 3. Previsualizar la restauración
Abre:

`sql/035_restaurar_stock_transacciones_existentes.sql`

Ejecuta únicamente PASO A y PASO B.

Revisa especialmente:
- SKU y producto.
- Stock físico actual.
- Unidades de Ventas rápidas a devolver.
- Unidades físicas de Pedidos a devolver.
- Reservas de Pedidos a liberar.
- Stock resultante.
- Total de dinero actual antes.

No continúes si aparece una cantidad que no reconoces.

## 4. Aplicar restauración
Cuando la previsualización sea correcta, descomenta únicamente la llamada de PASO C y ejecútala una vez con la clave:

`LIHEN-RECONSTRUCCION-2026-08-07-V1`

La operación debe indicar `financial_accounts_changed: false`.

## 5. Verificar
Ejecuta PASO D.

El total de Caja y cuentas debe ser exactamente igual antes y después.

Los registros antiguos quedarán archivados, no borrados. El frontend nuevo no los mostrará como operaciones activas.

## 6. Publicar frontend
Después de terminar el SQL, sube el proyecto actualizado a GitHub Pages.

Haz Ctrl + F5 y revisa:
- Pedidos.
- Ventas rápidas.
- Inventario y catálogo.
- Proveedores.
- Reportes.
- Caja y cuentas.

## 7. Reconstruir historia
Para compras antiguas usa `Compra histórica`: no afecta inventario ni caja.

Para ventas antiguas que vas a volver a cargar después de restaurar stock usa `Venta histórica de reconstrucción`: descuenta inventario pero no suma dinero a caja.

Para pedidos antiguos vendidos usa `Pedido histórico ya vendido`: descuenta inventario pero no suma dinero a caja.

Para operaciones nuevas usa siempre el modo Actual.

## 8. Regla del punto de corte
Los saldos actuales de Efectivo y Nequi son la línea base financiera. No vuelvas a sumarles ventas históricas ya incluidas en ese dinero.


## Corrección 07-08-2026 — ejecución desde Supabase SQL Editor

Se detectó que `apply_operational_reconstruction(...)` rechazaba el SQL Editor con `P0001: Acceso no autorizado` porque `auth.uid()` es nulo fuera de una sesión de la aplicación. La versión corregida de `034_reconstruccion_operativa_controlada.sql` admite exclusivamente una sesión administrativa `postgres` del SQL Editor y atribuye la auditoría a una cofundadora activa. Para bases donde el 034 anterior ya fue instalado, ejecutar `sql/037_hotfix_reconstruccion_sql_editor.sql` antes de repetir el PASO C del 035. El hotfix no modifica Caja ni inventario por sí mismo y no concede acceso a `anon`.
