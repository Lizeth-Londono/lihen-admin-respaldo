import test from 'node:test';
import assert from 'node:assert/strict';
import { buildInventoryImportPlan, buildInventoryImportBatchPayload, mergeExistingProduct } from '../js/services/inventory-import-service.js';

const products = [
  { id: 'p1', sku: 'BC-001', name: 'Producto A', business_line: 'Beauty Care', sale_price: 10000, minimum_stock: 2, status: 'activo', visible_on_website: true, inventory: [{ physical_stock: 5 }] },
  { id: 'p2', sku: 'ST-001', name: 'Producto B', business_line: 'Style', sale_price: 20000, minimum_stock: 1, status: 'activo', visible_on_website: false, inventory: [{ physical_stock: 0 }] }
];

test('identifica primero por ID interno aunque el SKU cambie', () => {
  const plan = buildInventoryImportPlan([{ row_number: 2, internal_id: 'p1', sku: 'BC-009', name: 'Producto A' }], products);
  assert.equal(plan.rows[0].current.id, 'p1');
  assert.equal(plan.rows[0].action, 'update');
  assert.ok(plan.rows[0].warnings.some(text => text.includes('cambiar el SKU')));
});

test('usa SKU cuando el ID interno no existe', () => {
  const plan = buildInventoryImportPlan([{ row_number: 2, internal_id: 'antiguo', sku: 'BC-001', name: 'Producto A' }], products);
  assert.equal(plan.rows[0].current.id, 'p1');
  assert.equal(plan.rows[0].action, 'unchanged');
  assert.equal(plan.summary.warning, 1);
});

test('detecta conflicto entre ID y SKU de productos diferentes', () => {
  const plan = buildInventoryImportPlan([{ row_number: 2, internal_id: 'p1', sku: 'ST-001', name: 'Producto A' }], products);
  assert.equal(plan.rows[0].action, 'error');
  assert.ok(plan.rows[0].errors[0].includes('productos diferentes'));
});

test('no interpreta una celda ausente como cero', () => {
  const payload = mergeExistingProduct(products[0], { sku: 'BC-001', name: 'Producto A' }, 'user');
  assert.equal(payload.sale_price, 10000);
  assert.equal(payload.minimum_stock, 2);
});

test('un producto ausente del archivo no se marca para eliminar', () => {
  const plan = buildInventoryImportPlan([{ row_number: 2, internal_id: 'p1', sku: 'BC-001', name: 'Producto A' }], products);
  assert.equal(plan.rows.length, 1);
  assert.equal(Object.hasOwn(plan.summary, 'delete'), false);
});

test('detecta SKU repetidos dentro del archivo', () => {
  const plan = buildInventoryImportPlan([
    { row_number: 2, sku: 'BC-100', name: 'Nuevo 1', business_line: 'Beauty Care' },
    { row_number: 3, sku: 'bc-100', name: 'Nuevo 2', business_line: 'Beauty Care' }
  ], products);
  assert.equal(plan.summary.error, 1);
});

test('ignora proveedor no registrado como cambio para evitar falso conflicto de concurrencia', () => {
  const current = [{
    id: 'p1', sku: 'BC-082', name: 'Fragancia LIHEN', business_line: 'Beauty Care',
    supplier_products: [{ preferred: true, supplier: { business_name: 'Proveedor Actual' } }]
  }];
  const activeSuppliers = [{ id: 's1', business_name: 'Proveedor Actual', active: true }];
  const plan = buildInventoryImportPlan([{
    row_number: 83, internal_id: 'p1', sku: 'BC-082', name: 'Fragancia LIHEN', supplier_name: 'LIHEN.CO'
  }], current, activeSuppliers);
  assert.equal(plan.rows[0].action, 'unchanged');
  assert.equal(plan.summary.warning, 1);
  assert.equal(Object.hasOwn(plan.rows[0].changes, 'supplier_name'), false);
});

test('elige proveedor actual con el mismo orden determinista que la RPC', () => {
  const current = [{
    id: 'p1', sku: 'BC-001', name: 'Producto A', business_line: 'Beauty Care',
    supplier_products: [
      { preferred: false, supplier: { business_name: 'Zeta' } },
      { preferred: true, supplier: { business_name: 'Beta' } },
      { preferred: true, supplier: { business_name: 'Alfa' } }
    ]
  }];
  const suppliers = [
    { id: 'a', business_name: 'Alfa', active: true },
    { id: 'b', business_name: 'Beta', active: true },
    { id: 'z', business_name: 'Zeta', active: true }
  ];
  const plan = buildInventoryImportPlan([{
    row_number: 2, internal_id: 'p1', sku: 'BC-001', name: 'Producto A', supplier_name: 'Alfa'
  }], current, suppliers);
  assert.equal(plan.rows[0].action, 'unchanged');
});

test('no envía supplier_name en update cuando proveedor no es un cambio real', () => {
  const product = { id:'p1', sku:'BC-082', name:'Fragancia LIHEN', business_line:'Beauty Care', supplier_products:[{ preferred:true, supplier:{ business_name:'Glow Belleza & Accesorios' } }] };
  const row = { row_number:83, internal_id:'p1', sku:'BC-082', name:'Fragancia LIHEN', business_line:'Beauty Care', supplier_name:'LIHEN.CO', catalog_code:'BC-082' };
  const plan = buildInventoryImportPlan([row],[product],[{id:'s1',business_name:'Glow Belleza & Accesorios',active:true}]);
  const payload = buildInventoryImportBatchPayload(plan,{sourceName:'x.xlsx',operationKey:'op'});
  assert.equal(payload.p_rows[0].supplier_name, undefined);
});
