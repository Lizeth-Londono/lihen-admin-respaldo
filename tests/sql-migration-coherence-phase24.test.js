import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../sql/029_coherencia_migraciones_fase_24.sql', import.meta.url), 'utf8');
const phase26 = readFileSync(new URL('../sql/026_consolidacion_funcional_fases_2_15.sql', import.meta.url), 'utf8');

test('fase 24 normaliza aliases incompatibles entre migraciones', () => {
  assert.match(migration, /reception_status/);
  assert.match(migration, /receipt_status/);
  assert.match(migration, /financial_account_id/);
  assert.match(migration, /payment_date/);
  assert.match(migration, /sync_supplier_request_reception_status/);
});

test('completa columnas requeridas por transferencias y reversiones', () => {
  assert.match(migration, /performed_by/);
  assert.match(migration, /transfer_group_id/);
  assert.match(migration, /reversal_of_id/);
  assert.match(migration, /saldo_inicial/);
});

test('incluye diagnóstico ejecutable de coherencia', () => {
  assert.match(migration, /validate_lihen_schema_coherence/);
  assert.match(migration, /missing_columns/);
  assert.match(migration, /missing_functions/);
});

test('fase 26 usa los nombres canónicos del modelo consolidado', () => {
  assert.match(phase26, /financial_account_id uuid/);
  assert.match(phase26, /payment_date timestamptz/);
  assert.match(phase26, /currency_code text/);
  assert.doesNotMatch(phase26, /values \('nequi','Nequi','wallet'\)/);
});
