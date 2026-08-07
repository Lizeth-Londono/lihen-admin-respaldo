import test from 'node:test';
import assert from 'node:assert/strict';
import { buildInventoryImportPlan, buildRejectedRows, getInventoryImportChangeLabels } from '../js/services/inventory-import-service.js';

const products=[{id:'p1',sku:'BC-001',name:'Producto A',business_line:'Beauty Care',current_cost:10000,sale_price:15000,minimum_stock:2,visible_on_website:true,status:'activo',inventory:[{physical_stock:5}]}];

test('resume cambios sensibles de stock, costo, precio y visibilidad',()=>{
 const plan=buildInventoryImportPlan([{row_number:2,internal_id:'p1',sku:'BC-001',name:'Producto A',physical_stock:8,current_cost:11000,sale_price:17000,visible_on_website:false}],products);
 assert.equal(plan.summary.stock_changes,1);
 assert.equal(plan.summary.cost_changes,1);
 assert.equal(plan.summary.price_changes,1);
 assert.equal(plan.summary.visibility_changes,1);
 const labels=getInventoryImportChangeLabels(plan.rows[0]).map(x=>x.label);
 assert.ok(labels.includes('Stock actual'));
});

test('genera filas rechazadas con campo, valor, motivo y corrección',()=>{
 const plan=buildInventoryImportPlan([{row_number:7,sku:'BC-NEW',name:'Nuevo',physical_stock:Number.NaN}],products);
 const rejected=buildRejectedRows(plan);
 assert.equal(plan.summary.error,1);
 assert.equal(rejected[0].Fila,7);
 assert.equal(rejected[0].SKU,'BC-NEW');
 assert.equal(rejected[0]['Campo afectado'],'Stock actual');
 assert.ok(rejected[0]['Motivo del error']);
 assert.ok(rejected[0]['Corrección esperada']);
});

test('una advertencia no bloquea la importación',()=>{
 const plan=buildInventoryImportPlan([{row_number:2,internal_id:'p1',sku:'BC-009',name:'Producto A'}],products);
 assert.equal(plan.summary.error,0);
 assert.equal(plan.summary.warning,1);
 assert.equal(plan.rows[0].action,'update');
});

test('detecta estado inválido con detalle estructurado',()=>{
 const plan=buildInventoryImportPlan([{row_number:4,sku:'BC-200',name:'Nuevo',status:'eliminado'}],products);
 assert.equal(plan.rows[0].action,'error');
 const rejected=buildRejectedRows(plan);
 assert.equal(rejected[0]['Campo afectado'],'Estado producto');
});
