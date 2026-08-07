import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

test('los estados de carga y los toast tienen semántica accesible', async () => {
  const ui = await read('js/ui.js');
  assert.match(ui, /aria-live=\\?"polite\\?"/);
  assert.match(ui, /aria-busy=\\?"true\\?"/);
  assert.match(ui, /type === 'danger' \? 'alert' : 'status'/);
});

test('los modales administran foco y tabulación', async () => {
  const ui = await read('js/ui.js');
  assert.match(ui, /lastFocusedElement/);
  assert.match(ui, /event\.key !== 'Tab'/);
  assert.match(ui, /firstFocusable\?\.focus/);
});

test('los botones pendientes exponen estado ARIA', async () => {
  const errors = await read('js/errors.js');
  assert.match(errors, /aria-busy/);
  assert.match(errors, /aria-disabled/);
});

test('la hoja de estilos contempla móvil y preferencias del sistema', async () => {
  const css = await read('css/app.css');
  assert.match(css, /prefers-reduced-motion/);
  assert.match(css, /prefers-contrast/);
  assert.match(css, /safe-area-inset-bottom/);
  assert.match(css, /min-height:44px/);
});
