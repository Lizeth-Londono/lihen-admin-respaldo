import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = file => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('hotfix 038 permite anular ventas legacy sin inventar movimiento financiero', () => {
  const sql = read('sql/038_hotfix_anulacion_ventas_legacy.sql');
  assert.match(sql, /cancel_quick_sale_financial_atomic_idempotent/);
  assert.match(sql, /v_financial_legacy := true/);
  assert.match(sql, /cancel_quick_sale_atomic_idempotent/);
  assert.match(sql, /financial_reversal', null/);
  assert.doesNotMatch(sql, /raise exception 'La venta no tiene un movimiento financiero asociado'/);
});

test('hotfix 038 evita doble anulación aunque cambie la operation key', () => {
  const sql = read('sql/038_hotfix_anulacion_ventas_legacy.sql');
  assert.match(sql, /if v_sale\.status = 'anulada' then/);
  assert.match(sql, /already_cancelled/);
  assert.match(sql, /idempotent', true/);
});

test('hotfix 038 recupera vínculos financieros incompletos antes de considerar legacy', () => {
  const sql = read('sql/038_hotfix_anulacion_ventas_legacy.sql');
  assert.match(sql, /source_type = 'quick_sale'/);
  assert.match(sql, /source_id = v_sale\.id/);
  assert.match(sql, /financial_account_id = v_original\.account_id/);
  assert.match(sql, /financial_movement_id = v_original\.id/);
});

test('hotfix 038 conserva reversión financiera e integridad de saldo', () => {
  const sql = read('sql/038_hotfix_anulacion_ventas_legacy.sql');
  assert.match(sql, /Saldo insuficiente en la cuenta para anular esta venta/);
  assert.match(sql, /'anulacion_venta'/);
  assert.match(sql, /set status = 'reversado'/);
  assert.match(sql, /current_balance = v_reverse\.balance_after/);
});
