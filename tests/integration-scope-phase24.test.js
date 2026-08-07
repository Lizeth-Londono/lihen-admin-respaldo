import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const requiredCurrentFiles = [
  'js/services/inventory-import-service.js',
  'js/repositories/inventory-import-repository.js',
  'js/services/confirmation-service.js',
  'js/services/operation-key-service.js',
  'sql/022_importacion_inventario_transaccional_fase_18.sql',
  'sql/023_seguridad_supabase_fase_19.sql',
  'sql/024_modelo_datos_consolidado_fase_20.sql',
  'sql/025_idempotencia_operaciones_fase_21.sql'
];

test('fase 24 verifica que las implementaciones físicas consolidadas estén presentes', () => {
  for (const file of requiredCurrentFiles) {
    assert.equal(fs.existsSync(file), true, `Falta ${file}`);
  }
});

test('fase 24 mantiene explícita la limitación de integración incompleta', () => {
  const report = fs.readFileSync('docs/FASE_24_PRUEBAS_OBLIGATORIAS.md', 'utf8');
  assert.match(report, /fases 2 a 15 no están integradas físicamente/i);
  assert.match(report, /no puede cerrarse como integración completa/i);
});
