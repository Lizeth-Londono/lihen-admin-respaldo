import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../sql/039_catalog_public_inventario_dinamico.sql', import.meta.url), 'utf8');

test('fase 5: catalog_public deriva disponibilidad desde inventory', () => {
  assert.match(sql, /from public\.inventory i/i);
  assert.match(sql, /availability_status/i);
  assert.match(sql, /Disponible/);
  assert.match(sql, /Agotado/);
});

test('fase 5: inventario, variantes e imágenes se preagregan', () => {
  assert.match(sql, /variant_inventory as/i);
  assert.match(sql, /inventory_public as/i);
  assert.match(sql, /variants_public as/i);
  assert.match(sql, /images_public as/i);
});

test('fase 5: la vista pública no expone cantidades ni datos administrativos sensibles', () => {
  const selectPart = sql.slice(sql.lastIndexOf('\nselect\n'));
  for (const forbidden of ['current_cost', 'minimum_stock', 'reserved_stock', 'pending_stock', 'average_cost', 'supplier_id']) {
    assert.equal(new RegExp(`\\bp\\.${forbidden}\\b`, 'i').test(selectPart), false, `${forbidden} no debe exponerse`);
  }
  assert.equal(/\bas available_stock\b/i.test(selectPart), false, 'la cantidad exacta no debe exponerse en el SELECT final');
});

test('fase 5: la vista conserva seguridad de solo lectura pública', () => {
  assert.match(sql, /revoke all on public\.catalog_public from public/i);
  assert.match(sql, /grant select on public\.catalog_public to anon, authenticated/i);
});

test('fase 5: contrato de imágenes conserva url, alt, sort_order e is_main', () => {
  for (const key of ["'url'", "'alt'", "'sort_order'", "'is_main'"]) assert.ok(sql.includes(key));
});
