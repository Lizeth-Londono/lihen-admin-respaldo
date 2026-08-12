import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../sql/042_movimientos_inventario_fase_8.sql', import.meta.url), 'utf8');
const jsFiles = [
  '../js/repositories/inventory-repository.js',
  '../js/repositories/order-repository.js',
  '../js/repositories/quick-sale-repository.js',
  '../js/repositories/supplier-purchase-repository.js'
].map(p => fs.readFileSync(new URL(p, import.meta.url), 'utf8'));

test('Fase 8 convierte inventory_movements en bitácora sin escritura directa del cliente', () => {
  assert.match(sql, /revoke insert, update, delete on public\.inventory_movements from authenticated, anon/i);
  assert.match(sql, /grant select on public\.inventory_movements to authenticated/i);
});

test('Fase 8 exige cantidad positiva y snapshots no negativos', () => {
  assert.match(sql, /check \(quantity > 0\) not valid/i);
  assert.match(sql, /physical_before >= 0 and physical_after >= 0/i);
  assert.match(sql, /reserved_before >= 0 and reserved_after >= 0/i);
});

test('Fase 8 protege que la reserva no supere el físico en los snapshots', () => {
  assert.match(sql, /reserved_before <= physical_before/i);
  assert.match(sql, /reserved_after <= physical_after/i);
});

test('Fase 8 valida dirección semántica de movimientos conocidos', () => {
  for (const type of ['reserva_pedido','liberacion_reserva','salida_venta','entrada_compra','ajuste_positivo','ajuste_negativo']) {
    assert.match(sql, new RegExp(type));
  }
});

test('La aplicación no inserta inventory_movements directamente desde JavaScript', () => {
  for (const source of jsFiles) {
    assert.doesNotMatch(source, /from\(['"]inventory_movements['"]\)\.insert/i);
  }
});
