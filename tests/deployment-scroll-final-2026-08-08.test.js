import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const css = fs.readFileSync(new URL('../css/app.css', import.meta.url), 'utf8').replace(/\s+/g,' ');

test('despliegue usa cache-busting final para CSS y JS', () => {
  assert.match(html, /css\/app\.css\?v=20260808-scroll-fix-final-v1/);
  assert.match(html, /js\/main\.js\?v=20260808-scroll-fix-final-v1/);
  assert.doesNotMatch(html, /20260807-fix-imports-v1/);
});

test('regla final deja un único scroll vertical en venta rápida', () => {
  assert.match(css, /LIHEN MODAL SCROLL FINAL 2026-08-08/);
  assert.match(css, /\.modal-body\{ flex:1 1 auto; min-height:0; overflow-y:auto; overflow-x:hidden;/);
  assert.match(css, /\.quick-sale-form \.sale-items-list\{ max-height:none; overflow:visible;/);
  assert.match(css, /\.quick-sale-form \.form-actions\{ position:sticky; bottom:0;/);
});
