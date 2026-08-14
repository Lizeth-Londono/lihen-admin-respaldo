import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseInventorySheetRows } from '../js/services/inventory-workbook-service.js';
import { buildInventoryImportPlan, buildInventoryImportBatchPayload } from '../js/services/inventory-import-service.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const ui = read('js/supplier-purchases.js');
const repo = read('js/repositories/supplier-purchase-repository.js');
const reportRepo = read('js/repositories/report-repository.js');
const migration = read('sql/046_compras_proveedor_pago_externo_y_estados.sql');

const headers = ['ID interno','SKU','Línea de negocio','Categoría / tipo','Subcategoría','Producto','Marca','Proveedor','Descripción','Costo real unitario','Precio sugerido LIHEN','Stock actual','Stock reservado','Stock disponible','Stock pendiente','Stock mínimo','Visible en catálogo','Estado producto','Código catálogo'];
const st006 = [null,'ST-006','Style','Online','Perfunme','Fragancia LIHEN','Online','KJ Parfums','Se crea para legalizar la compra de las Fragancias para LIHEN',2600,3000,0,0,0,0,0,'No','Activo',null];

test('compra normal ofrece Confirmar compra como acción principal y conserva borrador secundario', () => {
  assert.match(ui, /value=\"draft\">Guardar borrador/);
  assert.match(ui, /value=\"confirm\">Confirmar compra/);
  assert.match(ui, /requestedAction === 'confirm'/);
  assert.match(ui, /confirmSupplierPurchase\(purchase\.id/);
});

test('confirmar compra no se presenta como recepción ni pago automático', () => {
  assert.match(ui, /Confirmarla no descuenta dinero ni aumenta el inventario físico/);
  assert.match(ui, /Recibir mercancía/);
  assert.match(ui, /Registrar pago/);
});

test('pago permite elegir cuenta LIHEN o dinero personal externo', () => {
  assert.match(ui, /Cuenta de LIHEN/);
  assert.match(ui, /Dinero personal \/ externo/);
  assert.match(ui, /Pago fuera de caja LIHEN/);
});

test('pago externo no exige cuenta LIHEN y se envía como external', () => {
  assert.match(ui, /payment_source === 'external'/);
  assert.match(ui, /accountId: account\?\.id \|\| null/);
  assert.match(ui, /paymentSource: external \? 'external' : 'lihen'/);
  assert.match(repo, /register_supplier_payment_v2_atomic/);
});

test('RPC V2 solo crea movimiento financiero cuando payment_source es lihen', () => {
  assert.match(migration, /if v_source='lihen' then/);
  assert.match(migration, /insert into public\.financial_movements/);
  assert.match(migration, /Pago personal\/externo: jamás crear movimiento financiero LIHEN/);
  assert.match(migration, /financial_account_id is null and financial_movement_id is null/);
});

test('RPC V2 evita el literal inválido anulada contra supplier_request_status', () => {
  assert.doesNotMatch(migration, /v_purchase\.status\s+in\s*\([^)]*'anulada'/i);
  assert.match(migration, /v_purchase\.status::text = 'cancelada'/);
});

test('la RPC histórica de pago delega en V2 para compatibilidad', () => {
  assert.match(migration, /create or replace function public\.register_supplier_payment_atomic/);
  assert.match(migration, /return public\.register_supplier_payment_v2_atomic/);
  assert.match(migration, /'lihen'/);
});

test('recepción adapta el payload de UI al contrato real de la RPC', () => {
  assert.match(repo, /quantity: Number\(item\.quantity_received/);
  assert.match(repo, /unit_cost: Number\(item\.final_unit_cost/);
  assert.match(repo, /receive_supplier_purchase_v2_atomic/);
});

test('Reportes deja de consultar products.product_type inexistente', () => {
  assert.doesNotMatch(reportRepo, /product_type/);
  assert.match(reportRepo, /category,subcategory/);
});

test('Reportes usa nombres reales de cantidades de supplier_request_items', () => {
  assert.match(reportRepo, /quantity_requested,quantity_received,quoted_unit_cost/);
  assert.doesNotMatch(reportRepo, /requested_quantity,received_quantity/);
});

test('ST-006 del Excel se normaliza a status activo antes de importar', () => {
  const parsed = parseInventorySheetRows('Inventario', [headers, st006]);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].sku, 'ST-006');
  assert.equal(parsed[0].status, 'activo');
  assert.equal(parsed[0].visible_on_website, false);
  const plan = buildInventoryImportPlan(parsed, []);
  assert.equal(plan.rows[0].action, 'create');
  assert.equal(plan.rows[0].errors.length, 0);
  const payload = buildInventoryImportBatchPayload(plan, { sourceName: 'Inventario_Actual_LIHEN_2026-08-14.xlsx', operationKey: 'inventory-st006-test-20260814' });
  assert.equal(payload.p_rows[0].status, 'activo');
});

test('Inactivo/Oculto se normaliza al valor canónico oculto', () => {
  const inactive = [...st006];
  inactive[1] = 'ST-007';
  inactive[17] = 'Inactivo';
  const parsed = parseInventorySheetRows('Inventario', [headers, inactive]);
  assert.equal(parsed[0].status, 'oculto');
});
