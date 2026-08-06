import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeOrderItems, compareOrderItems } from '../js/services/order-payload-service.js';

test('normaliza cantidades y precios de productos', () => {
  assert.deepEqual(normalizeOrderItems([{ product_id: 10, quantity: '2', unit_price: '12500' }]), [{
    product_id: '10', variant_id: null, variant_snapshot: null, quantity: 2, unit_price: 12500
  }]);
});

test('detecta si Supabase guardó exactamente los productos esperados', () => {
  const expected = [{ product_id: 'a', quantity: 1, unit_price: 1000 }];
  assert.equal(compareOrderItems(expected, [{ product_id: 'a', quantity: 1, unit_price: 1000 }]), true);
  assert.equal(compareOrderItems(expected, [{ product_id: 'a', quantity: 2, unit_price: 1000 }]), false);
});
