import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../sql/045_integracion_admin_web_catalog_contract.sql', import.meta.url), 'utf8');
const forms = readFileSync(new URL('../js/forms.js', import.meta.url), 'utf8');
const views = readFileSync(new URL('../js/views.js', import.meta.url), 'utf8');
const repository = readFileSync(new URL('../js/repositories/product-repository.js', import.meta.url), 'utf8');

test('045 convierte catalog_public en gate activo + visible + fotografía', () => {
  assert.match(migration, /p\.status\s*=\s*'activo'/);
  assert.match(migration, /p\.visible_on_website\s*=\s*true/);
  assert.match(migration, /resolved_main_image_url/);
  assert.match(migration, /is not null/);
});

test('045 deriva disponibilidad sin exponer cantidades internas', () => {
  assert.match(migration, /availability_status/);
  assert.match(migration, /Disponible/);
  assert.match(migration, /Agotado/);
  assert.match(migration, /catalog_public expone columnas sensibles/);
});

test('045 mantiene catalog_public como única frontera anon del catálogo', () => {
  for (const table of ['products','inventory','product_variants','product_images','suppliers','supplier_products','inventory_movements']) {
    assert.match(migration, new RegExp(`revoke all on table public\\.${table} from anon`, 'i'));
  }
  assert.match(migration, /grant select on public\.catalog_public to anon, authenticated/i);
});

test('producto nuevo queda oculto por defecto y admite imagen pública', () => {
  assert.match(forms, /name="visible_on_website"><option value="false" selected>No<\/option>/);
  assert.match(forms, /name="main_image_url"/);
  assert.match(forms, /main_image_url:f\.main_image_url/);
});

test('inventario ADMIN diferencia oculto, pendiente de foto y publicado', () => {
  assert.match(views, /Pendiente foto/);
  assert.match(views, /Publicado/);
  assert.match(repository, /product_images\(id,public_url,is_main,sort_order\)/);
});
