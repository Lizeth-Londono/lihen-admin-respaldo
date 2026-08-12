import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const config = fs.readFileSync(new URL('../js/config.js', import.meta.url), 'utf8');
const integration = fs.readFileSync(new URL('../integracion-catalogo/catalogo-supabase.js', import.meta.url), 'utf8');

test('ADMIN y su integración de catálogo apuntan al mismo proyecto Supabase', () => {
  const urls = [...`${config}\n${integration}`.matchAll(/https:\/\/([a-z0-9]+)\.supabase\.co/gi)].map(m => m[1]);
  assert.ok(urls.length >= 2);
  assert.equal(new Set(urls).size, 1);
});

test('ADMIN usa solo una Publishable Key pública', () => {
  assert.match(config, /sb_publishable_[A-Za-z0-9_-]+/);
  assert.doesNotMatch(config, /sb_secret_[A-Za-z0-9_-]+/);
  assert.doesNotMatch(config, /service_role\s*[:=]\s*['"][^'"]+/i);
});
