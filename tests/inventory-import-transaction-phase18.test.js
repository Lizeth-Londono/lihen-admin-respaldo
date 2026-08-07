import test from 'node:test';
import assert from 'node:assert/strict';
import { buildInventoryImportBatchPayload, createInventoryImportOperationKey } from '../js/services/inventory-import-service.js';

const plan={summary:{total:3,unchanged:1,error:0},rows:[
 {row_number:2,action:'update',current:{id:'p1',sku:'BC-001'},row:{sku:'BC-001',physical_stock:5},changes:{physical_stock:{before:2,after:5}}},
 {row_number:3,action:'create',current:null,row:{sku:'BC-999',name:'Nuevo'},changes:{}},
 {row_number:4,action:'unchanged',current:{id:'p2'},row:{sku:'BC-002'},changes:{}}
]};

test('construye un único lote con solo filas accionables',()=>{
 const payload=buildInventoryImportBatchPayload(plan,{sourceName:'inventario.xlsx',operationKey:'op-1'});
 assert.equal(payload.p_rows.length,2);
 assert.equal(payload.p_total_rows,3);
 assert.equal(payload.p_unchanged_rows,1);
 assert.equal(payload.p_rows[0].product_id,'p1');
});

test('bloquea planes con errores',()=>{
 assert.throws(()=>buildInventoryImportBatchPayload({...plan,summary:{...plan.summary,error:1}}),/errores/i);
});

test('genera claves de operación distintas por ejecución y estables con tiempo fijo',()=>{
 const first=createInventoryImportOperationKey('a.xlsx',plan,1000);
 const second=createInventoryImportOperationKey('a.xlsx',plan,1000);
 const third=createInventoryImportOperationKey('a.xlsx',plan,1001);
 assert.equal(first,second);
 assert.notEqual(first,third);
});
