import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { buildInventoryImportBatchPayload } from '../js/services/inventory-import-service.js';

const sql = fs.readFileSync(new URL('../sql/043_importacion_inventario_trazabilidad_fase_9.sql', import.meta.url), 'utf8');

test('el payload envía los valores before como estado esperado para updates', () => {
  const plan = {
    summary: { total: 1, unchanged: 0, error: 0 },
    rows: [{
      row_number: 2,
      action: 'update',
      current: { id: '00000000-0000-0000-0000-000000000001', sku: 'BC-001' },
      row: { sku: 'BC-001', sale_price: 28000, physical_stock: 7 },
      changes: {
        sale_price: { before: 25000, after: 28000 },
        physical_stock: { before: 3, after: 7 }
      }
    }]
  };
  const payload = buildInventoryImportBatchPayload(plan, { sourceName: 'inventario.xlsx', operationKey: 'phase9-test' });
  assert.deepEqual(payload.p_rows[0].expected, { sale_price: 25000, physical_stock: 3 });
});

test('la RPC persiste trazabilidad before/after real en import_batch_rows', () => {
  assert.match(sql, /v_before_product\s*:=\s*to_jsonb\(v_product\)/i);
  assert.match(sql, /jsonb_build_object\('before',[\s\S]*'after'/i);
  assert.match(sql, /insert into public\.import_batch_rows[\s\S]*changes/i);
});

test('la RPC detecta vistas previas obsoletas por campo', () => {
  assert.match(sql, /Conflicto de concurrencia[\s\S]*vista previa/i);
  assert.match(sql, /v_expected \? 'physical_stock'/i);
  assert.match(sql, /v_expected \? v_field/i);
});

test('la RPC valida coherencia del lote antes de escribir', () => {
  assert.match(sql, /jsonb_array_length\(p_rows\)[\s\S]*p_unchanged_rows[\s\S]*p_total_rows/i);
  assert.match(sql, /números de fila duplicados/i);
  assert.match(sql, /actualizar el mismo producto más de una vez/i);
});

test('la RPC conserva idempotencia por operation_key y transacción única', () => {
  assert.match(sql, /where operation_key = p_operation_key/i);
  assert.match(sql, /'idempotent', true/i);
  assert.match(sql, /^begin;/im);
  assert.match(sql, /commit;/i);
});
