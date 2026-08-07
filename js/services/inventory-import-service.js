const normalize = value => String(value ?? '')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .trim()
  .toLowerCase()
  .replace(/\s+/g, ' ');

const editableFields = [
  'sku', 'business_line', 'category', 'subcategory', 'name', 'brand',
  'supplier_name', 'description', 'current_cost', 'sale_price',
  'physical_stock', 'minimum_stock', 'visible_on_website', 'status', 'catalog_code'
];

function currentInventory(product) {
  return Array.isArray(product?.inventory) ? product.inventory[0] || {} : product?.inventory || {};
}

function currentValue(product, field) {
  if (field === 'physical_stock' || field === 'minimum_stock') {
    return field === 'physical_stock'
      ? Number(currentInventory(product).physical_stock ?? 0)
      : Number(product.minimum_stock ?? 0);
  }
  if (field === 'supplier_name') {
    const links = Array.isArray(product?.supplier_products) ? product.supplier_products : [];
    return links.find(link => link?.preferred)?.supplier?.business_name
      || links[0]?.supplier?.business_name
      || null;
  }
  return product?.[field] ?? null;
}

function comparable(value, field = '') {
  if (value === undefined) return '__UNDEFINED__';
  if (value === null) return null;
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (['status','business_line'].includes(field)) return normalize(value);
  return String(value).trim();
}


const FIELD_LABELS = Object.freeze({
  internal_id: 'ID interno', sku: 'SKU', business_line: 'Línea de negocio', category: 'Categoría',
  subcategory: 'Subcategoría', name: 'Producto', brand: 'Marca', supplier_name: 'Proveedor',
  description: 'Descripción', current_cost: 'Costo real unitario', sale_price: 'Precio de venta',
  physical_stock: 'Stock actual', minimum_stock: 'Stock mínimo', visible_on_website: 'Visible en catálogo',
  status: 'Estado producto', catalog_code: 'Código catálogo', reported_reserved_stock: 'Stock reservado', reported_available_stock: 'Stock disponible', reported_pending_stock: 'Stock pendiente'
});

function issue(field, value, reason, correction, severity = 'error') {
  return { field, field_label: FIELD_LABELS[field] || field, value, reason, correction, severity };
}

function addIssue(collection, issues, item) {
  issues.push(item);
  collection.push(`${item.field_label}: ${item.reason}`);
}

function validateRowValues(row, errors, warnings, issues) {
  for (const field of ['current_cost', 'sale_price']) {
    if (Object.prototype.hasOwnProperty.call(row, field) && (!Number.isFinite(row[field]) || row[field] < 0)) {
      addIssue(errors, issues, issue(field, row[field], 'Debe ser un número igual o mayor que cero.', 'Escribe un valor numérico válido, por ejemplo 15000.'));
    }
  }
  for (const field of ['physical_stock', 'minimum_stock']) {
    if (Object.prototype.hasOwnProperty.call(row, field) && (!Number.isInteger(row[field]) || row[field] < 0)) {
      addIssue(errors, issues, issue(field, row[field], 'Debe ser un número entero igual o mayor que cero.', 'Escribe un entero válido, por ejemplo 0, 5 o 20.'));
    }
  }
  if (Object.prototype.hasOwnProperty.call(row, 'visible_on_website') && typeof row.visible_on_website !== 'boolean') {
    addIssue(errors, issues, issue('visible_on_website', row.visible_on_website, 'El valor no se reconoce como visible u oculto.', 'Usa Sí/No, Visible/Oculto, TRUE/FALSE o 1/0.'));
  }
  if (row.status && !['activo', 'inactivo'].includes(normalize(row.status))) {
    addIssue(errors, issues, issue('status', row.status, 'El estado no es válido.', 'Usa únicamente Activo o Inactivo.'));
  }
  if (row.business_line && !['beauty care', 'style'].includes(normalize(row.business_line))) {
    const item = issue('business_line', row.business_line, 'La línea no coincide con Beauty Care o Style.', 'Corrige la línea o confirma que deba revisarse manualmente.', 'warning');
    warnings.push(`${item.field_label}: ${item.reason}`);
    issues.push(item);
  }
}

export function buildInventoryImportPlan(rows, products, suppliers = []) {
  const byId = new Map((products || []).map(product => [String(product.id), product]));
  const bySku = new Map((products || []).filter(product => product.sku).map(product => [normalize(product.sku), product]));
  const supplierByName = new Map((suppliers || []).filter(item => item?.active !== false).map(item => [normalize(item.business_name), item]));
  const seenIds = new Map();
  const seenSkus = new Map();
  const result = [];

  for (const row of rows || []) {
    const errors = [];
    const warnings = [];
    const issues = [];
    const rowNumber = row.row_number ?? null;
    const internalId = String(row.internal_id ?? '').trim();
    const sku = String(row.sku ?? '').trim();
    const normalizedSku = normalize(sku);

    validateRowValues(row, errors, warnings, issues);

    if (internalId) {
      if (seenIds.has(internalId)) addIssue(errors, issues, issue('internal_id', internalId, `Está repetido; también aparece en la fila ${seenIds.get(internalId)}.`, 'Deja el ID interno en una sola fila.'));
      else seenIds.set(internalId, rowNumber);
    }
    if (normalizedSku) {
      if (seenSkus.has(normalizedSku)) addIssue(errors, issues, issue('sku', sku, `Está repetido; también aparece en la fila ${seenSkus.get(normalizedSku)}.`, 'Usa un SKU único por fila o elimina la fila duplicada.'));
      else seenSkus.set(normalizedSku, rowNumber);
    }

    const productById = internalId ? byId.get(internalId) : null;
    const productBySku = normalizedSku ? bySku.get(normalizedSku) : null;

    if (productById && productBySku && String(productById.id) !== String(productBySku.id)) {
      addIssue(errors, issues, issue('sku', sku, 'El ID interno y el SKU pertenecen a productos diferentes.', 'Corrige el ID interno o el SKU para que ambos identifiquen el mismo producto.'));
    }

    const current = productById || productBySku || null;

    if (!current && !row.business_line) {
      addIssue(errors, issues, issue('business_line', row.business_line, 'Un producto nuevo debe indicar su línea de negocio.', 'Usa Beauty Care o Style.'));
    }

    if (current && Object.prototype.hasOwnProperty.call(row, 'physical_stock')) {
      const reserved = Number(currentInventory(current).reserved_stock ?? 0);
      if (Number.isFinite(row.physical_stock) && row.physical_stock < reserved) {
        addIssue(errors, issues, issue('physical_stock', row.physical_stock, `No puede quedar por debajo del stock reservado (${reserved}).`, `Usa un stock igual o mayor que ${reserved}.`));
      }
    }

    if (current) {
      const inventory = currentInventory(current);
      const protectedChecks = [
        ['reported_reserved_stock','Stock reservado',Number(inventory.reserved_stock ?? 0)],
        ['reported_available_stock','Stock disponible',Number(inventory.available_stock ?? Math.max(0, Number(inventory.physical_stock ?? 0) - Number(inventory.reserved_stock ?? 0)))],
        ['reported_pending_stock','Stock pendiente',Number(inventory.pending_stock ?? 0)]
      ];
      for (const [field, label, actual] of protectedChecks) {
        if (!Object.prototype.hasOwnProperty.call(row, field) || !Number.isFinite(row[field]) || row[field] === actual) continue;
        const item = issue(field, row[field], `${label} es informativo y no se sobrescribirá. El valor real en Supabase es ${actual}.`, 'No edites esta columna; el sistema la calcula automáticamente.', 'warning');
        warnings.push(`${label}: ${item.reason}`); issues.push(item);
      }
    }

    if (row.supplier_name) {
      const matchedSupplier = supplierByName.get(normalize(row.supplier_name));
      if (!matchedSupplier && suppliers.length) {
        const item = issue('supplier_name', row.supplier_name, 'No existe un proveedor activo con ese nombre exacto.', 'Corrige el nombre para que coincida con un proveedor registrado. El producto se importará sin cambiar su relación de proveedor.', 'warning');
        warnings.push(`${item.field_label}: ${item.reason}`); issues.push(item);
      } else if (matchedSupplier) {
        row.supplier_id = matchedSupplier.id;
      }
    }
    if (internalId && !productById && productBySku) {
      const item = issue('internal_id', internalId, 'El ID interno no existe; se identificó el producto mediante el SKU.', 'Puedes conservarlo vacío o reemplazarlo por el ID correcto.', 'warning');
      warnings.push(`${item.field_label}: ${item.reason}`); issues.push(item);
    }
    if (internalId && !productById && !productBySku) {
      const item = issue('internal_id', internalId, 'El ID interno no existe; la fila se tratará como producto nuevo.', 'Verifica que realmente sea un producto nuevo.', 'warning');
      warnings.push(`${item.field_label}: ${item.reason}`); issues.push(item);
    }

    if (!current && !sku) addIssue(errors, issues, issue('sku', sku, 'Un producto nuevo debe tener SKU.', 'Escribe un SKU único.'));
    if (!current && !String(row.name ?? '').trim()) addIssue(errors, issues, issue('name', row.name, 'Un producto nuevo debe tener nombre.', 'Escribe el nombre del producto.'));

    if (current && sku && normalize(current.sku) !== normalizedSku) {
      const owner = bySku.get(normalizedSku);
      if (owner && String(owner.id) !== String(current.id)) addIssue(errors, issues, issue('sku', sku, 'El nuevo SKU ya está asignado a otro producto.', 'Usa un SKU que no pertenezca a otro producto.'));
      else {
        const item = issue('sku', sku, 'La fila propone cambiar el SKU del producto identificado por ID.', 'Confirma que el cambio de SKU sea intencional.', 'warning');
        warnings.push(`${item.field_label}: ${item.reason}`); issues.push(item);
      }
    }

    const changes = {};
    if (current && !errors.length) {
      for (const field of editableFields) {
        if (!Object.prototype.hasOwnProperty.call(row, field) || row[field] === undefined) continue;
        if (comparable(row[field], field) !== comparable(currentValue(current, field), field)) {
          changes[field] = { before: currentValue(current, field), after: row[field] };
        }
      }
    }

    let action = 'error';
    if (!errors.length) action = current ? (Object.keys(changes).length ? 'update' : 'unchanged') : 'create';
    result.push({ row, row_number: rowNumber, current, action, changes, errors, warnings, issues });
  }

  const summary = {
    total: result.length,
    create: result.filter(item => item.action === 'create').length,
    update: result.filter(item => item.action === 'update').length,
    unchanged: result.filter(item => item.action === 'unchanged').length,
    error: result.filter(item => item.action === 'error').length,
    warning: result.filter(item => item.warnings.length > 0).length,
    stock_changes: result.filter(item => Object.hasOwn(item.changes, 'physical_stock')).length,
    cost_changes: result.filter(item => Object.hasOwn(item.changes, 'current_cost')).length,
    price_changes: result.filter(item => Object.hasOwn(item.changes, 'sale_price')).length,
    visibility_changes: result.filter(item => Object.hasOwn(item.changes, 'visible_on_website')).length
  };
  return { rows: result, summary };
}

export function buildRejectedRows(plan) {
  const rejected = [];
  for (const item of plan?.rows || []) {
    for (const problem of (item.issues || []).filter(entry => entry.severity === 'error')) {
      rejected.push({
        'Fila': item.row_number ?? '',
        'ID interno': item.row.internal_id ?? '',
        'SKU': item.row.sku ?? '',
        'Producto': item.row.name ?? item.current?.name ?? '',
        'Campo afectado': problem.field_label,
        'Valor recibido': problem.value ?? '',
        'Motivo del error': problem.reason,
        'Corrección esperada': problem.correction
      });
    }
  }
  return rejected;
}

export function getInventoryImportChangeLabels(item) {
  return Object.entries(item?.changes || {}).map(([field, values]) => ({
    field,
    label: FIELD_LABELS[field] || field,
    before: values.before,
    after: values.after
  }));
}

export function mergeExistingProduct(current, row, userId) {
  const payload = {
    sku: current.sku,
    name: current.name,
    business_line: current.business_line,
    category: current.category ?? null,
    subcategory: current.subcategory ?? null,
    brand: current.brand ?? null,
    description: current.description ?? null,
    current_cost: current.current_cost ?? null,
    sale_price: current.sale_price ?? 0,
    minimum_stock: current.minimum_stock ?? 0,
    visible_on_website: current.visible_on_website ?? false,
    status: current.status ?? 'activo',
    catalog_code: current.catalog_code ?? null,
    updated_by: userId
  };
  for (const field of editableFields) {
    if (['supplier_name', 'physical_stock'].includes(field)) continue;
    if (Object.prototype.hasOwnProperty.call(row, field) && row[field] !== undefined) payload[field] = row[field];
  }
  return payload;
}

export function buildNewProductPayload(row, userId) {
  return {
    sku: row.sku,
    name: row.name,
    business_line: row.business_line || 'Beauty Care',
    category: row.category ?? null,
    subcategory: row.subcategory ?? null,
    brand: row.brand ?? null,
    description: row.description ?? `${row.name}. Consulta disponibilidad por WhatsApp.`,
    current_cost: row.current_cost ?? null,
    sale_price: row.sale_price ?? 0,
    minimum_stock: row.minimum_stock ?? 0,
    visible_on_website: row.visible_on_website ?? false,
    status: row.status || 'activo',
    catalog_code: row.catalog_code ?? null,
    created_by: userId,
    updated_by: userId
  };
}

export const INVENTORY_IMPORT_EDITABLE_FIELDS = Object.freeze([...editableFields]);

export function buildInventoryImportBatchPayload(plan, { sourceName, operationKey } = {}) {
  if (!plan || !Array.isArray(plan.rows)) throw new Error('El plan de importación no es válido.');
  if (plan.summary?.error > 0) throw new Error('La importación contiene filas con errores.');
  const rows = plan.rows
    .filter(item => ['create', 'update'].includes(item.action))
    .map(item => ({
      row_number: item.row_number,
      action: item.action,
      product_id: item.current?.id ?? null,
      sku: item.row.sku ?? item.current?.sku ?? null,
      business_line: item.row.business_line,
      category: item.row.category,
      subcategory: item.row.subcategory,
      name: item.row.name,
      brand: item.row.brand,
      supplier_name: item.row.supplier_name,
      description: item.row.description,
      current_cost: item.row.current_cost,
      sale_price: item.row.sale_price,
      physical_stock: item.row.physical_stock,
      minimum_stock: item.row.minimum_stock,
      visible_on_website: item.row.visible_on_website,
      status: item.row.status,
      catalog_code: item.row.catalog_code
    }));
  return {
    p_source_file: String(sourceName || 'inventario.xlsx'),
    p_operation_key: String(operationKey || '').trim(),
    p_total_rows: Number(plan.summary?.total ?? plan.rows.length),
    p_unchanged_rows: Number(plan.summary?.unchanged ?? 0),
    p_rows: rows
  };
}

export function createInventoryImportOperationKey(sourceName, plan) {
  const signature = (plan?.rows || []).map(item => ({
    row: item.row_number,
    id: item.row?.internal_id ?? '',
    sku: item.row?.sku ?? '',
    action: item.action,
    changes: Object.fromEntries(Object.entries(item.changes || {}).sort(([a],[b]) => a.localeCompare(b)))
  }));
  let hash = 2166136261;
  const text = JSON.stringify({ source: sourceName || 'inventario', signature });
  for (let index = 0; index < text.length; index++) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `inventory-${(hash >>> 0).toString(16)}`;
}
