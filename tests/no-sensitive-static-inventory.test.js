import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const imports = fs.readFileSync(new URL('../js/imports.js', import.meta.url), 'utf8');
const views = fs.readFileSync(new URL('../js/views.js', import.meta.url), 'utf8');
const seedUrl = new URL('../data/inventario_inicial.json', import.meta.url);

test('el ADMIN no publica el inventario inicial sensible como JSON estático', () => {
  assert.equal(fs.existsSync(seedUrl), false);
  assert.doesNotMatch(imports, /fetch\(['"]data\/inventario_inicial\.json/);
});

test('la interfaz productiva usa importación Excel segura y no ofrece el cargue legacy', () => {
  assert.doesNotMatch(views, /data-action=['"]import-bundled-inventory/);
  assert.match(views, /data-action=['"]import-inventory/);
});
