# HOTFIX — `Failed to fetch` en login — 2026-08-12

## Síntoma

En GitHub Pages, la pantalla de acceso de LIHEN Admin carga correctamente pero el intento de autenticación termina mostrando `Failed to fetch`.

## Causa raíz encontrada

El cliente de Supabase se estaba inicializando con un header HTTP global personalizado:

`x-application-name: lihen-admin`

Ese header se adjuntaba a las solicitudes de Supabase y añadía una condición CORS/preflight innecesaria al flujo de Auth. Un fallo de CORS a nivel navegador se manifiesta en JavaScript como un `TypeError: Failed to fetch`, sin entregar al frontend el detalle del bloqueo.

La autenticación no necesita ese header. Se eliminó para que `supabase-js` utilice únicamente los headers esperados por la plataforma.

No se modificaron la URL del proyecto ni la Publishable Key porque el repositorio no contiene evidencia de un proyecto alternativo y no es seguro inventar credenciales.

## Solución aplicada

### `js/supabase.js`

- Se mantuvo `@supabase/supabase-js@2.57.4`.
- Se mantuvo `persistSession: true`.
- Se mantuvo `autoRefreshToken: true`.
- Se mantuvo `detectSessionInUrl: true`.
- Se eliminó el header global `x-application-name`.

### `js/errors.js`

- Se agregó clasificación segura de errores de red.
- `Invalid login credentials` se traduce a un mensaje amigable.
- Se distinguen errores de sesión y conectividad.
- Se añadió logging técnico seguro que no imprime contraseñas, tokens ni claves.

### `js/main.js`

- El arranque, login, cambio de contraseña y recuperación de contraseña registran errores técnicos seguros.
- El usuario ya no ve el texto crudo `Failed to fetch`.

### `tests/auth-login-connectivity-hotfix.test.js`

Se añadieron regresiones para validar configuración HTTPS, Publishable Key, ausencia de service role/secret, persistencia de sesión, ausencia del header problemático, uso de `signInWithPassword` y rutas relativas.

## Validaciones

Resultados del hotfix:

- `npm run check`: **OK** — 52 módulos JavaScript, rutas locales y exportaciones importadas.
- Validación sintáctica con `node --check` para los archivos JavaScript modificados: **OK**.
- `npm test`: **143 pruebas aprobadas de 144**. La única falla es preexistente en el ZIP original: `tests/no-sensitive-static-inventory.test.js`, porque el paquete ya incluía `data/inventario_inicial.json`. El ZIP original también falla esa misma prueba (137 aprobadas de 138). Este hotfix no elimina ni modifica ese archivo para no introducir cambios ajenos al problema de autenticación.
- Las 6 nuevas pruebas de regresión del login/conectividad: **OK**.

## Supabase

No se modificó ninguna tabla, dato, RLS, usuario ni credencial.

Si después de desplegar este hotfix el navegador continúa mostrando un error de conexión, verificar manualmente en Supabase Dashboard que el proyecto referenciado por `js/config.js` siga activo y que la Publishable Key corresponda a ese mismo proyecto.

Para recuperación de contraseña, revisar además **Authentication → URL Configuration** y confirmar que la URL publicada de GitHub Pages está autorizada como redirect URL.

URL esperada de la aplicación:

`https://lizeth-londono.github.io/lihen-admin-respaldo/`

## GitHub Pages

No se requieren cambios de rutas. El proyecto conserva `.nojekyll` y los recursos de arranque usan rutas relativas compatibles con el subdirectorio `/lihen-admin-respaldo/`.

Después de subir el ZIP corregido al repositorio, esperar a que GitHub Pages termine el despliegue y hacer una recarga forzada del navegador (`Ctrl + F5`).
