import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { buildSupplierPurchaseImportPlan, SUPPLIER_PURCHASE_TEMPLATE_VERSION } from '../js/services/supplier-purchase-bulk-service.js';

test('plantilla de compras está versionada',()=>assert.equal(SUPPLIER_PURCHASE_TEMPLATE_VERSION,'LIHEN-COMPRAS-PROVEEDORES-V1'));
test('compra histórica conserva impacto cero',()=>{
 const plan=buildSupplierPurchaseImportPlan([{row_number:2,purchase_type:'Histórica',supplier_name:'Glow',purchase_date:'2026-08-04',total_amount:100,inventory_impact:'No',financial_impact:'No'}],[{row_number:2,purchase_key:'glow|2026-08-04||100.00|historica',sku:'A1',quantity_requested:1,quantity_received:0,unit_cost:100}],[],{suppliers:[{id:'s1',business_name:'Glow'}],products:[{id:'p1',sku:'A1'}]});
 assert.equal(plan.summary.historical,1); assert.equal(plan.purchases[0].inventory_impact,false); assert.equal(plan.purchases[0].financial_impact,false);
});
test('migración masiva usa RPC y RLS',()=>{ const sql=fs.readFileSync(new URL('../sql/031_importacion_exportacion_masiva_compras_proveedores.sql',import.meta.url),'utf8'); assert.match(sql,/import_supplier_purchases_batch_atomic/); assert.match(sql,/enable row level security/); assert.match(sql,/register_historical_supplier_purchase_atomic/); });
