import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { buildInventoryImportPlan, createInventoryImportOperationKey } from '../js/services/inventory-import-service.js';

const products = [{
  id:'p1', sku:'BC-001', name:'Producto A', business_line:'Beauty Care', current_cost:1000,
  sale_price:2000, minimum_stock:0, visible_on_website:false, status:'activo',
  inventory:[{physical_stock:5,reserved_stock:2,available_stock:3,pending_stock:1}],
  supplier_products:[{preferred:true,supplier:{business_name:'Glow Belleza & Accesorios'}}]
}];
const suppliers = [{id:'s1',business_name:'Glow Belleza & Accesorios',active:true}];

test('el stock físico no puede quedar por debajo del reservado', () => {
  const plan = buildInventoryImportPlan([{row_number:2,internal_id:'p1',sku:'BC-001',name:'Producto A',physical_stock:1}], products, suppliers);
  assert.equal(plan.rows[0].action,'error');
  assert.match(plan.rows[0].errors.join(' '),/reservado/i);
});

test('las columnas protegidas generan advertencia y nunca son cambios editables', () => {
  const plan = buildInventoryImportPlan([{row_number:2,internal_id:'p1',sku:'BC-001',name:'Producto A',reported_reserved_stock:99}], products, suppliers);
  assert.equal(plan.rows[0].action,'unchanged');
  assert.equal(plan.summary.warning,1);
  assert.equal(Object.hasOwn(plan.rows[0].changes,'reported_reserved_stock'),false);
});

test('el proveedor actual no produce una actualización falsa', () => {
  const plan = buildInventoryImportPlan([{row_number:2,internal_id:'p1',sku:'BC-001',name:'Producto A',supplier_name:'Glow Belleza & Accesorios'}], products, suppliers);
  assert.equal(plan.rows[0].action,'unchanged');
});

test('la clave idempotente cambia cuando cambia el valor y permanece estable para el mismo plan', () => {
  const p1 = buildInventoryImportPlan([{row_number:2,internal_id:'p1',sku:'BC-001',name:'Producto A',sale_price:3000}], products, suppliers);
  const p2 = buildInventoryImportPlan([{row_number:2,internal_id:'p1',sku:'BC-001',name:'Producto A',sale_price:3500}], products, suppliers);
  assert.equal(createInventoryImportOperationKey('inventario.xlsx',p1), createInventoryImportOperationKey('inventario.xlsx',p1));
  assert.notEqual(createInventoryImportOperationKey('inventario.xlsx',p1), createInventoryImportOperationKey('inventario.xlsx',p2));
});

test('la migración 032 conserva historial de costos y no reemplaza proveedor preferido', () => {
  const sql = fs.readFileSync(new URL('../sql/032_compatibilidad_plantilla_inventario_2026_08_07.sql', import.meta.url),'utf8');
  assert.match(sql,/product_cost_import_history/i);
  assert.match(sql,/set last_cost=coalesce\(v_product\.current_cost,last_cost\)/i);
  assert.doesNotMatch(sql,/set preferred=true,last_cost/i);
  assert.match(sql,/values\(v_supplier\.id,v_product\.id,v_product\.current_cost,not v_has_preferred_supplier\)/i);
});
