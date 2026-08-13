import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const config = fs.readFileSync(new URL('../js/config.js', import.meta.url), 'utf8');
const supabaseClient = fs.readFileSync(new URL('../js/supabase.js', import.meta.url), 'utf8');
const authRepository = fs.readFileSync(new URL('../js/repositories/auth-repository.js', import.meta.url), 'utf8');
const store = fs.readFileSync(new URL('../js/store.js', import.meta.url), 'utf8');
const index = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');

function extract(regex, source, label) {
  const match = source.match(regex);
  assert.ok(match, `No se encontró ${label}`);
  return match[1];
}

test('configuración Supabase usa HTTPS y project ref válido', () => {
  const url = extract(/supabaseUrl:\s*['"]([^'"]+)['"]/, config, 'supabaseUrl');
  const parsed = new URL(url);
  assert.equal(parsed.protocol, 'https:');
  assert.match(parsed.hostname, /^[a-z0-9]{20}\.supabase\.co$/);
});

test('frontend usa Publishable Key y no contiene claves administrativas', () => {
  const key = extract(/supabasePublishableKey:\s*['"]([^'"]+)['"]/, config, 'supabasePublishableKey');
  assert.match(key, /^sb_publishable_[A-Za-z0-9_-]+$/);
  assert.doesNotMatch(config + supabaseClient, /sb_secret_|service[_-]?role/i);
});

test('cliente Supabase conserva sesión sin header global personalizado', () => {
  assert.match(supabaseClient, /persistSession:\s*true/);
  assert.match(supabaseClient, /autoRefreshToken:\s*true/);
  assert.match(supabaseClient, /detectSessionInUrl:\s*true/);
  assert.doesNotMatch(supabaseClient, /x-application-name/i);
  assert.doesNotMatch(supabaseClient, /global:\s*\{\s*headers/i);
});

test('login continúa usando signInWithPassword de Supabase Auth', () => {
  assert.match(authRepository, /supabase\.auth\.signInWithPassword\s*\(/);
  assert.match(store, /authRepository\.signInWithPassword\s*\(/);
});

test('recuperación de contraseña conserva redirect relativo al despliegue', () => {
  assert.match(store, /new URL\('\.\/', window\.location\.href\)\.href/);
});

test('GitHub Pages usa recursos relativos para el arranque', () => {
  assert.match(index, /src=["'](?:\.\/)?js\/main\.js(?:\?[^"']*)?["']/);
  assert.doesNotMatch(index, /src=["']\/js\/main\.js["']/);
});
