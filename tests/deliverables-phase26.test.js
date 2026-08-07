import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

test('fase 26 prepara informe, lista de cambios y guía de entregables', async () => {
  const files = await Promise.all([
    read('docs/FASE_26_ENTREGABLES_FINALES.md'),
    read('docs/INFORME_TECNICO_FINAL_LIHEN_ADMIN_PRO.md'),
    read('docs/LISTA_CAMBIOS_LIHEN_ADMIN_PRO.md')
  ]);
  for (const content of files) assert.ok(content.length > 500);
});

test('fase 26 no declara producción validada sin Supabase real', async () => {
  const content = await read('docs/FASE_26_ENTREGABLES_FINALES.md');
  assert.match(content, /Supabase real|entorno de prueba/i);
  assert.match(content, /no se genera/i);
});

test('informe final registra las pruebas locales verificadas', async () => {
  const content = await read('docs/INFORME_TECNICO_FINAL_LIHEN_ADMIN_PRO.md');
  assert.match(content, /72 pruebas aprobadas/i);
  assert.match(content, /48 módulos JavaScript/i);
});
