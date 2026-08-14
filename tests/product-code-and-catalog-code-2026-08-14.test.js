import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { suggestNextProductSku, normalizeCatalogCode } from '../js/services/product-code-service.js';
import { buildInventoryImportPlan, buildInventoryImportBatchPayload } from '../js/services/inventory-import-service.js';

test('sugiere el siguiente SKU por línea de negocio', () => {
  const products = [
    { sku: 'BC-001' }, { sku: 'BC-081' }, { sku: 'bc-079' },
    { sku: 'ST-005' }, { sku: 'ST-X' }, { sku: null }
  ];
  assert.equal(suggestNextProductSku(products, 'Beauty Care'), 'BC-082');
  assert.equal(suggestNextProductSku(products, 'Style'), 'ST-006');
});

test('código catálogo vacío se normaliza a NULL', () => {
  assert.equal(normalizeCatalogCode(''), null);
  assert.equal(normalizeCatalogCode('   '), null);
  assert.equal(normalizeCatalogCode(null), null);
});

test('importador detecta Código catálogo repetido dentro del mismo Excel antes de PostgreSQL', () => {
  const plan = buildInventoryImportPlan([
    { row_number: 2, sku: 'BC-100', name: 'Uno', business_line: 'Beauty Care', catalog_code: '42' },
    { row_number: 3, sku: 'ST-100', name: 'Dos', business_line: 'Style', catalog_code: '42' }
  ], []);
  assert.equal(plan.summary.error, 1);
  assert.match(plan.rows[1].errors.join(' '), /Código catálogo.*repetido/i);
});

test('importador detecta Código catálogo ya usado por otro producto', () => {
  const products = [{ id: 'p1', sku: 'BC-001', name: 'Existente', catalog_code: 'CAT-42', inventory: [{ physical_stock: 0 }] }];
  const plan = buildInventoryImportPlan([
    { row_number: 2, sku: 'ST-006', name: 'Fragancia LIHEN', business_line: 'Style', catalog_code: 'CAT-42' }
  ], products);
  assert.equal(plan.summary.error, 1);
  assert.match(plan.rows[0].errors.join(' '), /Ya pertenece a BC-001/i);
});

test('ST-006 nuevo con Código catálogo vacío se prepara como NULL y puede crearse', () => {
  const plan = buildInventoryImportPlan([
    { row_number: 88, sku: 'ST-006', name: 'Fragancia LIHEN', business_line: 'Style', catalog_code: '' }
  ], []);
  assert.equal(plan.summary.error, 0);
  assert.equal(plan.rows[0].action, 'create');
  const payload = buildInventoryImportBatchPayload(plan, { sourceName: 'inventario.xlsx', operationKey: 'test-catalog-null' });
  assert.equal(payload.p_rows[0].catalog_code, null);
});

test('formulario de producto usa sugerencia automática por línea', () => {
  const source = fs.readFileSync(new URL('../js/forms.js', import.meta.url), 'utf8');
  assert.match(source, /suggestNextProductSku/);
  assert.match(source, /lineSelect\.addEventListener\('change',applySuggestion\)/);
  assert.match(source, /Siguiente SKU sugerido/);
});

test('migración 047 conserva unicidad y agrega mensaje defensivo amigable', () => {
  const sql = fs.readFileSync(new URL('../sql/047_catalog_code_y_sku_sugerido.sql', import.meta.url), 'utf8');
  assert.match(sql, /products_catalog_code_key/i);
  assert.match(sql, /El código catálogo % ya pertenece/i);
  assert.doesNotMatch(sql, /drop\s+(constraint|index).*products_catalog_code/i);
});
