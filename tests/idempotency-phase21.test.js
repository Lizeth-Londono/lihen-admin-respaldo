import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createOperationKey, ensureOperationKey } from '../js/services/operation-key-service.js';

const sql = fs.readFileSync(new URL('../sql/025_idempotencia_operaciones_fase_21.sql', import.meta.url), 'utf8');
const quickRepo = fs.readFileSync(new URL('../js/repositories/quick-sale-repository.js', import.meta.url), 'utf8');
const orderRepo = fs.readFileSync(new URL('../js/repositories/order-repository.js', import.meta.url), 'utf8');

test('fase 21 crea claves únicas con prefijo estable', () => {
  const first = createOperationKey('Crear Venta Rápida');
  const second = createOperationKey('Crear Venta Rápida');
  assert.match(first, /^crear_venta_r_pida:[a-f0-9-]{36}$/i);
  assert.notEqual(first, second);
});

test('ensureOperationKey conserva una clave ya definida', () => {
  const payload = { p_operation_key: 'crear_pedido:clave-existente-1234', value: 1 };
  assert.equal(ensureOperationKey(payload, 'crear_pedido'), payload);
});

test('migración incorpora registro central, bloqueo y huella de solicitud', () => {
  assert.match(sql, /create table if not exists public\.operation_executions/i);
  assert.match(sql, /unique\(operation_type, operation_key\)/i);
  assert.match(sql, /pg_advisory_xact_lock/i);
  assert.match(sql, /request_fingerprint/i);
  assert.match(sql, /datos diferentes/i);
});

test('RPC críticas disponibles usan envolturas idempotentes', () => {
  for (const name of [
    'create_order_atomic_idempotent',
    'create_quick_sale_atomic_idempotent',
    'cancel_quick_sale_atomic_idempotent',
    'close_order_direct_atomic_idempotent'
  ]) assert.match(sql, new RegExp(`function public\\.${name}`, 'i'));
});

test('repositorios envían claves idempotentes automáticamente', () => {
  assert.match(quickRepo, /create_quick_sale_(?:financial_)?atomic_idempotent/);
  assert.match(quickRepo, /cancel_quick_sale_(?:financial_)?atomic_idempotent/);
  assert.match(orderRepo, /create_order_atomic_idempotent/);
  assert.match(orderRepo, /close_order_direct_(?:financial_)?atomic_idempotent/);
  assert.match(quickRepo, /ensureOperationKey/);
  assert.match(orderRepo, /ensureOperationKey/);
});

test('infraestructura futura ya tiene claves únicas para recepciones, movimientos y pagos', () => {
  const model = fs.readFileSync(new URL('../sql/024_modelo_datos_consolidado_fase_20.sql', import.meta.url), 'utf8');
  assert.match(model, /supplier_purchase_receipts[\s\S]*unique\(operation_key\)/i);
  assert.match(model, /financial_movements[\s\S]*unique\(operation_key\)/i);
  assert.match(model, /supplier_payments[\s\S]*unique\(operation_key\)/i);
});
