# Guía segura de instalación — migración consolidada LIHEN

Esta guía instala la ampliación de compras a proveedores, caja y cuentas, pagos, importación segura, idempotencia e integración financiera sin obligarte a ejecutar manualmente las migraciones 022 a 029 una por una.

## Archivo que debes usar

Ejecuta únicamente:

`sql/supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql`

Este archivo reúne, en el orden correcto, las migraciones 022 a 029. Cada bloque conserva su propia transacción y sus protecciones idempotentes.

## Requisito previo

La base actual de LIHEN debe tener instalado el esquema principal y las migraciones históricas 001 a 013. La migración consolidada amplía ese esquema; no lo reemplaza.

## 1. Haz una copia de seguridad

Antes de ejecutar cualquier SQL en producción:

1. Abre el proyecto de Supabase de LIHEN.
2. Entra a **Database → Backups** y confirma que exista una copia reciente.
3. Exporta, como mínimo, las tablas de productos, inventario, proveedores, pedidos, pagos y ventas rápidas.
4. Guarda una copia del proyecto web que está actualmente publicado.

No continúes si no puedes recuperar la base en caso de error.

## 2. Verifica que no haya usuarios operando

Realiza la actualización en un momento en que nadie esté:

- creando pedidos;
- registrando ventas rápidas;
- importando productos;
- modificando inventario;
- registrando pagos.

Esto evita que cambien datos mientras se instala el nuevo modelo.

## 3. Ejecuta la migración consolidada

1. Abre **Supabase → SQL Editor**.
2. Crea una consulta nueva.
3. Copia todo el contenido de `supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql`.
4. Pégalo completo, sin eliminar bloques.
5. Ejecuta la consulta.
6. Espera hasta que Supabase indique que finalizó.

No ejecutes simultáneamente los archivos 022 a 029 si ya utilizaste la migración consolidada.

## 4. Ejecuta el diagnóstico

Después de la migración, ejecuta:

```sql
select public.validate_lihen_schema_coherence();
```

El resultado esperado es equivalente a:

```json
{
  "ok": true,
  "missing_columns": [],
  "missing_functions": []
}
```

Si `ok` aparece en `false`, no publiques todavía el frontend actualizado. Guarda el resultado completo para identificar la columna o función faltante.

## 5. Verifica las cuentas financieras

Confirma que existan las cuentas base:

- Nequi.
- Efectivo físico.

No se crean saldos ficticios. Desde la aplicación deberás registrar el saldo inicial real de cada cuenta.

## 6. Configura los saldos iniciales

En la aplicación:

1. Entra a **Caja y cuentas**.
2. Abre Nequi.
3. Registra el saldo real disponible y la fecha de inicio.
4. Repite el proceso para Efectivo físico.
5. Escribe una justificación clara.

No uses ventas menos compras como saldo inicial. Debe ser el dinero real que LIHEN tiene en ese momento.

## 7. Prueba en este orden

Realiza una prueba pequeña y controlada:

1. Crea una compra en borrador.
2. Confírmala.
3. Registra una recepción parcial de una sola unidad.
4. Comprueba el movimiento de inventario.
5. Registra un pago pequeño desde la cuenta correcta.
6. Comprueba que el saldo disminuya una sola vez.
7. Registra una venta rápida de prueba.
8. Comprueba que el saldo aumente una sola vez.
9. Abre Reportes y compara compras, pagos, ingresos y dinero disponible.
10. Exporta el inventario y verifica que incluya productos con stock cero.

## 8. Revisión de seguridad

Comprueba que:

- RLS continúe habilitado;
- la aplicación use únicamente la clave publicable de Supabase;
- no exista una `service_role` en archivos JavaScript;
- usuarios no autorizados no puedan insertar directamente movimientos financieros;
- las operaciones críticas se ejecuten mediante RPC.

## 9. Publicación del frontend

Solo después de aprobar las pruebas:

1. Sube el proyecto actualizado al repositorio correcto.
2. Confirma la rama configurada en GitHub Pages.
3. Espera a que termine el despliegue.
4. Abre la aplicación en una ventana privada.
5. Inicia sesión.
6. Revisa la consola del navegador.
7. Verifica que no existan errores rojos ni solicitudes fallidas.
8. Haz una recarga forzada con `Ctrl + F5`.

## 10. Qué hacer si falla la instalación

- No vuelvas a ejecutar repetidamente la migración sin leer el error.
- Copia el primer error completo de Supabase.
- Identifica el bloque indicado en el mensaje.
- No borres tablas ni desactives RLS para resolverlo rápidamente.
- Restaura la copia de seguridad si la base quedó en un estado no confiable.

## Alcance de esta migración

La migración consolidada amplía una base LIHEN existente. No contiene el archivo histórico `001_core_schema.sql` ni reconstruye una base vacía desde cero.
