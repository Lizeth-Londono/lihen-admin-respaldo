import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const report = fs.readFileSync(new URL('../docs/FASE_25_CRITERIOS_ACEPTACION.md', import.meta.url), 'utf8');

test('fase 25 documenta los 24 criterios de aceptación', () => {
  for (let index = 1; index <= 24; index += 1) {
    assert.match(report, new RegExp(`\\| ${index} \\|`));
  }
});

test('fase 25 distingue validación local de validación en entorno real', () => {
  assert.match(report, /requiere validación en entorno real/i);
  assert.match(report, /Supabase real/i);
  assert.match(report, /no debe declararse/i);
});

test('fase 25 exige diagnóstico de coherencia antes de publicar', () => {
  assert.match(report, /validate_lihen_schema_coherence/);
  assert.match(report, /ok = true/);
});
