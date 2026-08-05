import { supabase } from './supabase.js';
import { state, loadSuppliers, loadProducts } from './store.js';
import { $, escapeHtml } from './utils.js';
import { modal, closeModal, toast } from './ui.js';

const val = value => value ?? '';
const num = value => value === '' || value == null ? null : Number(value);

async function audit(action, entityType, entityId, oldData, newData){
  try{
    const { error } = await supabase.from('audit_logs').insert({
      user_id: state.profile.id,
      action,
      entity_type: entityType,
      entity_id: entityId,
      old_data: oldData,
      new_data: newData
    });
    if(error) console.warn('Auditoría no registrada:', error);
  }catch(error){ console.warn('Auditoría no registrada:', error); }
}

function setSaving(form, saving, text='Guardar cambios'){
  const button=$('button[type="submit"]',form);
  if(!button) return;
  button.disabled=saving;
  button.textContent=saving?'Guardando…':text;
}

function showFormMessage(form,message,type='danger'){
  let box=$('[data-form-message]',form);
  if(!box){box=document.createElement('div');box.dataset.formMessage='1';box.className='full';form.prepend(box);}
  box.innerHTML=`<div class="alert ${type}">${escapeHtml(message)}</div>`;
  box.scrollIntoView({behavior:'smooth',block:'nearest'});
}

export async function editCustomer(id){
  const customer=state.customers.find(item=>item.id===id);
  if(!customer) return toast('No se encontró el cliente.','danger');
  const address=customer.addresses?.find(item=>item.is_default)||customer.addresses?.[0]||{};
  modal('Editar cliente',`<form id="editCustomerForm" class="form-grid">
    <label>Nombre completo<input name="full_name" required value="${escapeHtml(val(customer.full_name))}"></label>
    <label>WhatsApp<input name="whatsapp" required inputmode="tel" value="${escapeHtml(val(customer.whatsapp))}"></label>
    <label>Correo<input name="email" type="email" value="${escapeHtml(val(customer.email))}"></label>
    <label>Ciudad<input name="city" value="${escapeHtml(val(address.city||'Cali'))}"></label>
    <label class="full">Dirección / sector<input name="address_line" value="${escapeHtml(val(address.address_line))}"></label>
    <label class="full">Observaciones<textarea name="notes" rows="3">${escapeHtml(val(customer.notes))}</textarea></label>
    <label>Estado<select name="active"><option value="true" ${customer.active!==false?'selected':''}>Activo</option><option value="false" ${customer.active===false?'selected':''}>Inactivo</option></select></label>
    <div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary" type="submit">Guardar cambios</button></div>
  </form>`);
  $('#editCustomerForm').addEventListener('submit',async event=>{
    event.preventDefault(); const form=event.currentTarget; const f=Object.fromEntries(new FormData(form));
    const oldData={...customer}; setSaving(form,true);
    try{
      const payload={full_name:f.full_name.trim(),whatsapp:f.whatsapp.trim(),email:f.email||null,notes:f.notes||null,active:f.active==='true'};
      const {data,error}=await supabase.from('customers').update(payload).eq('id',id).select('id').maybeSingle();
      if(error) throw error; if(!data) throw new Error('Supabase no permitió actualizar el cliente. Ejecuta la Migración 007.');
      if(f.address_line){
        if(address.id){const {error:a}=await supabase.from('customer_addresses').update({address_line:f.address_line,city:f.city||'Cali'}).eq('id',address.id);if(a)throw a;}
        else{const {error:a}=await supabase.from('customer_addresses').insert({customer_id:id,address_line:f.address_line,city:f.city||'Cali',is_default:true});if(a)throw a;}
      }
      await audit('editar_cliente','customers',id,oldData,payload);
      closeModal(); toast('Cliente actualizado correctamente'); document.dispatchEvent(new CustomEvent('lihen:refresh'));
    }catch(error){setSaving(form,false);showFormMessage(form,error.message||'No fue posible guardar los cambios.');}
  });
}

export async function editSupplier(id){
  const supplier=state.suppliers.find(item=>item.id===id);
  if(!supplier) return toast('No se encontró el proveedor.','danger');
  modal('Editar proveedor',`<form id="editSupplierForm" class="form-grid">
    <label>Nombre comercial<input name="business_name" required value="${escapeHtml(val(supplier.business_name))}"></label>
    <label>Persona de contacto<input name="contact_name" value="${escapeHtml(val(supplier.contact_name))}"></label>
    <label>WhatsApp<input name="whatsapp" required value="${escapeHtml(val(supplier.whatsapp))}"></label>
    <label>Correo<input name="email" type="email" value="${escapeHtml(val(supplier.email))}"></label>
    <label>Ciudad<input name="city" value="${escapeHtml(val(supplier.city))}"></label>
    <label>Días habituales de entrega<input name="average_delivery_days" type="number" min="0" value="${val(supplier.average_delivery_days)}"></label>
    <label class="full">Información de pago<textarea name="payment_information" rows="2">${escapeHtml(val(supplier.payment_information))}</textarea></label>
    <label class="full">Observaciones<textarea name="notes" rows="3">${escapeHtml(val(supplier.notes))}</textarea></label>
    <label>Estado<select name="active"><option value="true" ${supplier.active!==false?'selected':''}>Activo</option><option value="false" ${supplier.active===false?'selected':''}>Inactivo</option></select></label>
    <div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary" type="submit">Guardar cambios</button></div>
  </form>`);
  $('#editSupplierForm').addEventListener('submit',async event=>{
    event.preventDefault(); const form=event.currentTarget; const f=Object.fromEntries(new FormData(form)); setSaving(form,true);
    const payload={business_name:f.business_name.trim(),contact_name:f.contact_name||null,whatsapp:f.whatsapp.trim(),email:f.email||null,city:f.city||null,average_delivery_days:num(f.average_delivery_days),payment_information:f.payment_information||null,notes:f.notes||null,active:f.active==='true'};
    try{
      const {data,error}=await supabase.from('suppliers').update(payload).eq('id',id).select('id').maybeSingle();
      if(error)throw error; if(!data)throw new Error('Supabase no permitió actualizar el proveedor. Ejecuta la Migración 007.');
      await audit('editar_proveedor','suppliers',id,supplier,payload);closeModal();toast('Proveedor actualizado correctamente');document.dispatchEvent(new CustomEvent('lihen:refresh'));
    }catch(error){setSaving(form,false);showFormMessage(form,error.message||'No fue posible guardar los cambios.');}
  });
}

export async function editProduct(id){
  await Promise.all([loadSuppliers(),loadProducts()]);
  const product=state.products.find(item=>item.id===id);
  if(!product) return toast('No se encontró el producto.','danger');
  const inventory=product.inventory?.[0]||{};
  const mainSupplier=product.supplier_products?.find(item=>item.preferred)?.supplier?.id||'';
  modal('Editar producto',`<form id="editProductForm" class="form-grid">
    <label>Código catálogo<input name="catalog_code" value="${escapeHtml(val(product.catalog_code))}"></label>
    <label>SKU interno<input name="sku" value="${escapeHtml(val(product.sku))}"></label>
    <label class="full">Nombre<input name="name" required value="${escapeHtml(val(product.name))}"></label>
    <label>Línea<select name="business_line"><option ${product.business_line==='Beauty Care'?'selected':''}>Beauty Care</option><option ${product.business_line==='Style'?'selected':''}>Style</option></select></label>
    <label>Categoría<input name="category" value="${escapeHtml(val(product.category))}"></label>
    <label>Marca<input name="brand" value="${escapeHtml(val(product.brand))}"></label>
    <label>Precio LIHEN<input name="sale_price" type="number" min="0" required value="${val(product.sale_price)}"></label>
    <label>Costo actual<input name="current_cost" type="number" min="0" value="${val(product.current_cost)}"></label>
    <label>Stock mínimo<input name="minimum_stock" type="number" min="0" value="${val(product.minimum_stock||0)}"></label>
    <label>Proveedor principal<select name="supplier_id"><option value="">Sin asignar</option>${state.suppliers.map(s=>`<option value="${s.id}" ${s.id===mainSupplier?'selected':''}>${escapeHtml(s.business_name)}</option>`).join('')}</select></label>
    <label>Visible en la página<select name="visible_on_website"><option value="true" ${product.visible_on_website?'selected':''}>Sí</option><option value="false" ${!product.visible_on_website?'selected':''}>No</option></select></label>
    <label>Estado<select name="status"><option value="activo" ${product.status==='activo'?'selected':''}>Activo</option><option value="oculto" ${product.status!=='activo'?'selected':''}>Oculto</option></select></label>
    <label class="full">Descripción<textarea name="description" rows="4">${escapeHtml(val(product.description))}</textarea></label>
    <div class="callout full"><b>Stock físico actual: ${inventory.physical_stock||0}</b><p>Para cambiar cantidades usa “Ajustar inventario”, así queda trazabilidad.</p></div>
    <div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary" type="submit">Guardar cambios</button></div>
  </form>`,{wide:true});
  $('#editProductForm').addEventListener('submit',async event=>{
    event.preventDefault(); const form=event.currentTarget; const f=Object.fromEntries(new FormData(form)); setSaving(form,true);
    try{
      const sku=f.sku?.trim()||null;
      if(sku){const {data:duplicate,error:dError}=await supabase.from('products').select('id,name').ilike('sku',sku).neq('id',id).maybeSingle();if(dError)throw dError;if(duplicate)throw new Error(`El SKU ${sku} ya pertenece a ${duplicate.name}.`);}
      const payload={catalog_code:f.catalog_code?.trim()||null,sku,name:f.name.trim(),business_line:f.business_line,category:f.category?.trim()||null,brand:f.brand?.trim()||null,sale_price:Number(f.sale_price),current_cost:num(f.current_cost),minimum_stock:Number(f.minimum_stock)||0,visible_on_website:f.visible_on_website==='true',status:f.status,description:f.description?.trim()||null,updated_by:state.profile.id};
      const {data:updated,error}=await supabase.from('products').update(payload).eq('id',id).select('id,name,status,visible_on_website').maybeSingle();
      if(error)throw error; if(!updated)throw new Error('Supabase no permitió actualizar el producto. Ejecuta la Migración 007 incluida en el ZIP.');
      const {error:clearError}=await supabase.from('supplier_products').update({preferred:false}).eq('product_id',id); if(clearError)throw clearError;
      if(f.supplier_id){
        const {data:relation,error:readError}=await supabase.from('supplier_products').select('id').eq('supplier_id',f.supplier_id).eq('product_id',id).maybeSingle(); if(readError)throw readError;
        if(relation){const {error:sError}=await supabase.from('supplier_products').update({last_cost:payload.current_cost,preferred:true}).eq('id',relation.id);if(sError)throw sError;}
        else{const {error:sError}=await supabase.from('supplier_products').insert({supplier_id:f.supplier_id,product_id:id,last_cost:payload.current_cost,preferred:true});if(sError)throw sError;}
      }
      await audit('editar_producto','products',id,product,payload);
      closeModal(); toast(`Producto “${updated.name}” actualizado correctamente`); document.dispatchEvent(new CustomEvent('lihen:refresh'));
    }catch(error){setSaving(form,false);showFormMessage(form,error.message||'No fue posible guardar los cambios.');}
  });
}
