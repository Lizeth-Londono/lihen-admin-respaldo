import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizePhone, createWhatsAppUrl } from '../js/services/whatsapp-service.js';

test('normaliza un celular colombiano', () => {
  assert.equal(normalizePhone('316 285 6130'), '573162856130');
});

test('codifica el mensaje de WhatsApp', () => {
  const url = createWhatsAppUrl('3162856130', 'Hola LIHEN 🤎');
  assert.match(url, /^https:\/\/wa\.me\/573162856130\?text=/);
  assert.match(url, /Hola%20LIHEN/);
});
