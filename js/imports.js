import { supabase } from './supabase.js';
import { state, loadProducts, loadSuppliers, loadCustomers } from './store.js';
import { $, escapeHtml } from './utils.js';
import { modal, closeModal, toast } from './ui.js';

const normalize=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ');
const number=v=>{if(v==null||v==='')return 0;const n=Number(String(v).replace(/[^0-9,.-]/g,'').replace(',','.'));return Number.isFinite(n)?n:0;};
const chunks=(arr,size=40)=>Array.from({length:Math.ceil(arr.length/size)},(_,i)=>arr.slice(i*size,i*size+size));

function ensureXlsx(){if(!window.XLSX)throw new Error('No se pudo cargar el lector de Excel. Actualiza la página e inténtalo nuevamente.');}
async function workbookFromFile(file){ensureXlsx();const buffer=await file.arrayBuffer();return XLSX.read(buffer,{type:'array',cellDates:true});}
function rowsFromSheet(workbook,name){return XLSX.utils.sheet_to_json(workbook.Sheets[name],{header:1,defval:null,raw:true});}
async function audit(action,newData){try{await supabase.from('audit_logs').insert({user_id:state.profile.id,action,entity_type:'importacion',new_data:newData});}catch(error){console.warn(error);}}

export function importInventory(){
 modal('Importar inventario desde Excel',`<div class="import-wizard">
  <div class="callout"><b>Cargue masivo con control por SKU</b><p>Lee las hojas Beauty Care y Style. Los productos existentes se actualizan; los nuevos se crean. Antes de guardar verás un resumen.</p></div>
  <label class="file-drop">Seleccionar Inventario_LIHEN_Corregido_Final.xlsx<input id="inventoryFile" type="file" accept=".xlsx,.xls"></label>
  <div id="inventoryPreview"></div>
  <div class="form-actions"><button class="button ghost" data-close-modal>Cancelar</button><button class="button primary" id="runInventoryImport" disabled>Importar inventario</button></div>
 </div>`,{wide:true});
 let prepared=[];let sourceName='';
 $('#inventoryFile').addEventListener('change',async event=>{
  try{
   const file=event.target.files[0];if(!file)return;sourceName=file.name;const wb=await workbookFromFile(file);prepared=[];
   for(const sheetName of ['Beauty Care','Style']){
    if(!wb.SheetNames.includes(sheetName))continue;
    const rows=rowsFromSheet(wb,sheetName);const headerIndex=rows.findIndex(row=>normalize(row[0])==='sku');if(headerIndex<0)continue;
    for(const row of rows.slice(headerIndex+1)){
     if(!row[0]||!row[3])continue;
     prepared.push({sku:String(row[0]).trim(),business_line:sheetName,category:row[1]||null,subcategory:row[2]||null,name:String(row[3]).trim(),brand:row[4]||null,supplier_name:row[5]||null,current_cost:number(row[8]),sale_price:number(row[13]),physical_stock:number(row[17]),minimum_stock:number(row[18]),status_text:row[19]||null});
    }
   }
   await Promise.all([loadProducts(),loadSuppliers()]);
   const existing=new Map(state.products.filter(p=>p.sku).map(p=>[normalize(p.sku),p]));
   const supplierNames=new Set(state.suppliers.map(s=>normalize(s.business_name)));
   const duplicates=prepared.filter((r,i,a)=>a.findIndex(x=>normalize(x.sku)===normalize(r.sku))!==i);
   const create=prepared.filter(r=>!existing.has(normalize(r.sku))).length;
   const update=prepared.length-create;
   const pendingSuppliers=[...new Set(prepared.map(r=>r.supplier_name).filter(Boolean).filter(n=>!supplierNames.has(normalize(n))))];
   $('#inventoryPreview').innerHTML=`<div class="import-summary"><div><b>${prepared.length}</b><span>Filas válidas</span></div><div><b>${create}</b><span>Productos nuevos</span></div><div><b>${update}</b><span>Por actualizar</span></div><div><b>${duplicates.length}</b><span>SKU repetidos</span></div></div>${pendingSuppliers.length?`<div class="alert warning"><b>${pendingSuppliers.length} proveedores pendientes:</b> ${escapeHtml(pendingSuppliers.slice(0,8).join(', '))}${pendingSuppliers.length>8?'…':''}. Los productos se importarán sin proveedor hasta que los registres.</div>`:''}<div class="preview-table"><table><thead><tr><th>SKU</th><th>Producto</th><th>Línea</th><th>Stock</th><th>Precio</th><th>Acción</th></tr></thead><tbody>${prepared.slice(0,12).map(r=>`<tr><td>${escapeHtml(r.sku)}</td><td>${escapeHtml(r.name)}</td><td>${escapeHtml(r.business_line)}</td><td>${r.physical_stock}</td><td>${r.sale_price}</td><td>${existing.has(normalize(r.sku))?'Actualizar':'Crear'}</td></tr>`).join('')}</tbody></table></div>`;
   $('#runInventoryImport').disabled=!prepared.length||duplicates.length>0;
   if(duplicates.length)toast('El archivo contiene SKU repetidos. Corrígelos antes de importar.','danger');
  }catch(error){toast(error.message,'danger');}
 });
 $('#runInventoryImport').addEventListener('click',async()=>{
  const button=$('#runInventoryImport');button.disabled=true;button.textContent='Importando…';
  try{
   await Promise.all([loadProducts(),loadSuppliers()]);
   const existing=new Map(state.products.filter(p=>p.sku).map(p=>[normalize(p.sku),p]));
   const suppliers=new Map(state.suppliers.map(s=>[normalize(s.business_name),s]));
   let created=0,updated=0,units=0,pendingSupplier=0;
   for(const row of prepared){
    const current=existing.get(normalize(row.sku));
    const payload={sku:row.sku,name:row.name,business_line:row.business_line,category:row.category,brand:row.brand,current_cost:row.current_cost||null,sale_price:row.sale_price||0,minimum_stock:row.minimum_stock||0,status:'activo',visible_on_website:current?.visible_on_website??false,description:current?.description||null,updated_by:state.profile.id};
    let productId;
    if(current){const {error}=await supabase.from('products').update(payload).eq('id',current.id);if(error)throw error;productId=current.id;updated++;}
    else{const {data,error}=await supabase.from('products').insert({...payload,created_by:state.profile.id}).select('id').single();if(error)throw error;productId=data.id;created++;existing.set(normalize(row.sku),{id:productId,...payload});}
    const {data:inv,error:iRead}=await supabase.from('inventory').select('id,physical_stock').eq('product_id',productId).maybeSingle();if(iRead)throw iRead;
    if(inv){const {error}=await supabase.from('inventory').update({physical_stock:row.physical_stock,updated_by:state.profile.id}).eq('id',inv.id);if(error)throw error;}
    else{const {error}=await supabase.from('inventory').insert({product_id:productId,physical_stock:row.physical_stock,updated_by:state.profile.id});if(error)throw error;}
    units+=row.physical_stock;
    const supplier=suppliers.get(normalize(row.supplier_name));
    if(supplier){await supabase.from('supplier_products').upsert({supplier_id:supplier.id,product_id:productId,last_cost:row.current_cost||null,preferred:true},{onConflict:'supplier_id,product_id'});}else if(row.supplier_name)pendingSupplier++;
   }
   await audit('importar_inventario',{source_file:sourceName,created,updated,units,pending_supplier_links:pendingSupplier});
   closeModal();toast(`Importación lista: ${created} creados y ${updated} actualizados`);document.dispatchEvent(new CustomEvent('lihen:refresh'));
  }catch(error){button.disabled=false;button.textContent='Importar inventario';toast(error.message,'danger');}
 });
}

function genericImport(kind){
 const cfg=kind==='suppliers'?{title:'Importar proveedores',load:loadSuppliers,table:'suppliers',key:'business_name',fields:{'nombre comercial':'business_name','proveedor':'business_name','persona de contacto':'contact_name','contacto':'contact_name','whatsapp':'whatsapp','telefono':'whatsapp','teléfono':'whatsapp','correo':'email','email':'email','ciudad':'city','dias entrega':'average_delivery_days','días entrega':'average_delivery_days','observaciones':'notes'}}:{title:'Importar clientes',load:loadCustomers,table:'customers',key:'whatsapp',fields:{'nombre':'full_name','nombre completo':'full_name','cliente':'full_name','whatsapp':'whatsapp','telefono':'whatsapp','teléfono':'whatsapp','correo':'email','email':'email','observaciones':'notes','notas':'notes'}};
 modal(cfg.title,`<div class="import-wizard"><div class="callout"><b>Excel o CSV</b><p>La primera fila debe contener los encabezados. Se mostrará una vista previa antes de guardar.</p></div><label class="file-drop">Seleccionar archivo<input id="genericFile" type="file" accept=".xlsx,.xls,.csv"></label><div id="genericPreview"></div><div class="form-actions"><button class="button ghost" data-close-modal>Cancelar</button><button class="button primary" id="runGenericImport" disabled>Importar</button></div></div>`,{wide:true});
 let data=[];
 $('#genericFile').addEventListener('change',async event=>{try{const file=event.target.files[0];if(!file)return;const wb=await workbookFromFile(file);const rows=rowsFromSheet(wb,wb.SheetNames[0]);const headers=(rows[0]||[]).map(h=>cfg.fields[normalize(h)]||null);data=rows.slice(1).filter(r=>r.some(Boolean)).map(row=>Object.fromEntries(headers.map((h,i)=>[h,row[i]]).filter(([h])=>h))).filter(r=>r[cfg.key]);$('#genericPreview').innerHTML=`<div class="alert success">Se detectaron <b>${data.length}</b> registros válidos.</div><div class="preview-table"><table><thead><tr>${Object.keys(data[0]||{}).map(h=>`<th>${escapeHtml(h)}</th>`).join('')}</tr></thead><tbody>${data.slice(0,10).map(r=>`<tr>${Object.keys(data[0]||{}).map(h=>`<td>${escapeHtml(r[h]??'')}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;$('#runGenericImport').disabled=!data.length;}catch(error){toast(error.message,'danger');}});
 $('#runGenericImport').addEventListener('click',async()=>{try{await cfg.load();const existing=kind==='suppliers'?new Map(state.suppliers.map(x=>[normalize(x.business_name),x])):new Map(state.customers.map(x=>[normalize(x.whatsapp),x]));let created=0,updated=0;for(const row of data){const key=normalize(row[cfg.key]);const current=existing.get(key);const payload={...row};if('average_delivery_days'in payload)payload.average_delivery_days=number(payload.average_delivery_days)||null;if(current){const {error}=await supabase.from(cfg.table).update(payload).eq('id',current.id);if(error)throw error;updated++;}else{const {data:createdRow,error}=await supabase.from(cfg.table).insert({...payload,created_by:state.profile.id}).select('id').single();if(error)throw error;existing.set(key,{id:createdRow.id,...payload});created++;}}await audit(`importar_${kind}`,{created,updated});closeModal();toast(`${created} creados y ${updated} actualizados`);document.dispatchEvent(new CustomEvent('lihen:refresh'));}catch(error){toast(error.message,'danger');}});
}
export const importSuppliers=()=>genericImport('suppliers');
export const importCustomers=()=>genericImport('customers');
