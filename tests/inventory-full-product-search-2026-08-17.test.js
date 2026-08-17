import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const repository = readFileSync(new URL('../js/repositories/product-repository.js', import.meta.url), 'utf8');
const views = readFileSync(new URL('../js/views.js', import.meta.url), 'utf8');
const main = readFileSync(new URL('../js/main.js', import.meta.url), 'utf8');

test('inventario: productos se cargan paginados y ya no están limitados a 300', () => {
  assert.match(repository, /PRODUCT_PAGE_SIZE\s*=\s*200/);
  assert.match(repository, /\.range\(from,\s*from \+ PRODUCT_PAGE_SIZE - 1\)/);
  assert.match(repository, /if \(page\.length < PRODUCT_PAGE_SIZE\) break/);
  assert.match(repository, /from \+= PRODUCT_PAGE_SIZE/);
  assert.doesNotMatch(repository, /limit\s*=\s*300/);
  assert.doesNotMatch(repository, /\.limit\(300\)/);
});

test('inventario: paginación usa orden estable para no saltar ni repetir registros', () => {
  assert.match(repository, /\.order\('name'\)[\s\S]*\.order\('id'\)/);
});

test('inventario: cada fila expone términos de búsqueda completos', () => {
  assert.match(views, /\[p\.name,p\.sku,p\.catalog_code,p\.brand,p\.category,p\.subcategory\]/);
  assert.match(views, /data-product-search=/);
  assert.match(views, /data-web-state=/);
  assert.match(views, /Buscar por nombre, SKU, código, marca o categoría/);
});

test('inventario: búsqueda y visibilidad se combinan sin pisarse', () => {
  assert.match(main, /const applyProductFilters = \(\) =>/);
  assert.match(main, /row\.dataset\.productSearch/);
  assert.match(main, /row\.dataset\.webState/);
  assert.match(main, /matchesSearch && matchesVisibility/);
  assert.match(main, /#productSearch/);
  assert.match(main, /#productVisibility/);
});
