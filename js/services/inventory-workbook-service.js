export const INVENTORY_TEMPLATE_VERSION = 'LIHEN-INVENTARIO-V1';

export const INVENTORY_HEADERS = Object.freeze([
  'ID interno','SKU','Línea de negocio','Categoría / tipo','Subcategoría','Producto','Marca','Proveedor','Descripción',
  'Costo real unitario','Precio sugerido LIHEN','Stock actual','Stock reservado','Stock disponible','Stock pendiente',
  'Stock mínimo','Visible en catálogo','Estado producto','Código catálogo'
]);

const normalize = value => String(value ?? '')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .trim()
  .toLowerCase()
  .replace(/\s+/g, ' ');

function headerMap(row) {
  const map = {};
  (row || []).forEach((header, index) => {
    const key = normalize(header);
    if (key) map[key] = index;
  });
  return map;
}

function pick(row, map, names, fallback = undefined) {
  for (const name of names) {
    const index = map[normalize(name)];
    if (index !== undefined && row[index] !== undefined) return row[index];
  }
  return fallback;
}

function optionalNumber(value, { integer = false, minimum = null } = {}) {
  if (value == null || String(value).trim() === '') return undefined;
  const cleaned = String(value).replace(/[^0-9,.-]/g, '').replace(',', '.');
  const parsed = Number(cleaned);
  if (!Number.isFinite(parsed)) return Number.NaN;
  if (integer && !Number.isInteger(parsed)) return Number.NaN;
  if (minimum !== null && parsed < minimum) return Number.NaN;
  return parsed;
}

function optionalBoolean(value) {
  if (value == null || String(value).trim() === '') return undefined;
  const normalized = normalize(value);
  if (['si','true','1','visible'].includes(normalized)) return true;
  if (['no','false','0','oculto'].includes(normalized)) return false;
  return String(value).trim();
}

function canonicalStatus(value) {
  if (value == null || String(value).trim() === '') return undefined;
  const normalized = normalize(value);
  if (normalized === 'activo') return 'activo';
  if (normalized === 'inactivo') return 'inactivo';
  return String(value).trim();
}

function canonicalBusinessLine(value) {
  if (value == null || String(value).trim() === '') return undefined;
  const normalized = normalize(value);
  if (normalized === 'beauty care') return 'Beauty Care';
  if (normalized === 'style') return 'Style';
  return String(value).trim();
}

export function readInventoryTemplateVersion(workbook, rowsFromSheet) {
  if (!workbook?.SheetNames?.includes('Instrucciones')) return null;
  const rows = rowsFromSheet(workbook, 'Instrucciones');
  for (const row of rows || []) {
    if (normalize(row?.[0]) === 'plantilla') return String(row?.[1] ?? '').trim() || null;
  }
  return null;
}

export function parseInventorySheetRows(sheetName, rows) {
  const prepared = [];
  const headerIndex = (rows || []).findIndex(row => {
    const map = headerMap(row);
    return map[normalize('SKU')] !== undefined && map[normalize('Producto')] !== undefined;
  });
  if (headerIndex < 0) return prepared;

  const map = headerMap(rows[headerIndex]);
  for (let offset = headerIndex + 1; offset < rows.length; offset++) {
    const source = rows[offset] || [];
    const sku = String(pick(source, map, ['SKU'], '') || '').trim();
    const internalId = String(pick(source, map, ['ID interno','ID','Producto ID'], '') || '').trim();
    const name = String(pick(source, map, ['Producto','Nombre'], '') || '').trim();
    if (!sku && !internalId && !name) continue;
    if (normalize(sku) === 'totales') continue;

    const sheetBusinessLine = ['Beauty Care','Style'].includes(sheetName) ? sheetName : undefined;
    const parsed = {
      row_number: offset + 1,
      source_sheet: sheetName,
      internal_id: internalId || undefined,
      sku: sku || undefined,
      business_line: canonicalBusinessLine(sheetBusinessLine ?? pick(source, map, ['Línea de negocio','Linea de negocio'], undefined))
    };

    const textFields = [
      ['category',['Categoría / tipo','Categoria / tipo','Categoría','Categoria']],
      ['subcategory',['Subcategoría','Subcategoria']],
      ['name',['Producto','Nombre']],
      ['brand',['Marca']],
      ['supplier_name',['Proveedor','Proveedor principal']],
      ['description',['Descripción','Descripcion']],
      ['catalog_code',['Código catálogo','Codigo catalogo']]
    ];
    for (const [field, names] of textFields) {
      const value = pick(source, map, names, undefined);
      if (value !== undefined && String(value).trim() !== '') parsed[field] = String(value).trim();
    }

    const statusRaw = pick(source, map, ['Estado producto','Estado'], undefined);
    if (statusRaw !== undefined && String(statusRaw).trim() !== '') parsed.status = canonicalStatus(statusRaw);

    const numericFields = [
      ['current_cost',['Costo real unitario','Costo real unitario (COP)','Costo unitario'],false],
      ['sale_price',['Precio sugerido LIHEN','Precio sugerido LIHEN (COP)','Precio de venta'],false],
      ['physical_stock',['Stock actual','Stock físico','Stock fisico'],true],
      ['minimum_stock',['Stock mínimo','Stock minimo'],true],
      ['reported_reserved_stock',['Stock reservado'],true],
      ['reported_available_stock',['Stock disponible'],true],
      ['reported_pending_stock',['Stock pendiente'],true]
    ];
    for (const [field, names, integer] of numericFields) {
      const raw = pick(source, map, names, undefined);
      if (raw !== undefined && String(raw).trim() !== '') parsed[field] = optionalNumber(raw, { integer, minimum: 0 });
    }

    const visibleRaw = pick(source, map, ['Visible en catálogo','Visible en catalogo','Visible web'], undefined);
    if (visibleRaw !== undefined && String(visibleRaw).trim() !== '') parsed.visible_on_website = optionalBoolean(visibleRaw);
    prepared.push(parsed);
  }
  return prepared;
}

export function parseInventoryWorkbookData(workbook, rowsFromSheet) {
  if (!workbook || !Array.isArray(workbook.SheetNames)) throw new Error('El archivo Excel no es válido.');
  const version = readInventoryTemplateVersion(workbook, rowsFromSheet);
  if (version && version !== INVENTORY_TEMPLATE_VERSION) {
    throw new Error(`La plantilla ${version} no es compatible. Utiliza ${INVENTORY_TEMPLATE_VERSION}.`);
  }

  const recognized = ['Inventario','Beauty Care','Style','Otros'].filter(name => workbook.SheetNames.includes(name));
  if (!recognized.length) {
    throw new Error('No se encontró la hoja Inventario ni una hoja compatible de inventario.');
  }

  const rows = recognized.flatMap(name => parseInventorySheetRows(name, rowsFromSheet(workbook, name)));
  if (!rows.length) throw new Error('El archivo no contiene productos válidos para analizar.');
  return { version: version || null, rows, sheets: recognized };
}
