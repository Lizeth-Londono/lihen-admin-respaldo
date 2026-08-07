import test from 'node:test';
import assert from 'node:assert/strict';
import { parseInventoryWorkbookData, parseInventorySheetRows, INVENTORY_TEMPLATE_VERSION } from '../js/services/inventory-workbook-service.js';

const headers = ['ID interno','SKU','Línea de negocio','Categoría / tipo','Subcategoría','Producto','Marca','Proveedor','Descripción','Costo real unitario','Precio sugerido LIHEN','Stock actual','Stock reservado','Stock disponible','Stock pendiente','Stock mínimo','Visible en catálogo','Estado producto','Código catálogo'];
const row = ['p1','BC-064','Style','Accesorios Style','Anillo','Anillo corazon','Reina bella','Glow Belleza & Accesorios','Descripción',5400,8000,1,0,1,0,0,'No','Activo','28'];

test('reconoce la hoja Inventario y los 19 encabezados de LIHEN-INVENTARIO-V1', () => {
  const workbook = { SheetNames: ['Instrucciones','Inventario'], Sheets: {} };
  const data = {
    Instrucciones: [['Plantilla', INVENTORY_TEMPLATE_VERSION]],
    Inventario: [headers, row]
  };
  const parsed = parseInventoryWorkbookData(workbook, (_wb, name) => data[name]);
  assert.equal(parsed.version, INVENTORY_TEMPLATE_VERSION);
  assert.equal(parsed.rows.length, 1);
  assert.equal(parsed.rows[0].current_cost, 5400);
  assert.equal(parsed.rows[0].sale_price, 8000);
  assert.equal(parsed.rows[0].business_line, 'Style');
  assert.equal(parsed.rows[0].status, 'activo');
  assert.equal(parsed.rows[0].visible_on_website, false);
});

test('no redondea stock decimal: lo marca como inválido', () => {
  const decimalRow = [...row];
  decimalRow[11] = 1.5;
  const parsed = parseInventorySheetRows('Inventario', [headers, decimalRow]);
  assert.ok(Number.isNaN(parsed[0].physical_stock));
});

test('conserva un visible inválido para que la validación lo rechace', () => {
  const invalid = [...row];
  invalid[16] = 'Quizás';
  const parsed = parseInventorySheetRows('Inventario', [headers, invalid]);
  assert.equal(parsed[0].visible_on_website, 'Quizás');
});

test('rechaza una versión de plantilla incompatible', () => {
  const workbook = { SheetNames: ['Instrucciones','Inventario'], Sheets: {} };
  const data = { Instrucciones: [['Plantilla','OTRA-VERSION']], Inventario: [headers,row] };
  assert.throws(() => parseInventoryWorkbookData(workbook, (_wb, name) => data[name]), /no es compatible/i);
});
