import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeConfirmationConfig, buildConfirmationMarkup, moneyDetail } from '../js/services/confirmation-service.js';

test('normaliza una confirmación crítica con valores seguros', () => {
  const result = normalizeConfirmationConfig({
    title: ' Anular venta ',
    message: ' Acción irreversible ',
    tone: 'danger',
    details: [{ label: 'Total', value: '$ 50.000' }, null, { label: '', value: 'x' }]
  });
  assert.equal(result.title, 'Anular venta');
  assert.equal(result.message, 'Acción irreversible');
  assert.equal(result.tone, 'danger');
  assert.deepEqual(result.details, [{ label: 'Total', value: '$ 50.000' }]);
});

test('rechaza tonos desconocidos y usa primary', () => {
  assert.equal(normalizeConfirmationConfig({ tone: 'neon' }).tone, 'primary');
});

test('el marcado escapa texto y expone un alertdialog accesible', () => {
  const html = buildConfirmationMarkup({
    title: '<script>alert(1)</script>',
    message: 'Aplicar cambios',
    details: [{ label: 'Archivo', value: '<b>datos.xlsx</b>' }]
  });
  assert.match(html, /role="alertdialog"/);
  assert.match(html, /aria-modal="true"/);
  assert.doesNotMatch(html, /<script>/);
  assert.doesNotMatch(html, /<b>datos\.xlsx<\/b>/);
});

test('moneyDetail devuelve un valor monetario legible', () => {
  const item = moneyDetail('Total', 150000);
  assert.equal(item.label, 'Total');
  assert.match(item.value, /150/);
});
