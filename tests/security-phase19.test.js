import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../sql/023_seguridad_supabase_fase_19.sql', import.meta.url), 'utf8');
const config = await readFile(new URL('../js/config.js', import.meta.url), 'utf8');

test('fase 19 fuerza RLS y elimina escritura directa de importaciones', () => {
  assert.match(sql, /force row level security/i);
  assert.match(sql, /revoke insert, update, delete/i);
  assert.match(sql, /grant select on public\.import_batches to authenticated/i);
});

test('RPC queda limitada a authenticated y con search_path seguro', () => {
  assert.match(sql, /revoke all on function public\.import_inventory_batch_atomic[\s\S]*from public, anon/i);
  assert.match(sql, /grant execute on function public\.import_inventory_batch_atomic[\s\S]*to authenticated/i);
  assert.match(sql, /set search_path = ''/i);
});

test('incluye restricciones, unicidad e índices de consulta', () => {
  assert.match(sql, /import_batches_counts_nonnegative/i);
  assert.match(sql, /import_batch_rows_batch_row_unique/i);
  assert.match(sql, /import_batches_created_by_created_at_idx/i);
  assert.match(sql, /import_batch_rows_error_consistency/i);
});

test('valida límites y estructura del lote', () => {
  assert.match(sql, /validate_inventory_import_request/i);
  assert.match(sql, /10000/i);
  assert.match(sql, /Cada fila debe ser un objeto JSON/i);
  assert.match(sql, /Los productos nuevos requieren SKU y nombre/i);
});

test('frontend no contiene service role key', () => {
  assert.doesNotMatch(config, /service[_-]?role/i);
  assert.match(config, /supabasePublishableKey/);
});
