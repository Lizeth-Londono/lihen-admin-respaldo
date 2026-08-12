import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../sql/040_creacion_producto_atomica.sql', import.meta.url), 'utf8');
const repository = fs.readFileSync(new URL('../js/repositories/product-repository.js', import.meta.url), 'utf8');
const forms = fs.readFileSync(new URL('../js/forms.js', import.meta.url), 'utf8');

test('fase 6: creación de producto es atómica en PostgreSQL', () => {
  assert.match(migration, /create or replace function public\.create_product_atomic/i);
  assert.match(migration, /insert into public\.products/i);
  assert.match(migration, /insert into public\.inventory/i);
  assert.match(migration, /insert into public\.supplier_products/i);
});

test('fase 6: la RPC valida identidad comercial y valores no negativos', () => {
  assert.match(migration, /lower\(trim\(p\.sku\)\)/i);
  assert.match(migration, /lower\(trim\(p\.catalog_code\)\)/i);
  assert.match(migration, /precio LIHEN debe ser mayor o igual a cero/i);
  assert.match(migration, /stock físico inicial debe ser mayor o igual a cero/i);
});

test('fase 6: la RPC está restringida a authenticated y cofundadora activa', () => {
  assert.match(migration, /not public\.is_active_cofounder\(\)/i);
  assert.match(migration, /revoke all on function public\.create_product_atomic\(jsonb,integer,uuid\) from public, anon/i);
  assert.match(migration, /grant execute .* to authenticated/i);
});

test('fase 6: el repositorio centraliza la llamada a create_product_atomic', () => {
  assert.match(repository, /export async function createProductAtomic/);
  assert.match(repository, /supabase\.rpc\('create_product_atomic'/);
});

test('fase 6: formulario de producto ya no encadena inserts directos de producto e inventario', () => {
  assert.match(forms, /createProductAtomic/);
  const section = forms.slice(forms.indexOf('export async function newProduct'), forms.indexOf('export async function newOrder'));
  assert.equal(/from\('products'\)\.insert/.test(section), false);
  assert.equal(/from\('inventory'\)\.insert/.test(section), false);
});
