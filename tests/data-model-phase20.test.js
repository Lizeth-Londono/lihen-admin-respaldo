import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../sql/024_modelo_datos_consolidado_fase_20.sql', import.meta.url), 'utf8');

test('fase 20 reutiliza supplier_requests y no duplica encabezado de compra', () => {
  assert.match(sql, /alter table public\.supplier_requests/i);
  assert.doesNotMatch(sql, /create table if not exists public\.supplier_purchases\s*\(/i);
});

test('fase 20 separa recepción, pagos y movimientos financieros', () => {
  for (const table of [
    'supplier_purchase_receipts',
    'supplier_purchase_receipt_items',
    'financial_accounts',
    'financial_movements',
    'supplier_payments',
    'product_cost_history'
  ]) {
    assert.match(sql, new RegExp(`create table if not exists public\\.${table}`, 'i'));
  }
});

test('fase 20 incorpora relaciones restrictivas e idempotencia', () => {
  assert.match(sql, /references public\.supplier_requests\(id\) on delete restrict/i);
  assert.match(sql, /references public\.financial_movements\(id\) on delete restrict/i);
  assert.match(sql, /unique\(operation_key\)/i);
});

test('fase 20 habilita RLS y retira escritura directa', () => {
  assert.match(sql, /enable row level security/i);
  assert.match(sql, /revoke insert, update, delete, truncate, references, trigger/i);
  assert.match(sql, /public\.is_active_cofounder\(\)/i);
});
