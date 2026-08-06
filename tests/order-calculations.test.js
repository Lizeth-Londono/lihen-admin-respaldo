import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateOrderTotals } from '../js/order-calculations.js';

test('calcula subtotal, descuento fijo y domicilio', () => {
  const result = calculateOrderTotals([
    { quantity: 2, unit_price: 10000 },
    { quantity: 1, unit_price: 5000 }
  ], { discountType: 'valor_fijo', discountValue: 2000, deliveryCost: 3000 });
  assert.deepEqual(result, { subtotal: 25000, units: 3, discount: 2000, delivery: 3000, total: 26000 });
});

test('limita el descuento porcentual a 100%', () => {
  const result = calculateOrderTotals([{ quantity: 1, unit_price: 10000 }], { discountType: 'porcentaje', discountValue: 140 });
  assert.equal(result.total, 0);
});
