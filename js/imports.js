import { supabase } from './supabase.js';
import { state, loadProducts, loadSuppliers, loadCustomers } from './store.js';
import { $, escapeHtml } from './utils.js';
import { modal, closeModal, toast } from './ui.js';

const normalize=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ');
const number=v=>{if(v==null||v==='')return 0;const n=Number(String(v).replace(/[^0-9,.-]/g,'').replace(',','.'));return Number.isFinite(n)?n:0;};
function ensureXlsx(){if(!window.XLSX)throw new Error('No se pudo cargar el lector de Excel. Actualiza la página e inténtalo nuevamente.');}
async function workbookFromFile(file){ensureXlsx();const buffer=await file.arrayBuffer();return XLSX.read(buffer,{type:'array',cellDates:true});}
function rowsFromSheet(workbook,name){return XLSX.utils.sheet_to_json(workbook.Sheets[name],{header:1,defval:null,raw:true});}
async function audit(action,newData){try{await supabase.from('audit_logs').insert({user_id:state.profile.id,action,entity_type:'importacion',new_data:newData});}catch(error){console.warn(error);}}

function headerMap(row){const map={};(row||[]).forEach((h,i)=>{const k=normalize(h);if(k)map[k]=i;});return map;}
function pick(row,map,names,fallback){for(const name of names){const i=map[normalize(name)];if(i!==undefined&&row[i]!==undefined)return row[i];}return fallback;}
function parseInventoryWorkbook(wb){
 const prepared=[];
 for(const sheetName of ['Beauty Care','Style']){
  if(!wb.SheetNames.includes(sheetName))continue;
  const rows=rowsFromSheet(wb,sheetName);const headerIndex=rows.findIndex(row=>normalize(row?.[0])==='sku');if(headerIndex<0)continue;
  const map=headerMap(rows[headerIndex]);
  for(const row of rows.slice(headerIndex+1)){
   const sku=String(pick(row,map,['SKU'],'')||'').trim();
   const name=String(pick(row,map,['Producto'],'')||'').trim();
   if(!sku||!name||normalize(sku)==='totales')continue;
   prepared.push({sku,business_line:sheetName,category:pick(row,map,['Categoría / tipo','Categoria / tipo'],null),subcategory:pick(row,map,['Subcategoría','Subcategoria'],null),name,brand:pick(row,map,['Marca'],null),supplier_name:pick(row,map,['Proveedor'],null),current_cost:number(pick(row,map,['Costo real unitario (COP)'],0)),sale_price:number(pick(row,map,['Precio sugerido LIHEN (COP)'],0)),physical_stock:Math.max(0,Math.round(number(pick(row,map,['Stock actual'],0)))),minimum_stock:Math.max(0,Math.round(number(pick(row,map,['Stock mínimo','Stock minimo'],0)))),status_text:pick(row,map,['Estado inventario'],null)});
  }
 }
 return prepared;
}

function previewHtml(prepared,existing,supplierNames){
 const duplicates=prepared.filter((r,i,a)=>a.findIndex(x=>normalize(x.sku)===normalize(r.sku))!==i);
 const create=prepared.filter(r=>!existing.has(normalize(r.sku))).length;const update=prepared.length-create;
 const pending=[...new Set(prepared.map(r=>r.supplier_name).filter(Boolean).filter(n=>!supplierNames.has(normalize(n))))];
 return {duplicates,html:`<div class="import-summary"><div><b>${prepared.length}</b><span>Filas válidas</span></div><div><b>${create}</b><span>Productos nuevos</span></div><div><b>${update}</b><span>Por actualizar</span></div><div><b>${prepared.reduce((a,r)=>a+r.physical_stock,0)}</b><span>Unidades físicas</span></div></div>${pending.length?`<div class="alert warning"><b>${pending.length} proveedores pendientes:</b> ${escapeHtml(pending.slice(0,8).join(', '))}${pending.length>8?'…':''}. Se podrán relacionar después.</div>`:''}<div class="preview-table"><table><thead><tr><th>SKU</th><th>Producto</th><th>Línea</th><th>Stock</th><th>Precio</th><th>Acción</th></tr></thead><tbody>${prepared.slice(0,15).map(r=>`<tr><td>${escapeHtml(r.sku)}</td><td>${escapeHtml(r.name)}</td><td>${escapeHtml(r.business_line)}</td><td>${r.physical_stock}</td><td>${r.sale_price}</td><td>${existing.has(normalize(r.sku))?'Actualizar':'Crear'}</td></tr>`).join('')}</tbody></table></div>${prepared.length>15?`<p class="privacy">Vista previa de 15 de ${prepared.length} productos.</p>`:''}`};
}

async function runInventoryImport(prepared,sourceName,button){
 await Promise.all([loadProducts(),loadSuppliers()]);
 const existing=new Map(state.products.filter(p=>p.sku).map(p=>[normalize(p.sku),p]));
 const suppliers=new Map(state.suppliers.map(s=>[normalize(s.business_name),s]));
 let created=0,updated=0,units=0,pendingSupplier=0;
 for(let index=0;index<prepared.length;index++){
  const row=prepared[index];button.textContent=`Importando ${index+1} de ${prepared.length}…`;
  const current=existing.get(normalize(row.sku));
  const payload={sku:row.sku,name:row.name,business_line:row.business_line,category:row.category||null,brand:row.brand||null,current_cost:row.current_cost||null,sale_price:row.sale_price||0,minimum_stock:row.minimum_stock||0,status:current?.status||'activo',visible_on_website:current?.visible_on_website??false,description:current?.description||`${row.name}. Consulta disponibilidad por WhatsApp.`,updated_by:state.profile.id};
  let productId;
  if(current){const {data,error}=await supabase.from('products').update(payload).eq('id',current.id).select('id').maybeSingle();if(error)throw error;if(!data)throw new Error(`No se pudo actualizar ${row.sku}. Ejecuta la Migración 007.`);productId=current.id;updated++;}
  else{const {data,error}=await supabase.from('products').insert({...payload,created_by:state.profile.id}).select('id').single();if(error)throw error;productId=data.id;created++;existing.set(normalize(row.sku),{id:productId,...payload});}
  const {data:inv,error:iRead}=await supabase.from('inventory').select('id,physical_stock').eq('product_id',productId).maybeSingle();if(iRead)throw iRead;
  if(inv){const {data,error}=await supabase.from('inventory').update({physical_stock:row.physical_stock,updated_by:state.profile.id}).eq('id',inv.id).select('id').maybeSingle();if(error)throw error;if(!data)throw new Error(`No se pudo actualizar el inventario de ${row.sku}. Ejecuta la Migración 007.`);}
  else{const {error}=await supabase.from('inventory').insert({product_id:productId,physical_stock:row.physical_stock,updated_by:state.profile.id});if(error)throw error;}
  units+=row.physical_stock;
  const supplier=suppliers.get(normalize(row.supplier_name));
  if(supplier){
   const {data:rel,error:rError}=await supabase.from('supplier_products').select('id').eq('supplier_id',supplier.id).eq('product_id',productId).maybeSingle();if(rError)throw rError;
   if(rel){const {error}=await supabase.from('supplier_products').update({last_cost:row.current_cost||null,preferred:true}).eq('id',rel.id);if(error)throw error;}
   else{const {error}=await supabase.from('supplier_products').insert({supplier_id:supplier.id,product_id:productId,last_cost:row.current_cost||null,preferred:true});if(error)throw error;}
  }else if(row.supplier_name)pendingSupplier++;
 }
 await supabase.from('import_batches').insert({import_type:'inventario',source_file:sourceName,status:'completado',total_rows:prepared.length,created_rows:created,updated_rows:updated,summary:{units,pending_supplier_links:pendingSupplier},created_by:state.profile.id});
 await audit('importar_inventario',{source_file:sourceName,created,updated,units,pending_supplier_links:pendingSupplier});
 return {created,updated,units,pendingSupplier};
}

function inventoryModal(title,description,loader){
 modal(title,`<div class="import-wizard"><div class="callout"><b>Cargue masivo con control por SKU</b><p>${description}</p></div>${loader}<div id="inventoryPreview"></div><div class="form-actions"><button class="button ghost" data-close-modal>Cancelar</button><button class="button primary" id="runInventoryImport" disabled>Importar inventario</button></div></div>`,{wide:true});
}

export function importInventory(){
 inventoryModal('Importar inventario desde Excel','Selecciona cualquier versión futura del Excel. Los productos existentes se actualizan por SKU y los nuevos se crean.','<label class="file-drop">Seleccionar archivo Excel<input id="inventoryFile" type="file" accept=".xlsx,.xls"></label>');
 let prepared=[];let sourceName='';
 $('#inventoryFile').addEventListener('change',async event=>{try{const file=event.target.files[0];if(!file)return;sourceName=file.name;prepared=parseInventoryWorkbook(await workbookFromFile(file));await Promise.all([loadProducts(),loadSuppliers()]);const result=previewHtml(prepared,new Map(state.products.filter(p=>p.sku).map(p=>[normalize(p.sku),p])),new Set(state.suppliers.map(s=>normalize(s.business_name))));$('#inventoryPreview').innerHTML=result.html;$('#runInventoryImport').disabled=!prepared.length||result.duplicates.length>0;if(result.duplicates.length)toast('El archivo contiene SKU repetidos. Corrígelos antes de importar.','danger');}catch(error){toast(error.message,'danger');}});
 $('#runInventoryImport').addEventListener('click',async()=>{const button=$('#runInventoryImport');button.disabled=true;try{const r=await runInventoryImport(prepared,sourceName,button);closeModal();toast(`Importación completa: ${r.created} creados, ${r.updated} actualizados y ${r.units} unidades cargadas`);document.dispatchEvent(new CustomEvent('lihen:refresh'));}catch(error){button.disabled=false;button.textContent='Importar inventario';toast(error.message,'danger');}});
}

export async function importBundledInventory(){
 inventoryModal('Cargar inventario inicial de LIHEN','Este cargue viene incluido en el sistema y contiene todos los productos de Inventario_LIHEN_Corregido_Final.xlsx. Es seguro repetirlo: actualiza por SKU y no duplica.','<div class="alert success">Archivo integrado: <b>Inventario_LIHEN_Corregido_Final.xlsx</b></div>');
 try{
  const response=await fetch('data/inventario_inicial.json',{cache:'no-store'});if(!response.ok)throw new Error('No se pudo leer el inventario integrado.');const prepared=await response.json();
  await Promise.all([loadProducts(),loadSuppliers()]);const result=previewHtml(prepared,new Map(state.products.filter(p=>p.sku).map(p=>[normalize(p.sku),p])),new Set(state.suppliers.map(s=>normalize(s.business_name))));$('#inventoryPreview').innerHTML=result.html;const button=$('#runInventoryImport');button.disabled=!prepared.length;
  button.addEventListener('click',async()=>{button.disabled=true;try{const r=await runInventoryImport(prepared,'Inventario_LIHEN_Corregido_Final.xlsx (integrado)',button);closeModal();toast(`Inventario inicial cargado: ${r.created} creados, ${r.updated} actualizados y ${r.units} unidades físicas`);document.dispatchEvent(new CustomEvent('lihen:refresh'));}catch(error){button.disabled=false;button.textContent='Importar inventario';toast(error.message,'danger');}});
 }catch(error){$('#inventoryPreview').innerHTML=`<div class="alert danger">${escapeHtml(error.message)}</div>`;}
}

function genericImport(kind){
 const cfg=kind==='suppliers'?{title:'Importar proveedores',load:loadSuppliers,table:'suppliers',key:'business_name',fields:{'nombre comercial':'business_name','proveedor':'business_name','persona de contacto':'contact_name','contacto':'contact_name','whatsapp':'whatsapp','telefono':'whatsapp','teléfono':'whatsapp','correo':'email','email':'email','ciudad':'city','dias entrega':'average_delivery_days','días entrega':'average_delivery_days','observaciones':'notes'}}:{title:'Importar clientes',load:loadCustomers,table:'customers',key:'whatsapp',fields:{'nombre':'full_name','nombre completo':'full_name','cliente':'full_name','whatsapp':'whatsapp','telefono':'whatsapp','teléfono':'whatsapp','correo':'email','email':'email','observaciones':'notes','notas':'notes'}};
 modal(cfg.title,`<div class="import-wizard"><div class="callout"><b>Excel o CSV</b><p>La primera fila debe contener los encabezados. Se mostrará una vista previa antes de guardar.</p></div><label class="file-drop">Seleccionar archivo<input id="genericFile" type="file" accept=".xlsx,.xls,.csv"></label><div id="genericPreview"></div><div class="form-actions"><button class="button ghost" data-close-modal>Cancelar</button><button class="button primary" id="runGenericImport" disabled>Importar</button></div></div>`,{wide:true});
 let data=[];
 $('#genericFile').addEventListener('change',async event=>{try{const file=event.target.files[0];if(!file)return;const wb=await workbookFromFile(file);const rows=rowsFromSheet(wb,wb.SheetNames[0]);const headers=(rows[0]||[]).map(h=>cfg.fields[normalize(h)]||null);data=rows.slice(1).filter(r=>r.some(Boolean)).map(row=>Object.fromEntries(headers.map((h,i)=>[h,row[i]]).filter(([h])=>h))).filter(r=>r[cfg.key]);$('#genericPreview').innerHTML=`<div class="alert success">Se detectaron <b>${data.length}</b> registros válidos.</div><div class="preview-table"><table><thead><tr>${Object.keys(data[0]||{}).map(h=>`<th>${escapeHtml(h)}</th>`).join('')}</tr></thead><tbody>${data.slice(0,10).map(r=>`<tr>${Object.keys(data[0]||{}).map(h=>`<td>${escapeHtml(r[h]??'')}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;$('#runGenericImport').disabled=!data.length;}catch(error){toast(error.message,'danger');}});
 $('#runGenericImport').addEventListener('click',async()=>{const button=$('#runGenericImport');button.disabled=true;button.textContent='Importando…';try{await cfg.load();const existing=kind==='suppliers'?new Map(state.suppliers.map(x=>[normalize(x.business_name),x])):new Map(state.customers.map(x=>[normalize(x.whatsapp),x]));let created=0,updated=0;for(const row of data){const key=normalize(row[cfg.key]);const current=existing.get(key);const payload={...row};if('average_delivery_days'in payload)payload.average_delivery_days=number(payload.average_delivery_days)||null;if(current){const {data:changed,error}=await supabase.from(cfg.table).update(payload).eq('id',current.id).select('id').maybeSingle();if(error)throw error;if(!changed)throw new Error('Supabase bloqueó la actualización. Ejecuta la Migración 007.');updated++;}else{const {data:createdRow,error}=await supabase.from(cfg.table).insert({...payload,created_by:state.profile.id}).select('id').single();if(error)throw error;existing.set(key,{id:createdRow.id,...payload});created++;}}await audit(`importar_${kind}`,{created,updated});closeModal();toast(`${created} creados y ${updated} actualizados`);document.dispatchEvent(new CustomEvent('lihen:refresh'));}catch(error){button.disabled=false;button.textContent='Importar';toast(error.message,'danger');}});
}
export const importSuppliers=()=>genericImport('suppliers');
export const importCustomers=()=>genericImport('customers');
