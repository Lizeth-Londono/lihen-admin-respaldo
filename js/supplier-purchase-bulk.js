import { state, loadProducts, loadSuppliers, loadFinancialAccounts, loadSupplierPurchases } from './store.js';
import { $, escapeHtml, money } from './utils.js';
import { modal, closeModal, toast } from './ui.js';
import { confirmAction, moneyDetail } from './services/confirmation-service.js';
import { createOperationKey } from './services/operation-key-service.js';
import {
  SUPPLIER_PURCHASE_TEMPLATE_VERSION,
  PURCHASE_HEADERS,
  ITEM_HEADERS,
  PAYMENT_HEADERS,
  buildSupplierPurchaseImportPlan,
  buildSupplierPurchaseBatchPayload,
  rejectedSupplierPurchaseRows
} from './services/supplier-purchase-bulk-service.js';
import { fetchSupplierPurchaseExportData, importSupplierPurchasesBatch } from './repositories/supplier-purchase-bulk-repository.js';

let xlsxPromise;
async function ensureXlsx() {
  if (window.XLSX) return window.XLSX;
  if (!xlsxPromise) xlsxPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';
    script.onload = () => window.XLSX ? resolve(window.XLSX) : reject(new Error('No se pudo iniciar el módulo de Excel.'));
    script.onerror = () => reject(new Error('No se pudo cargar la librería de Excel. Revisa la conexión.'));
    document.head.appendChild(script);
  });
  return xlsxPromise;
}

const normalize = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ');
const safe = value => /^[=+@-]/.test(String(value ?? '')) ? `'${value}` : value ?? '';
const isoDate = value => value ? new Date(value).toISOString().slice(0,10) : '';
function headerMap(row = []) { const map={}; row.forEach((value,index)=>{ const key=normalize(value); if(key) map[key]=index; }); return map; }
function pick(row,map,names) { for(const name of names){ const index=map[normalize(name)]; if(index!==undefined) return row[index]; } return undefined; }
function rowsFrom(workbook, sheetName) {
  if (!workbook.SheetNames.includes(sheetName)) return [];
  const rows = window.XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], { header:1, defval:'', raw:true });
  const headerIndex = rows.findIndex(row => Object.keys(headerMap(row)).length > 2);
  if (headerIndex < 0) return [];
  const map = headerMap(rows[headerIndex]);
  return rows.slice(headerIndex + 1).map((row,index)=>({ row, map, row_number:headerIndex + index + 2 })).filter(entry=>entry.row.some(value=>String(value??'').trim()));
}

function parsePurchaseWorkbook(workbook) {
  const purchases = rowsFrom(workbook, 'Compras').map(({row,map,row_number}) => ({
    row_number,
    template_version: pick(row,map,['Versión plantilla','Version plantilla']),
    purchase_id: pick(row,map,['ID compra']), operation_key: pick(row,map,['Clave compra']), purchase_key: pick(row,map,['Clave compra']),
    purchase_type: pick(row,map,['Tipo compra']), supplier_id: pick(row,map,['Proveedor ID']), supplier_name: pick(row,map,['Proveedor']),
    purchase_date: pick(row,map,['Fecha compra']), invoice_number: pick(row,map,['Número factura','Numero factura']), expected_date:pick(row,map,['Fecha esperada recepción','Fecha esperada recepcion']), due_date:pick(row,map,['Fecha límite pago','Fecha limite pago']),
    status:pick(row,map,['Estado compra']), reception_status:pick(row,map,['Estado recepción','Estado recepcion']), payment_status:pick(row,map,['Estado pago']),
    subtotal:pick(row,map,['Subtotal']), discount_amount:pick(row,map,['Descuento']), tax_amount:pick(row,map,['Impuestos']), freight_amount:pick(row,map,['Flete']), total_amount:pick(row,map,['Total']), amount_paid:pick(row,map,['Valor pagado']), balance_due:pick(row,map,['Saldo pendiente']),
    payment_method:pick(row,map,['Medio de pago']), account_name:pick(row,map,['Cuenta financiera']), payment_date:pick(row,map,['Fecha pago']), payment_reference:pick(row,map,['Referencia pago']), source_reference:pick(row,map,['Origen registro']), notes:pick(row,map,['Observaciones']), inventory_impact:pick(row,map,['Impacto inventario']), financial_impact:pick(row,map,['Impacto financiero'])
  }));
  const items = rowsFrom(workbook, 'Productos de compra').map(({row,map,row_number}) => ({
    row_number, detail_id:pick(row,map,['ID detalle']), purchase_id:pick(row,map,['ID compra']), purchase_key:pick(row,map,['Clave compra']), supplier_name:pick(row,map,['Proveedor']),
    product_id:pick(row,map,['Producto ID']), sku:pick(row,map,['SKU']), product_name:pick(row,map,['Producto']), category:pick(row,map,['Categoría','Categoria']), brand:pick(row,map,['Marca']),
    quantity_requested:pick(row,map,['Cantidad comprada']), quantity_received:pick(row,map,['Cantidad recibida']), quantity_pending:pick(row,map,['Cantidad pendiente']), unit_cost:pick(row,map,['Costo unitario']), subtotal:pick(row,map,['Subtotal']), associated:pick(row,map,['Producto asociado']), notes:pick(row,map,['Observaciones'])
  }));
  const payments = rowsFrom(workbook, 'Pagos').map(({row,map,row_number}) => ({
    row_number, payment_id:pick(row,map,['ID pago']), purchase_id:pick(row,map,['ID compra']), purchase_key:pick(row,map,['Clave compra']), supplier_name:pick(row,map,['Proveedor']), payment_date:pick(row,map,['Fecha pago']), amount:pick(row,map,['Valor']), payment_method:pick(row,map,['Medio']), account_id:pick(row,map,['Cuenta ID']), account_name:pick(row,map,['Cuenta']), reference_number:pick(row,map,['Referencia']), status:pick(row,map,['Estado']), historical_payment:pick(row,map,['Pago histórico','Pago historico']), affects_current_balance:pick(row,map,['Afecta saldo actual']), notes:pick(row,map,['Observaciones'])
  }));
  return { purchases, items, payments };
}

function sheetFromRows(XLSXLib, headers, rows) {
  const sheet = XLSXLib.utils.json_to_sheet(rows, { header:headers });
  sheet['!autofilter'] = { ref:`A1:${XLSXLib.utils.encode_col(headers.length-1)}${Math.max(1, rows.length+1)}` };
  sheet['!freeze'] = { xSplit:0, ySplit:1 };
  sheet['!cols'] = headers.map(header => ({ wch:Math.min(32, Math.max(12, header.length + 2)) }));
  return sheet;
}

function addInstructions(XLSXLib, workbook) {
  const rows = [
    ['Plantilla', SUPPLIER_PURCHASE_TEMPLATE_VERSION],
    ['Objetivo','Importar y actualizar compras históricas y actuales de todos los proveedores.'],
    ['Históricas','Deben tener Impacto inventario = No e Impacto financiero = No.'],
    ['Actuales','Respetan el flujo de borrador, confirmación, recepción y pago.'],
    ['Identificación','Use ID compra o Clave compra. Los productos se asocian por Producto ID o SKU exacto.'],
    ['Celdas vacías','No borran automáticamente valores existentes.'],
    ['Seguridad','No cambie los encabezados ni elimine las hojas Compras, Productos de compra y Pagos.']
  ];
  XLSXLib.utils.book_append_sheet(workbook, XLSXLib.utils.aoa_to_sheet(rows), 'Instrucciones');
}

function exportRows(data) {
  const purchases = data.purchases.map(p => ({
    'Versión plantilla':SUPPLIER_PURCHASE_TEMPLATE_VERSION, 'ID compra':safe(p.id), 'Clave compra':safe(p.operation_key || p.historical_operation_key || ''), 'Tipo compra':p.is_historical?'Histórica':'Actual', 'Proveedor ID':safe(p.supplier_id), 'Proveedor':safe(p.supplier?.business_name),
    'Fecha compra':isoDate(p.purchase_date || p.created_at), 'Número factura':safe(p.invoice_number), 'Fecha esperada recepción':isoDate(p.expected_date), 'Fecha límite pago':isoDate(p.due_date), 'Estado compra':safe(p.status), 'Estado recepción':safe(p.reception_status || p.receipt_status), 'Estado pago':safe(p.payment_status),
    'Subtotal':Number(p.subtotal_amount || 0), 'Descuento':Number(p.discount_amount || 0), 'Impuestos':Number(p.tax_amount || 0), 'Flete':Number(p.freight_amount || 0), 'Total':Number(p.total_amount || 0), 'Valor pagado':Number(p.amount_paid || p.historical_paid_amount || 0), 'Saldo pendiente':Number(p.balance_due || 0),
    'Medio de pago':safe(p.historical_payment_method), 'Cuenta financiera':'', 'Fecha pago':isoDate(p.historical_payment_date), 'Referencia pago':'', 'Origen registro':safe(p.source_reference), 'Observaciones':safe(p.notes), 'Impacto inventario':p.inventory_impact===false?'No':'Sí', 'Impacto financiero':p.financial_impact===false?'No':'Sí'
  }));
  const items = data.purchases.flatMap(p => (p.items || []).map(i => ({
    'ID detalle':safe(i.id), 'ID compra':safe(p.id), 'Clave compra':safe(p.operation_key || p.historical_operation_key || ''), 'Proveedor':safe(p.supplier?.business_name), 'Producto ID':safe(i.product_id), 'SKU':safe(i.product?.sku), 'Producto':safe(i.product?.name), 'Categoría':safe(i.product?.category), 'Marca':safe(i.product?.brand),
    'Cantidad comprada':Number(i.quantity_requested || 0), 'Cantidad recibida':Number(i.quantity_received || 0), 'Cantidad pendiente':Math.max(0, Number(i.quantity_requested||0)-Number(i.quantity_received||0)), 'Costo unitario':Number(i.quoted_unit_cost || i.final_unit_cost || 0), 'Subtotal':Number(i.quantity_requested||0)*Number(i.quoted_unit_cost||i.final_unit_cost||0), 'Producto asociado':'Sí', 'Observaciones':safe(i.notes)
  })));
  const payments = data.purchases.flatMap(p => (p.payments || []).map(pay => ({
    'ID pago':safe(pay.id), 'ID compra':safe(p.id), 'Clave compra':safe(p.operation_key || p.historical_operation_key || ''), 'Proveedor':safe(p.supplier?.business_name), 'Fecha pago':isoDate(pay.payment_date || pay.paid_at), 'Valor':Number(pay.amount || 0), 'Medio':safe(pay.payment_method), 'Cuenta ID':safe(pay.financial_account_id || pay.account_id), 'Cuenta':safe(pay.account?.name), 'Referencia':safe(pay.reference_number), 'Estado':safe(pay.status), 'Pago histórico':p.is_historical?'Sí':'No', 'Afecta saldo actual':p.is_historical?'No':'Sí', 'Observaciones':safe(pay.notes)
  })));
  const summaries = data.suppliers.map(s => {
    const list = data.purchases.filter(p => p.supplier_id === s.id);
    return { 'Proveedor ID':safe(s.id), 'Proveedor':safe(s.business_name), 'Contacto':safe(s.contact_name), 'WhatsApp':safe(s.whatsapp), 'Ciudad':safe(s.city), 'Compras totales':list.length, 'Compras históricas':list.filter(p=>p.is_historical).length, 'Compras actuales':list.filter(p=>!p.is_historical).length, 'Total comprado':list.reduce((sum,p)=>sum+Number(p.total_amount||0),0), 'Total pagado':list.reduce((sum,p)=>sum+Number(p.amount_paid||p.historical_paid_amount||0),0), 'Saldo pendiente':list.reduce((sum,p)=>sum+Number(p.balance_due||0),0), 'Última compra':list.map(p=>isoDate(p.purchase_date)).sort().pop()||'', 'Productos asociados':s.supplier_products?.length||0 };
  });
  return { purchases, items, payments, summaries };
}

export async function exportSupplierPurchaseConsolidated({ empty=false }={}) {
  const XLSXLib = await ensureXlsx();
  const workbook = XLSXLib.utils.book_new(); addInstructions(XLSXLib, workbook);
  const data = empty ? { purchases:[], suppliers:state.suppliers, accounts:[] } : await fetchSupplierPurchaseExportData();
  const rows = exportRows(data);
  XLSXLib.utils.book_append_sheet(workbook, sheetFromRows(XLSXLib, PURCHASE_HEADERS, rows.purchases), 'Compras');
  XLSXLib.utils.book_append_sheet(workbook, sheetFromRows(XLSXLib, ITEM_HEADERS, rows.items), 'Productos de compra');
  XLSXLib.utils.book_append_sheet(workbook, sheetFromRows(XLSXLib, PAYMENT_HEADERS, rows.payments), 'Pagos');
  XLSXLib.utils.book_append_sheet(workbook, XLSXLib.utils.json_to_sheet(rows.summaries), 'Resumen proveedores');
  const catalogs = [['Tipo','Valor'],['Tipo compra','Histórica'],['Tipo compra','Actual'],['Estado compra','borrador'],['Estado compra','confirmada'],['Estado compra','cerrada'],['Estado pago','pendiente'],['Estado pago','parcial'],['Estado pago','pagada'],['Sí/No','Sí'],['Sí/No','No']];
  XLSXLib.utils.book_append_sheet(workbook, XLSXLib.utils.aoa_to_sheet(catalogs), 'Catálogos');
  XLSXLib.writeFile(workbook, empty ? 'Plantilla_Compras_Proveedores_LIHEN.xlsx' : `Consolidado_Compras_Proveedores_LIHEN_${new Date().toISOString().slice(0,10)}.xlsx`);
  toast(empty ? 'Plantilla vacía descargada.' : `Consolidado exportado: ${rows.purchases.length} compras.`);
}

function preview(plan) {
  const s=plan.summary;
  const issueRows=plan.issues.slice(0,100).map(i=>`<tr><td>${escapeHtml(i.sheet)}</td><td>${escapeHtml(i.row_number||'')}</td><td>${escapeHtml(i.field)}</td><td>${escapeHtml(i.reason)}</td><td>${escapeHtml(i.severity)}</td></tr>`).join('');
  return `<div class="import-summary"><div><b>${s.total}</b><span>Compras</span></div><div><b>${s.historical}</b><span>Históricas</span></div><div><b>${s.current}</b><span>Actuales</span></div><div><b>${s.products}</b><span>Productos</span></div><div><b>${s.payments}</b><span>Pagos</span></div><div><b>${s.errors}</b><span>Errores</span></div></div>
  <div class="callout"><b>Impacto controlado</b><p>Las compras históricas no modificarán inventario ni saldos actuales. Las compras actuales seguirán sus estados de recepción y pago.</p></div>
  ${plan.issues.length?`<div class="preview-table"><table><thead><tr><th>Hoja</th><th>Fila</th><th>Campo</th><th>Detalle</th><th>Nivel</th></tr></thead><tbody>${issueRows}</tbody></table></div>`:'<div class="alert success">El archivo no presenta errores críticos.</div>'}`;
}

async function downloadRejected(plan) {
  const rows=rejectedSupplierPurchaseRows(plan); if(!rows.length) throw new Error('No hay filas rechazadas.');
  const XLSXLib=await ensureXlsx(); const workbook=XLSXLib.utils.book_new(); XLSXLib.utils.book_append_sheet(workbook,XLSXLib.utils.json_to_sheet(rows),'Filas rechazadas'); XLSXLib.writeFile(workbook,'Compras_Proveedores_Filas_Rechazadas.xlsx');
}

export async function importSupplierPurchases() {
  await Promise.all([loadSuppliers(), loadProducts(), loadFinancialAccounts(), loadSupplierPurchases()]);
  modal('Importar compras de proveedores', `<div class="import-wizard"><div class="callout"><b>Plantilla oficial ${SUPPLIER_PURCHASE_TEMPLATE_VERSION}</b><p>Puede contener compras históricas y actuales. La vista previa se debe revisar antes de aplicar.</p></div><label class="file-drop">Seleccionar Excel<input id="supplierPurchasesFile" type="file" accept=".xlsx,.xls"></label><div id="supplierPurchaseImportPreview"></div><div class="form-actions"><button class="button ghost" data-close-modal>Cancelar</button><button class="button secondary" id="downloadSupplierPurchaseErrors" disabled>Descargar errores</button><button class="button primary" id="runSupplierPurchaseImport" disabled>Confirmar importación masiva</button></div></div>`, { wide:true });
  let plan=null; let sourceName='';
  $('#supplierPurchasesFile').addEventListener('change', async event => {
    try {
      const file=event.target.files[0]; if(!file) return; sourceName=file.name;
      const XLSXLib=await ensureXlsx(); const workbook=XLSXLib.read(await file.arrayBuffer(),{type:'array',cellDates:true});
      const parsed=parsePurchaseWorkbook(workbook);
      plan=buildSupplierPurchaseImportPlan(parsed.purchases,parsed.items,parsed.payments,{suppliers:state.suppliers,products:state.products,accounts:state.financialAccounts,purchases:state.supplierPurchases});
      $('#supplierPurchaseImportPreview').innerHTML=preview(plan);
      $('#runSupplierPurchaseImport').disabled=!plan.valid||!plan.summary.total;
      $('#downloadSupplierPurchaseErrors').disabled=!plan.issues.length;
    } catch(error) { toast(error.message,'danger'); }
  });
  $('#downloadSupplierPurchaseErrors').addEventListener('click',()=>downloadRejected(plan).catch(error=>toast(error.message,'danger')));
  $('#runSupplierPurchaseImport').addEventListener('click',async event=>{
    if(!plan?.valid) return;
    const historicalTotal=plan.purchases.filter(p=>p.purchase_type==='historica').reduce((sum,p)=>sum+Number(p.total_amount||0),0);
    const currentTotal=plan.purchases.filter(p=>p.purchase_type==='actual').reduce((sum,p)=>sum+Number(p.total_amount||0),0);
    const accepted=await confirmAction({title:'Confirmar importación masiva',message:'Se aplicará el lote completo. Las históricas tendrán impacto cero; las actuales respetarán sus estados.',confirmLabel:'Confirmar importación masiva',tone:'warning',details:[{label:'Compras históricas',value:plan.summary.historical},{label:'Compras actuales',value:plan.summary.current},moneyDetail('Total histórico',historicalTotal),moneyDetail('Total actual',currentTotal),{label:'Errores',value:plan.summary.errors}]});
    if(!accepted)return;
    const button=event.currentTarget; button.disabled=true; button.textContent='Procesando lote…';
    try { const payload=buildSupplierPurchaseBatchPayload(plan,sourceName,createOperationKey('importar_compras_proveedores')); const result=await importSupplierPurchasesBatch(payload); closeModal(); toast(`Importación completa: ${result?.created||0} creadas, ${result?.updated||0} actualizadas.`); document.dispatchEvent(new CustomEvent('lihen:refresh')); }
    catch(error){ button.disabled=false; button.textContent='Confirmar importación masiva'; toast(error.message,'danger'); }
  });
}

export const downloadSupplierPurchaseTemplate = () => exportSupplierPurchaseConsolidated({empty:true});
