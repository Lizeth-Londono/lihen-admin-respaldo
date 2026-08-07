import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('la migración histórica declara impacto cero', () => {
  const sql = fs.readFileSync('sql/030_compras_historicas_sin_impacto.sql', 'utf8');
  assert.match(sql, /is_historical/);
  assert.match(sql, /inventory_impact/);
  assert.match(sql, /financial_impact/);
  assert.match(sql, /true,false,false/);
  assert.match(sql, /NO modifica inventory, financial_accounts ni financial_movements/);
});

test('la interfaz ofrece compra histórica', () => {
  const views = fs.readFileSync('js/views.js', 'utf8');
  const purchases = fs.readFileSync('js/supplier-purchases.js', 'utf8');
  assert.match(views, /data-new-historical-purchase/);
  assert.match(purchases, /newHistoricalSupplierPurchase/);
  assert.match(purchases, /sin afectar inventario ni caja/);
});
