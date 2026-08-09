import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const css = fs.readFileSync(new URL('../css/app.css', import.meta.url), 'utf8');
const ui = fs.readFileSync(new URL('../js/ui.js', import.meta.url), 'utf8');
const confirmation = fs.readFileSync(new URL('../js/services/confirmation-service.js', import.meta.url), 'utf8');

function compact(value){ return value.replace(/\s+/g, ' '); }
const normalized = compact(css);

test('modal usa arquitectura flex y body desplazable dentro del viewport', () => {
  assert.match(normalized, /\.modal\{ display:flex; flex-direction:column; min-height:0; max-height:calc\(100dvh - 32px\); overflow:hidden;/);
  assert.match(normalized, /\.modal-body\{ flex:1 1 auto; min-height:0; overflow-y:auto; overflow-x:hidden;/);
  assert.match(normalized, /\.modal>header, \.modal>footer\{flex:0 0 auto\}/);
});

test('venta rápida mantiene accesibles sus acciones al crecer', () => {
  assert.match(normalized, /\.quick-sale-form \.form-actions\{ position:sticky; bottom:0;/);
  assert.match(normalized, /\.quick-sale-form \.sale-items-list\{ max-height:none; overflow:visible;/);
  assert.match(normalized, /\.order-editor \.order-builder\.compact\{ max-height:none!important; min-height:0; overflow:visible!important;/);
});

test('modal bloquea y restaura el scroll del documento', () => {
  assert.match(ui, /document\.body\.classList\.add\('modal-open'\)/);
  assert.match(ui, /document\.body\.classList\.remove\('modal-open'\)/);
  assert.match(normalized, /body\.modal-open, body\.confirmation-open\{overflow:hidden;overscroll-behavior:none\}/);
});

test('confirmaciones altas usan body interno desplazable', () => {
  assert.match(normalized, /\.confirmation-dialog\{ display:flex; flex-direction:column; min-height:0;/);
  assert.match(normalized, /\.confirmation-body\{ flex:1 1 auto; min-height:0; overflow-y:auto;/);
  assert.match(confirmation, /classList\.add\('confirmation-open'\)/);
  assert.match(confirmation, /classList\.remove\('confirmation-open'\)/);
});

test('sidebar preserva acceso a las opciones inferiores', () => {
  assert.match(normalized, /\.sidebar nav\{ flex:1 1 auto; min-height:0; overflow-y:auto;/);
  assert.match(normalized, /\.sidebar-footer\{flex:0 0 auto\}/);
});
