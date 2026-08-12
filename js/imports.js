import { supabase } from './supabase.js';
import { state, loadProducts, loadSuppliers, loadCustomers } from './store.js';
import { $, escapeHtml } from './utils.js';
import { modal, closeModal, toast } from './ui.js';
import { buildInventoryImportPlan, buildRejectedRows, getInventoryImportChangeLabels, buildInventoryImportBatchPayload, createInventoryImportOperationKey } from './services/inventory-import-service.js';
import { importInventoryBatchAtomic } from './repositories/inventory-import-repository.js';
import { confirmAction } from './services/confirmation-service.js';
import { parseInventoryWorkbookData, INVENTORY_TEMPLATE_VERSION } from './services/inventory-workbook-service.js';

const normalize=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ');
const number=v=>{if(v==null||v==='')return 0;const n=Number(String(v).replace(/[^0-9,.-]/g,'').replace(',','.'));return Number.isFinite(n)?n:0;};
let xlsxLoadPromise = null;
async function ensureXlsx(){
  if(window.XLSX) return window.XLSX;
  if(!xlsxLoadPromise){
    xlsxLoadPromise = new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.src='https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';
      script.async=true;
      script.onload=()=>window.XLSX?resolve(window.XLSX):reject(new Error('El lector de Excel no quedó disponible.'));
      script.onerror=()=>reject(new Error('No se pudo cargar el lector de Excel. Revisa la conexión e inténtalo nuevamente.'));
      document.head.appendChild(script);
    }).catch(error=>{xlsxLoadPromise=null;throw error;});
  }
  return xlsxLoadPromise;
}
async function workbookFromFile(file){const XLSXLib=await ensureXlsx();const buffer=await file.arrayBuffer();return XLSXLib.read(buffer,{type:'array',cellDates:true});}
function rowsFromSheet(workbook,name){return XLSX.utils.sheet_to_json(workbook.Sheets[name],{header:1,defval:null,raw:true});}
async function audit(action,newData){try{await supabase.from('audit_logs').insert({user_id:state.profile.id,action,entity_type:'importacion',new_data:newData});}catch(error){console.warn(error);}}

function parseInventoryWorkbook(workbook){
 const parsed=parseInventoryWorkbookData(workbook,rowsFromSheet);
 return parsed.rows;
}

function actionLabel(action){return ({create:'Crear',update:'Actualizar',unchanged:'Sin cambios',error:'Error'})[action]||action;}
function formatPreviewValue(value){
 if(value===undefined||value===null||value==='')return '—';
 if(typeof value==='boolean')return value?'Sí':'No';
 return String(value);
}
function previewHtml(plan){
 const {summary}=plan;
 const rows=plan.rows;
 const errors=rows.filter(item=>item.errors.length);
 const warnings=rows.filter(item=>item.warnings.length);
 const detailRows=rows.slice(0,100).map(item=>{
  const changes=getInventoryImportChangeLabels(item);
  const validation=item.issues?.length
   ? item.issues.map(problem=>`<div class="import-issue ${problem.severity}"><b>${escapeHtml(problem.field_label)}:</b> ${escapeHtml(problem.reason)}${problem.correction?`<small>Corrección: ${escapeHtml(problem.correction)}</small>`:''}</div>`).join('')
   : changes.length
     ? changes.map(change=>`<div class="import-change"><b>${escapeHtml(change.label)}:</b> ${escapeHtml(formatPreviewValue(change.before))} → ${escapeHtml(formatPreviewValue(change.after))}</div>`).join('')
     : 'Sin cambios';
  return `<tr class="import-row-${item.action}"><td>${item.row_number??''}</td><td>${escapeHtml(item.row.internal_id||'—')}<br><small>${escapeHtml(item.row.sku||'—')}</small></td><td>${escapeHtml(item.row.name||item.current?.name||'—')}</td><td><span class="status-pill ${item.action}">${escapeHtml(actionLabel(item.action))}</span></td><td>${validation}</td></tr>`;
 }).join('');
 const rejected=buildRejectedRows(plan);
 const rejectedTable=rejected.length?`<section class="import-rejected"><div class="section-heading"><div><h4>Filas rechazadas</h4><p>Detalle de los errores que deben corregirse antes de importar.</p></div><button type="button" class="button ghost" id="downloadRejectedRows">Descargar errores</button></div><div class="preview-table"><table><thead><tr><th>Fila</th><th>SKU</th><th>Campo</th><th>Valor recibido</th><th>Motivo</th><th>Corrección esperada</th></tr></thead><tbody>${rejected.slice(0,100).map(row=>`<tr><td>${escapeHtml(row.Fila)}</td><td>${escapeHtml(row.SKU||'—')}</td><td>${escapeHtml(row['Campo afectado'])}</td><td>${escapeHtml(formatPreviewValue(row['Valor recibido']))}</td><td>${escapeHtml(row['Motivo del error'])}</td><td>${escapeHtml(row['Corrección esperada'])}</td></tr>`).join('')}</tbody></table></div></section>`:'';
 return {rejected,html:`<div class="import-summary"><div><b>${summary.total}</b><span>Total de filas</span></div><div><b>${summary.create}</b><span>Productos nuevos</span></div><div><b>${summary.update}</b><span>Por actualizar</span></div><div><b>${summary.unchanged}</b><span>Sin cambios</span></div><div><b>${summary.warning}</b><span>Con advertencias</span></div><div><b>${summary.error}</b><span>Con errores</span></div></div><div class="import-change-summary"><span><b>${summary.stock_changes}</b> cambios de stock</span><span><b>${summary.cost_changes}</b> cambios de costo</span><span><b>${summary.price_changes}</b> cambios de precio</span><span><b>${summary.visibility_changes}</b> cambios de visibilidad</span></div>${warnings.length?`<div class="alert warning"><b>${warnings.length} filas con advertencias.</b> Se pueden importar, pero conviene revisarlas.</div>`:''}${errors.length?`<div class="alert danger"><b>No se puede importar todavía.</b> Corrige ${errors.length} filas con errores y vuelve a cargar el archivo.</div>`:''}<div class="preview-table"><table><thead><tr><th>Fila</th><th>ID / SKU</th><th>Producto</th><th>Acción</th><th>Cambios y validación</th></tr></thead><tbody>${detailRows}</tbody></table></div>${rows.length>100?`<p class="privacy">Vista previa de 100 de ${rows.length} filas. El resumen contempla todo el archivo.</p>`:''}${rejectedTable}`};
}

async function downloadRejectedRows(plan,sourceName='inventario'){
 const rejected=buildRejectedRows(plan);
 if(!rejected.length)throw new Error('No hay filas rechazadas para descargar.');
 const XLSXLib=await ensureXlsx();
 const workbook=XLSXLib.utils.book_new();
 const sheet=XLSXLib.utils.json_to_sheet(rejected);
 sheet['!cols']=[{wch:8},{wch:38},{wch:18},{wch:28},{wch:24},{wch:44},{wch:48},{wch:48}];
 if(sheet['!ref'])sheet['!autofilter']={ref:sheet['!ref']};
 XLSXLib.utils.book_append_sheet(workbook,sheet,'Errores');
 const safeBase=String(sourceName||'inventario').replace(/\.[^.]+$/,'').replace(/[^a-z0-9_-]+/gi,'_');
 XLSXLib.writeFile(workbook,`${safeBase}_FILAS_RECHAZADAS.xlsx`,{compression:true});
}

function bindRejectedDownload(plan,sourceName){
 const button=$('#downloadRejectedRows');
 if(!button)return;
 button.addEventListener('click',async()=>{button.disabled=true;try{await downloadRejectedRows(plan,sourceName);toast('Archivo de errores descargado.');}catch(error){toast(error.message,'danger');}finally{button.disabled=false;}});
}

async function runInventoryImport(plan,sourceName,button){
 if(!plan||plan.summary.error>0)throw new Error('Corrige las filas con errores antes de importar.');
 const operationKey=createInventoryImportOperationKey(sourceName,plan);
 const payload=buildInventoryImportBatchPayload(plan,{sourceName,operationKey});
 button.textContent='Aplicando importación segura…';
 const result=await importInventoryBatchAtomic(payload);
 const summary=result?.summary||result||{};
 return {
  created:Number(summary.created_rows??summary.created??0),
  updated:Number(summary.updated_rows??summary.updated??0),
  unchanged:Number(summary.unchanged_rows??summary.unchanged??plan.summary.unchanged??0),
  units:Number(summary.stock_units_after??summary.units??0),
  pendingSupplier:Number(summary.pending_supplier_links??0),
  batchId:result?.batch_id??summary.batch_id??null,
  idempotent:Boolean(result?.idempotent??false)
 };
}

function inventoryModal(title,description,loader){
 modal(title,`<div class="import-wizard"><div class="callout"><b>Actualización controlada por ID interno o SKU</b><p>${description}</p></div>${loader}<div id="inventoryPreview"></div><div class="form-actions"><button class="button ghost" data-close-modal>Cancelar</button><button class="button primary" id="runInventoryImport" disabled>Importar inventario</button></div></div>`,{wide:true});
}

export function importInventory(){
 inventoryModal('Importar o actualizar inventario',`El sistema reconoce la plantilla ${INVENTORY_TEMPLATE_VERSION}, identifica primero por ID interno válido y después por SKU. Las celdas vacías conservan el valor actual y los productos ausentes del archivo no se eliminan.`,`<label class="file-drop">Seleccionar archivo Excel<input id="inventoryFile" type="file" accept=".xlsx,.xls"></label>`);
 let plan=null;let sourceName='';
 $('#inventoryFile').addEventListener('change',async event=>{try{const file=event.target.files[0];if(!file)return;sourceName=file.name;const prepared=parseInventoryWorkbook(await workbookFromFile(file));await Promise.all([loadProducts(),loadSuppliers()]);plan=buildInventoryImportPlan(prepared,state.products,state.suppliers);const preview=previewHtml(plan);$('#inventoryPreview').innerHTML=preview.html;bindRejectedDownload(plan,sourceName);$('#runInventoryImport').disabled=!plan.summary.total||plan.summary.error>0;if(plan.summary.error)toast('Hay filas con errores. Descarga el detalle, corrígelas y vuelve a cargar el archivo.','danger');}catch(error){toast(error.message,'danger');}});
 $('#runInventoryImport').addEventListener('click',async()=>{const button=$('#runInventoryImport');const accepted=await confirmAction({title:'Aplicar actualización masiva de inventario',message:'Los cambios válidos se guardarán en Supabase y los ajustes de stock quedarán registrados. Revisa el resumen antes de continuar.',confirmLabel:'Aplicar importación',tone:'warning',details:[{label:'Archivo',value:sourceName||'Sin nombre'},{label:'Productos nuevos',value:plan?.summary?.create??0},{label:'Productos por actualizar',value:plan?.summary?.update??0},{label:'Cambios de stock',value:plan?.summary?.stock_changes??plan?.summary?.stockChanges??0},{label:'Filas sin cambios',value:plan?.summary?.unchanged??0}]});if(!accepted)return;button.disabled=true;try{const r=await runInventoryImport(plan,sourceName,button);closeModal();toast(`Importación completa: ${r.created} creados, ${r.updated} actualizados y ${r.unchanged} sin cambios`);document.dispatchEvent(new CustomEvent('lihen:refresh'));}catch(error){button.disabled=false;button.textContent='Importar inventario';toast(error.message,'danger');}});
}

export async function importBundledInventory(){
 modal('Inventario inicial migrado',`<div class="alert success"><b>El inventario inicial ya fue migrado a Supabase.</b><p>Por seguridad, el archivo local con costos, proveedores y existencias ya no se publica con el ADMIN. Para nuevas cargas utiliza <b>Importar nuevo Excel</b>, que aplica preview, validación y la RPC transaccional.</p></div><div class="form-actions"><button class="button primary" data-close-modal>Entendido</button></div>`);
}

function genericImport(kind){
 const cfg=kind==='suppliers'?{title:'Importar proveedores',load:loadSuppliers,table:'suppliers',key:'business_name',fields:{'nombre comercial':'business_name','proveedor':'business_name','persona de contacto':'contact_name','contacto':'contact_name','whatsapp':'whatsapp','telefono':'whatsapp','teléfono':'whatsapp','correo':'email','email':'email','ciudad':'city','dias entrega':'average_delivery_days','días entrega':'average_delivery_days','observaciones':'notes'}}:{title:'Importar clientes',load:loadCustomers,table:'customers',key:'whatsapp',fields:{'nombre':'full_name','nombre completo':'full_name','cliente':'full_name','whatsapp':'whatsapp','telefono':'whatsapp','teléfono':'whatsapp','correo':'email','email':'email','observaciones':'notes','notas':'notes'}};
 modal(cfg.title,`<div class="import-wizard"><div class="callout"><b>Excel o CSV</b><p>La primera fila debe contener los encabezados. Se mostrará una vista previa antes de guardar.</p></div><label class="file-drop">Seleccionar archivo<input id="genericFile" type="file" accept=".xlsx,.xls,.csv"></label><div id="genericPreview"></div><div class="form-actions"><button class="button ghost" data-close-modal>Cancelar</button><button class="button primary" id="runGenericImport" disabled>Importar</button></div></div>`,{wide:true});
 let data=[];
 $('#genericFile').addEventListener('change',async event=>{try{const file=event.target.files[0];if(!file)return;const wb=await workbookFromFile(file);const rows=rowsFromSheet(wb,wb.SheetNames[0]);const headers=(rows[0]||[]).map(h=>cfg.fields[normalize(h)]||null);data=rows.slice(1).filter(r=>r.some(Boolean)).map(row=>Object.fromEntries(headers.map((h,i)=>[h,row[i]]).filter(([h])=>h))).filter(r=>r[cfg.key]);$('#genericPreview').innerHTML=`<div class="alert success">Se detectaron <b>${data.length}</b> registros válidos.</div><div class="preview-table"><table><thead><tr>${Object.keys(data[0]||{}).map(h=>`<th>${escapeHtml(h)}</th>`).join('')}</tr></thead><tbody>${data.slice(0,10).map(r=>`<tr>${Object.keys(data[0]||{}).map(h=>`<td>${escapeHtml(r[h]??'')}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;$('#runGenericImport').disabled=!data.length;}catch(error){toast(error.message,'danger');}});
 $('#runGenericImport').addEventListener('click',async()=>{const accepted=await confirmAction({title:`Confirmar ${cfg.title.toLowerCase()}`,message:'Se crearán registros nuevos y se actualizarán coincidencias existentes. Revisa la cantidad antes de continuar.',confirmLabel:'Confirmar importación',tone:'warning',details:[{label:'Tipo',value:kind==='suppliers'?'Proveedores':'Clientes'},{label:'Registros detectados',value:data.length}]});if(!accepted)return;const button=$('#runGenericImport');button.disabled=true;button.textContent='Importando…';try{await cfg.load();const existing=kind==='suppliers'?new Map(state.suppliers.map(x=>[normalize(x.business_name),x])):new Map(state.customers.map(x=>[normalize(x.whatsapp),x]));let created=0,updated=0;for(const row of data){const key=normalize(row[cfg.key]);const current=existing.get(key);const payload={...row};if('average_delivery_days'in payload)payload.average_delivery_days=number(payload.average_delivery_days)||null;if(current){const {data:changed,error}=await supabase.from(cfg.table).update(payload).eq('id',current.id).select('id').maybeSingle();if(error)throw error;if(!changed)throw new Error('Supabase bloqueó la actualización. Ejecuta la Migración 007.');updated++;}else{const {data:createdRow,error}=await supabase.from(cfg.table).insert({...payload,created_by:state.profile.id}).select('id').single();if(error)throw error;existing.set(key,{id:createdRow.id,...payload});created++;}}await audit(`importar_${kind}`,{created,updated});closeModal();toast(`${created} creados y ${updated} actualizados`);document.dispatchEvent(new CustomEvent('lihen:refresh'));}catch(error){button.disabled=false;button.textContent='Importar';toast(error.message,'danger');}});
}
export const importSuppliers=()=>genericImport('suppliers');
export const importCustomers=()=>genericImport('customers');
