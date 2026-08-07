import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

test('supplier purchase UI exposes create, receive and payment flows', async () => {
  const source = await read('js/supplier-purchases.js');
  for (const token of ['newSupplierPurchase', 'viewSupplierPurchases', 'receiveSupplierPurchase', 'registerSupplierPayment', 'confirmAction']) assert.match(source, new RegExp(token));
});

test('cash UI exposes initial balance and manual movement forms', async () => {
  const source = await read('js/financial-accounts.js');
  for (const token of ['configureAccountBalance', 'newFinancialMovement', 'configureInitialBalance', 'registerFinancialMovement']) assert.match(source, new RegExp(token));
});

test('main routes supplier purchase and account actions', async () => {
  const source = await read('js/main.js');
  assert.match(source, /data-new-supplier-purchase/);
  assert.match(source, /data-view-supplier-purchases/);
  assert.match(source, /data-configure-account/);
  assert.match(source, /new-financial-movement/);
});
