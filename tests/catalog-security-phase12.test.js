import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const sql = fs.readFileSync(path.join(root, 'sql/044_seguridad_catalogo_publico_fase_12.sql'), 'utf8');

test('fase 12 revoca acceso anon directo a tablas administrativas', () => {
  for (const table of ['products', 'inventory', 'product_variants', 'product_images', 'suppliers', 'supplier_products', 'inventory_movements']) {
    assert.match(sql, new RegExp(`revoke all on table public\\.${table} from anon`, 'i'));
  }
});

test('fase 12 deja catalog_public como frontera pública de solo lectura', () => {
  assert.match(sql, /grant select on public\.catalog_public to anon, authenticated/i);
  assert.match(sql, /security_barrier\s*=\s*true/i);
});

test('fase 12 aborta si catalog_public expone campos sensibles', () => {
  for (const field of ['current_cost', 'reserved_stock', 'pending_stock', 'available_stock', 'supplier_id']) {
    assert.match(sql, new RegExp(`'${field}'`, 'i'));
  }
  assert.match(sql, /raise exception 'catalog_public expone columnas sensibles/i);
});
