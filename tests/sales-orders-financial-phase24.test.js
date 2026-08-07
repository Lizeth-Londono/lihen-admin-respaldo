import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = file => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('ventas rápidas exigen una cuenta y usan RPC financiera', () => {
  const sales = read('js/sales.js');
  const repo = read('js/repositories/quick-sale-repository.js');
  assert.match(sales, /financial_account_id/);
  assert.match(sales, /loadFinancialAccounts/);
  assert.match(repo, /create_quick_sale_financial_atomic_idempotent/);
  assert.match(repo, /cancel_quick_sale_financial_atomic_idempotent/);
});

test('cierre directo de pedidos registra la cuenta receptora', () => {
  const workflow = read('js/order-workflow.js');
  const repo = read('js/repositories/order-repository.js');
  assert.match(workflow, /Cuenta que recibió el dinero/);
  assert.match(workflow, /p_financial_account_id/);
  assert.match(repo, /close_order_direct_financial_atomic_idempotent/);
});

test('migración integra ventas, anulaciones y pedidos con caja', () => {
  const sql = read('sql/028_integracion_ventas_pedidos_caja_fase_24.sql');
  assert.match(sql, /create_quick_sale_financial_atomic_idempotent/);
  assert.match(sql, /cancel_quick_sale_financial_atomic_idempotent/);
  assert.match(sql, /close_order_direct_financial_atomic_idempotent/);
  assert.match(sql, /financial_movement_id/);
  assert.match(sql, /Saldo insuficiente en la cuenta para anular esta venta/);
});
