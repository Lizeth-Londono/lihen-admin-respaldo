const text = (value) => String(value ?? '').trim();
const normalized = (value) => text(value).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\s+/g, ' ');
const numeric = (value) => {
  if (value === '' || value == null) return undefined;
  const parsed = Number(String(value).replace(/[^0-9,.-]/g, '').replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : Number.NaN;
};
const integer = (value) => {
  const parsed = numeric(value);
  return parsed === undefined ? undefined : Number.isInteger(parsed) ? parsed : Number.NaN;
};
const bool = (value) => {
  const n = normalized(value);
  if (!n) return undefined;
  if (['si','sí','true','1','yes'].includes(n)) return true;
  if (['no','false','0'].includes(n)) return false;
  return undefined;
};
const dateValue = (value) => {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value.toISOString().slice(0, 10);
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toISOString().slice(0, 10);
};

export const SUPPLIER_PURCHASE_TEMPLATE_VERSION = 'LIHEN-COMPRAS-PROVEEDORES-V1';
export const PURCHASE_HEADERS = ['Versión plantilla','ID compra','Clave compra','Tipo compra','Proveedor ID','Proveedor','Fecha compra','Número factura','Fecha esperada recepción','Fecha límite pago','Estado compra','Estado recepción','Estado pago','Subtotal','Descuento','Impuestos','Flete','Total','Valor pagado','Saldo pendiente','Medio de pago','Cuenta financiera','Fecha pago','Referencia pago','Origen registro','Observaciones','Impacto inventario','Impacto financiero'];
export const ITEM_HEADERS = ['ID detalle','ID compra','Clave compra','Proveedor','Producto ID','SKU','Producto','Categoría','Marca','Cantidad comprada','Cantidad recibida','Cantidad pendiente','Costo unitario','Subtotal','Producto asociado','Observaciones'];
export const PAYMENT_HEADERS = ['ID pago','ID compra','Clave compra','Proveedor','Fecha pago','Valor','Medio','Cuenta ID','Cuenta','Referencia','Estado','Pago histórico','Afecta saldo actual','Observaciones'];

export function buildPurchaseKey(row) {
  const explicit = text(row.purchase_key || row.operation_key);
  if (explicit) return explicit;
  return [normalized(row.supplier_name), dateValue(row.purchase_date), normalized(row.invoice_number), Number(row.total_amount || 0).toFixed(2), normalized(row.purchase_type)].join('|');
}

function indexData(context = {}) {
  return {
    suppliersById: new Map((context.suppliers || []).map(item => [String(item.id), item])),
    suppliersByName: new Map((context.suppliers || []).map(item => [normalized(item.business_name), item])),
    productsById: new Map((context.products || []).map(item => [String(item.id), item])),
    productsBySku: new Map((context.products || []).map(item => [normalized(item.sku), item])),
    accountsById: new Map((context.accounts || []).map(item => [String(item.id), item])),
    accountsByName: new Map((context.accounts || []).map(item => [normalized(item.name), item])),
    purchasesById: new Map((context.purchases || []).map(item => [String(item.id), item])),
    purchasesByKey: new Map((context.purchases || []).map(item => [String(item.operation_key || item.historical_operation_key || ''), item]).filter(([key]) => key))
  };
}

export function buildSupplierPurchaseImportPlan(rawPurchases = [], rawItems = [], rawPayments = [], context = {}) {
  const indexes = indexData(context);
  const issues = [];
  const purchaseRows = [];
  const purchaseByKey = new Map();

  for (const source of rawPurchases) {
    const row = { ...source };
    row.purchase_type = normalized(row.purchase_type).startsWith('hist') ? 'historica' : normalized(row.purchase_type).startsWith('act') ? 'actual' : '';
    row.purchase_date = dateValue(row.purchase_date);
    row.total_amount = numeric(row.total_amount);
    row.discount_amount = numeric(row.discount_amount) ?? 0;
    row.tax_amount = numeric(row.tax_amount) ?? 0;
    row.freight_amount = numeric(row.freight_amount) ?? 0;
    row.amount_paid = numeric(row.amount_paid) ?? 0;
    row.inventory_impact = bool(row.inventory_impact);
    row.financial_impact = bool(row.financial_impact);
    const rowIssues = [];
    const supplierById = row.supplier_id ? indexes.suppliersById.get(String(row.supplier_id)) : null;
    const supplierByName = row.supplier_name ? indexes.suppliersByName.get(normalized(row.supplier_name)) : null;
    if (supplierById && supplierByName && supplierById.id !== supplierByName.id) rowIssues.push({ severity:'error', field:'Proveedor', reason:'El ID y el nombre pertenecen a proveedores distintos.' });
    row.supplier = supplierById || supplierByName;
    if (!row.supplier) rowIssues.push({ severity:'error', field:'Proveedor', reason:'No se encontró el proveedor registrado.' });
    if (!row.purchase_type) rowIssues.push({ severity:'error', field:'Tipo compra', reason:'Debe ser Histórica o Actual.' });
    if (!row.purchase_date) rowIssues.push({ severity:'error', field:'Fecha compra', reason:'La fecha es obligatoria y debe ser válida.' });
    if (!Number.isFinite(row.total_amount) || row.total_amount < 0) rowIssues.push({ severity:'error', field:'Total', reason:'El total debe ser un número igual o mayor que cero.' });
    if (row.amount_paid > row.total_amount) rowIssues.push({ severity:'error', field:'Valor pagado', reason:'El valor pagado no puede superar el total.' });
    if (row.purchase_type === 'historica' && (row.inventory_impact === true || row.financial_impact === true)) rowIssues.push({ severity:'error', field:'Impactos', reason:'Una compra histórica no puede afectar inventario ni caja actual.' });
    row.inventory_impact = row.purchase_type === 'historica' ? false : row.inventory_impact !== false;
    row.financial_impact = row.purchase_type === 'historica' ? false : row.financial_impact !== false;
    row.purchase_key = buildPurchaseKey({ ...row, supplier_name: row.supplier?.business_name || row.supplier_name });
    const current = (row.purchase_id && indexes.purchasesById.get(String(row.purchase_id))) || indexes.purchasesByKey.get(row.purchase_key) || null;
    row.action = current ? 'update' : 'create';
    row.current = current;
    if (purchaseByKey.has(row.purchase_key)) rowIssues.push({ severity:'error', field:'Clave compra', reason:'La compra está repetida dentro del archivo.' });
    purchaseByKey.set(row.purchase_key, row);
    row.issues = rowIssues;
    issues.push(...rowIssues.map(item => ({ ...item, sheet:'Compras', row_number:row.row_number, purchase_key:row.purchase_key })));
    purchaseRows.push(row);
  }

  const itemRows = rawItems.map(source => {
    const row = { ...source };
    const rowIssues = [];
    const purchase = purchaseByKey.get(text(row.purchase_key)) || purchaseRows.find(item => row.purchase_id && String(item.purchase_id || item.current?.id) === String(row.purchase_id));
    if (!purchase) rowIssues.push({ severity:'error', field:'Compra', reason:'No se encontró la compra relacionada en la hoja Compras.' });
    const productById = row.product_id ? indexes.productsById.get(String(row.product_id)) : null;
    const productBySku = row.sku ? indexes.productsBySku.get(normalized(row.sku)) : null;
    if (productById && productBySku && productById.id !== productBySku.id) rowIssues.push({ severity:'error', field:'Producto', reason:'El ID y el SKU pertenecen a productos distintos.' });
    row.product = productById || productBySku;
    if (!row.product) rowIssues.push({ severity:'error', field:'Producto', reason:'No se encontró una coincidencia exacta por ID o SKU.' });
    row.quantity_requested = integer(row.quantity_requested);
    row.quantity_received = integer(row.quantity_received) ?? 0;
    row.unit_cost = numeric(row.unit_cost);
    if (!Number.isInteger(row.quantity_requested) || row.quantity_requested <= 0) rowIssues.push({ severity:'error', field:'Cantidad comprada', reason:'Debe ser un entero mayor que cero.' });
    if (!Number.isInteger(row.quantity_received) || row.quantity_received < 0 || row.quantity_received > row.quantity_requested) rowIssues.push({ severity:'error', field:'Cantidad recibida', reason:'Debe estar entre cero y la cantidad comprada.' });
    if (!Number.isFinite(row.unit_cost) || row.unit_cost < 0) rowIssues.push({ severity:'error', field:'Costo unitario', reason:'Debe ser un número igual o mayor que cero.' });
    row.purchase = purchase;
    row.issues = rowIssues;
    issues.push(...rowIssues.map(item => ({ ...item, sheet:'Productos de compra', row_number:row.row_number, sku:row.sku })));
    return row;
  });

  for (const purchase of purchaseRows) {
    purchase.items = itemRows.filter(item => item.purchase === purchase);
    if (!purchase.items.length) {
      const issue = { severity:'error', field:'Productos', reason:'La compra debe tener al menos un producto.', sheet:'Compras', row_number:purchase.row_number };
      purchase.issues.push(issue); issues.push(issue);
    }
    const computed = purchase.items.reduce((sum, item) => sum + Number(item.quantity_requested || 0) * Number(item.unit_cost || 0), 0) - Number(purchase.discount_amount || 0) + Number(purchase.tax_amount || 0) + Number(purchase.freight_amount || 0);
    if (Number.isFinite(purchase.total_amount) && Math.abs(computed - purchase.total_amount) > 1) {
      const issue = { severity:'warning', field:'Total', reason:`El total calculado es ${computed} y el archivo indica ${purchase.total_amount}.`, sheet:'Compras', row_number:purchase.row_number };
      purchase.issues.push(issue); issues.push(issue);
    }
  }

  const paymentRows = rawPayments.map(source => {
    const row = { ...source };
    const rowIssues = [];
    const purchase = purchaseByKey.get(text(row.purchase_key)) || purchaseRows.find(item => row.purchase_id && String(item.purchase_id || item.current?.id) === String(row.purchase_id));
    if (!purchase) rowIssues.push({ severity:'error', field:'Compra', reason:'No se encontró la compra relacionada.' });
    row.amount = numeric(row.amount);
    if (!Number.isFinite(row.amount) || row.amount <= 0) rowIssues.push({ severity:'error', field:'Valor', reason:'El pago debe ser mayor que cero.' });
    row.historical = bool(row.historical_payment) ?? purchase?.purchase_type === 'historica';
    row.affects_current_balance = bool(row.affects_current_balance) ?? !row.historical;
    if (row.historical && row.affects_current_balance) rowIssues.push({ severity:'error', field:'Afecta saldo actual', reason:'Un pago histórico no puede afectar la caja actual.' });
    const account = (row.account_id && indexes.accountsById.get(String(row.account_id))) || (row.account_name && indexes.accountsByName.get(normalized(row.account_name))) || null;
    if (!row.historical && !account) rowIssues.push({ severity:'error', field:'Cuenta', reason:'Los pagos actuales requieren una cuenta financiera válida.' });
    row.account = account; row.purchase = purchase; row.payment_date = dateValue(row.payment_date); row.issues = rowIssues;
    issues.push(...rowIssues.map(item => ({ ...item, sheet:'Pagos', row_number:row.row_number })));
    return row;
  });

  for (const purchase of purchaseRows) purchase.payments = paymentRows.filter(payment => payment.purchase === purchase);
  const errorCount = issues.filter(item => item.severity === 'error').length;
  return {
    purchases: purchaseRows,
    items: itemRows,
    payments: paymentRows,
    issues,
    summary: {
      total: purchaseRows.length,
      create: purchaseRows.filter(item => item.action === 'create').length,
      update: purchaseRows.filter(item => item.action === 'update').length,
      historical: purchaseRows.filter(item => item.purchase_type === 'historica').length,
      current: purchaseRows.filter(item => item.purchase_type === 'actual').length,
      products: itemRows.length,
      payments: paymentRows.length,
      warnings: issues.filter(item => item.severity === 'warning').length,
      errors: errorCount
    },
    valid: errorCount === 0
  };
}

export function buildSupplierPurchaseBatchPayload(plan, fileName, operationKey) {
  if (!plan?.valid) throw new Error('La importación contiene errores y no puede aplicarse.');
  return {
    operation_key: operationKey,
    file_name: fileName,
    template_version: SUPPLIER_PURCHASE_TEMPLATE_VERSION,
    purchases: plan.purchases.map(purchase => ({
      action: purchase.action,
      purchase_id: purchase.current?.id || purchase.purchase_id || null,
      purchase_key: purchase.purchase_key,
      purchase_type: purchase.purchase_type,
      supplier_id: purchase.supplier.id,
      purchase_date: purchase.purchase_date,
      invoice_number: text(purchase.invoice_number) || null,
      expected_date: dateValue(purchase.expected_date) || null,
      due_date: dateValue(purchase.due_date) || null,
      status: text(purchase.status) || (purchase.purchase_type === 'historica' ? 'cerrada' : 'borrador'),
      reception_status: text(purchase.reception_status) || (purchase.purchase_type === 'historica' ? 'historica' : 'pendiente'),
      payment_status: text(purchase.payment_status) || (Number(purchase.amount_paid || 0) > 0 ? 'parcial' : 'pendiente'),
      discount_amount: Number(purchase.discount_amount || 0), tax_amount: Number(purchase.tax_amount || 0), freight_amount: Number(purchase.freight_amount || 0),
      total_amount: Number(purchase.total_amount || 0), amount_paid: Number(purchase.amount_paid || 0),
      source_reference: text(purchase.source_reference) || null, notes: text(purchase.notes) || null,
      inventory_impact: purchase.inventory_impact, financial_impact: purchase.financial_impact,
      items: purchase.items.map(item => ({ product_id:item.product.id, quantity_requested:item.quantity_requested, quantity_received:item.quantity_received, unit_cost:item.unit_cost, notes:text(item.notes)||null })),
      payments: purchase.payments.map(payment => ({ amount:payment.amount, payment_date:payment.payment_date || purchase.purchase_date, payment_method:text(payment.payment_method)||'otro', account_id:payment.account?.id||null, reference_number:text(payment.reference_number)||null, notes:text(payment.notes)||null, historical:payment.historical, affects_current_balance:payment.affects_current_balance }))
    }))
  };
}

export function rejectedSupplierPurchaseRows(plan) {
  return (plan?.issues || []).map(issue => ({ Hoja:issue.sheet, Fila:issue.row_number || '', Compra:issue.purchase_key || '', SKU:issue.sku || '', Campo:issue.field, Severidad:issue.severity, Motivo:issue.reason }));
}
