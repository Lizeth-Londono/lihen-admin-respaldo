import test from 'node:test';
import assert from 'node:assert/strict';
import { canEditOrder, canPerformOrderAction } from '../js/services/order-state-service.js';

test('bloquea la edición de pedidos entregados', () => {
  assert.equal(canEditOrder('entregado'), false);
  assert.equal(canPerformOrderAction('entregado', 'receipt'), true);
});

test('permite editar pedidos completos', () => {
  assert.equal(canEditOrder('pedido_completo'), true);
  assert.equal(canPerformOrderAction('pedido_completo', 'send-summary'), true);
});
