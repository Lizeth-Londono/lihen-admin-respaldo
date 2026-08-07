import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { normalizePurchaseItems, calculatePurchaseTotals } from '../js/services/supplier-purchase-service.js';
import { summarizeAccounts, validateMoneyMovement } from '../js/services/financial-account-service.js';

test('consolida productos repetidos en una compra', () => {
  const rows = normalizePurchaseItems([
    { product_id:'a', quantity_requested:2, quoted_unit_cost:1000 },
    { product_id:'a', quantity_requested:3, quoted_unit_cost:1000 }
  ]);
  assert.equal(rows.length,1); assert.equal(rows[0].quantity_requested,5);
});

test('calcula total de compra con descuento, impuestos y flete', () => {
  const result = calculatePurchaseTotals([{quantity_requested:2,quoted_unit_cost:10000}],{discountAmount:1000,taxAmount:500,freightAmount:2500});
  assert.deepEqual(result,{subtotal:20000,total:22000});
});

test('resume cuentas separando Nequi y efectivo', () => {
  assert.deepEqual(summarizeAccounts([{code:'nequi',current_balance:10,active:true},{code:'efectivo',current_balance:5,active:true}]),{total:15,nequi:10,cash:5});
});

test('valida movimientos monetarios', () => {
  assert.equal(validateMoneyMovement({amount:100,type:'ingreso'}),100);
  assert.throws(()=>validateMoneyMovement({amount:0,type:'ingreso'}));
});

test('migración de consolidación contiene RPC esenciales', () => {
  const sql=fs.readFileSync(new URL('../sql/026_consolidacion_funcional_fases_2_15.sql',import.meta.url),'utf8');
  for(const name of ['create_supplier_purchase_atomic','configure_initial_balance_atomic','register_financial_movement_atomic','register_supplier_payment_atomic']) assert.match(sql,new RegExp(name));
});
