import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sqlPath = new URL('../sql/supabase_migracion_compras_caja_inventario_CONSOLIDADA.sql', import.meta.url);
const guidePath = new URL('../docs/GUIA_INSTALACION_MIGRACION_CONSOLIDADA.md', import.meta.url);

test('la migración consolidada contiene los bloques 022 a 029 en orden', async () => {
  const sql = await readFile(sqlPath, 'utf8');
  const names = [
    '022_importacion_inventario_transaccional_fase_18.sql',
    '023_seguridad_supabase_fase_19.sql',
    '024_modelo_datos_consolidado_fase_20.sql',
    '025_idempotencia_operaciones_fase_21.sql',
    '026_consolidacion_funcional_fases_2_15.sql',
    '027_transferencias_reversiones_fase_24.sql',
    '028_integracion_ventas_pedidos_caja_fase_24.sql',
    '029_coherencia_migraciones_fase_24.sql'
  ];

  let previous = -1;
  for (const name of names) {
    const index = sql.indexOf(`INICIO BLOQUE: ${name}`);
    assert.ok(index > previous, `${name} debe aparecer después del bloque anterior`);
    previous = index;
  }
});

test('la migración consolidada incluye el diagnóstico final y no usa includes de psql', async () => {
  const sql = await readFile(sqlPath, 'utf8');
  assert.match(sql, /validate_lihen_schema_coherence/);
  assert.doesNotMatch(sql, /\\i\s+/);
  assert.doesNotMatch(sql, /service_role/i);
});

test('la guía indica respaldo, diagnóstico y prueba controlada', async () => {
  const guide = await readFile(guidePath, 'utf8');
  assert.match(guide, /copia de seguridad/i);
  assert.match(guide, /validate_lihen_schema_coherence/);
  assert.match(guide, /prueba pequeña y controlada/i);
  assert.match(guide, /No se crean saldos ficticios/i);
});
