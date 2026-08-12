import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(new URL('../sql/041_integridad_inventario_fase_7.sql', import.meta.url), 'utf8');
const importService = fs.readFileSync(new URL('../js/services/inventory-import-service.js', import.meta.url), 'utf8');

function normalized(value) {
  return value.replace(/\s+/g, ' ').toLowerCase();
}

const compactSql = normalized(sql);

test('Fase 7 protege cantidades negativas y reserva superior al físico', () => {
  assert.match(compactSql, /check \(physical_stock >= 0\) not valid/);
  assert.match(compactSql, /check \(reserved_stock >= 0\) not valid/);
  assert.match(compactSql, /check \(pending_stock >= 0\) not valid/);
  assert.match(compactSql, /check \(reserved_stock <= physical_stock\) not valid/);
});

test('Fase 7 valida que variant_id pertenezca al mismo producto', () => {
  assert.match(compactSql, /create or replace function public\.validate_inventory_product_variant/);
  assert.match(compactSql, /pv\.id = new\.variant_id and pv\.product_id = new\.product_id/);
  assert.match(compactSql, /before insert or update of product_id, variant_id/);
});

test('ajuste manual solo recibe stock físico; no acepta reservados, pendientes ni disponibles', () => {
  const signature = compactSql.match(/create or replace function public\.adjust_inventory_atomic\((.*?)\) returns public\.inventory/s)?.[1] || '';
  assert.match(signature, /p_new_physical_stock integer/);
  assert.doesNotMatch(signature, /reserved/);
  assert.doesNotMatch(signature, /pending/);
  assert.doesNotMatch(signature, /available/);
});

test('ajuste manual bloquea físico por debajo de reserva y crea movimiento con before/after', () => {
  assert.match(compactSql, /p_new_physical_stock < v_inventory\.reserved_stock/);
  assert.match(compactSql, /insert into public\.inventory_movements/);
  assert.match(compactSql, /physical_before, physical_after/);
  assert.match(compactSql, /reserved_before, reserved_after/);
});

test('Excel mantiene stock reservado/disponible/pendiente como campos protegidos', () => {
  assert.match(importService, /reported_reserved_stock/);
  assert.match(importService, /reported_available_stock/);
  assert.match(importService, /reported_pending_stock/);
  assert.match(importService, /PROTECTED_REPORTED_FIELDS|protected/i);
});
