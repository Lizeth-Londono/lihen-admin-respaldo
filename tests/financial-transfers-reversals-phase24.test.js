import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read = path => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

test('financial UI exposes transfers and reversals', async () => {
  const source = await read('js/financial-accounts.js');
  for (const token of ['transferBetweenAccounts','reverseMovement','transferFinancialFunds','reverseFinancialMovement']) assert.match(source, new RegExp(token));
});

test('cash view exposes transfer and reversal actions', async () => {
  const source = await read('js/views.js');
  assert.match(source, /transfer-financial-funds/);
  assert.match(source, /data-reverse-financial-movement/);
});

test('migration adds atomic transfer and reversal RPCs', async () => {
  const sql = await read('sql/027_transferencias_reversiones_fase_24.sql');
  assert.match(sql, /transfer_financial_funds_atomic/);
  assert.match(sql, /reverse_financial_movement_atomic/);
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /status='reversado'/);
});
