import { state, loadProducts, loadCustomers } from './store.js';
import { $, $$, escapeHtml, money, statusLabel, whatsappUrl } from './utils.js';
import { ORDER_PAYMENT_LABELS, ORDER_STATUSES } from './constants.js';
import { calculateOrderTotals } from './order-calculations.js';
import { confirmationMessage, confirmedMessage } from './order-messages.js';
import { errorMessage } from './errors.js';
import { getOrderById, createOrderAtomic, updateOrderAtomic, listSavedOrderItems, closeOrderDirectAtomic } from './repositories/order-repository.js';
import { canEditOrder } from './services/order-state-service.js';
import { orderItemKey as itemKey, normalizeOrderItems as normalizedPayload, compareOrderItems } from './services/order-payload-service.js';
import { modal, closeModal, toast, badge, totals } from './ui.js';
import { openReceipt } from './receipts.js';

function publishOrderDebug(entry){
  const snapshot={...entry,created_at:new Date().toISOString()};
  window.__LIHEN_LAST_ORDER_SAVE__=snapshot;
  try{ sessionStorage.setItem('lihen:last-order-save',JSON.stringify(snapshot)); }catch(_err){}
  return snapshot;
}

function productOption(p){
  const inv=p.inventory?.[0]||{};
  const search=[p.name,p.sku,p.brand,p.category].filter(Boolean).join(' · ');
  return `<option value="${p.id}" data-price="${Number(p.sale_price)||0}" data-stock="${Number(inv.available_stock)||0}">${escapeHtml(search)} · Stock ${Number(inv.available_stock)||0}</option>`;
}

async function fetchFullOrder(order){ return getOrderById(order.id); }

function editorMarkup(order){
  const editing=Boolean(order);
  return `<form id="orderEditorForm" class="order-editor">
    <section class="order-editor-sticky">
      <div class="form-grid"><label class="full">Cliente<select name="customer_id" required><option value="">Selecciona un cliente</option>${state.customers.map(c=>`<option value="${c.id}" ${order?.customer_id===c.id?'selected':''}>${escapeHtml(c.full_name)} · ${escapeHtml(c.whatsapp)}</option>`).join('')}</select></label></div>
      <div class="quick-product-box">
        <div class="quick-product-heading"><p class="eyebrow">AGREGAR PRODUCTO</p><h3>Selección rápida</h3><small>Agrega uno tras otro sin desplazarte.</small></div>
        <label class="quick-product-search">Producto<select id="quickProduct"><option value="">Buscar por nombre, SKU, marca o categoría</option>${state.products.map(productOption).join('')}</select></label>
        <div class="quick-product-fields">
          <label>Cantidad<input id="quickQuantity" type="number" min="1" value="1"></label>
          <label>Precio<input id="quickPrice" type="number" min="0" value="0"></label>
          <button type="button" class="button secondary quick-add" id="quickAddProduct">+ Agregar al pedido</button>
        </div>
      </div>
    </section>
    <section class="order-items-section">
      <div class="section-title"><div><p class="eyebrow">PRODUCTOS DEL PEDIDO</p><h3 id="orderItemCount">0 productos</h3></div><button type="button" class="text-button" id="previewFromEditor">Vista previa</button></div>
      <div id="orderItems" class="order-builder compact"></div>
      <div id="emptyOrderItems" class="order-items-empty">Aún no hay productos agregados.</div>
    </section>
    <section class="order-editor-summary">
      <div class="form-grid">
        <label>Tipo de descuento<select name="discount_type" id="discountType"><option value="ninguno">Sin descuento</option><option value="porcentaje">Porcentaje</option><option value="valor_fijo">Valor fijo</option></select></label>
        <label>Valor del descuento<input name="discount_value" id="discountValue" type="number" min="0" value="${Number(order?.discount_value)||0}"></label>
        <label>Costo domicilio<input name="delivery_cost" id="deliveryCost" type="number" min="0" value="${Number(order?.delivery_cost)||0}"></label>
        <label>Método de pago<select name="payment_method">${Object.entries(ORDER_PAYMENT_LABELS).map(([v,l])=>`<option value="${v}" ${order?.payment_method===v?'selected':''}>${l}</option>`).join('')}</select></label>
        ${editing?`<label>Estado<select name="status">${ORDER_STATUSES.map(v=>`<option value="${v}" ${order.status===v?'selected':''}>${statusLabel(v)}</option>`).join('')}</select></label>`:''}
        <label class="full">Notas internas<textarea name="internal_notes" rows="3">${escapeHtml(order?.internal_notes||'')}</textarea></label>
      </div>
      <div class="editor-summary-card"><div><span>Productos</span><b id="summaryProducts">0</b></div><div><span>Unidades</span><b id="summaryUnits">0</b></div><div id="orderTotals" class="order-totals"></div></div>
      <div class="form-actions sticky-actions"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary" type="submit">${editing?'Guardar cambios':'Crear pedido'}</button></div>
    </section>
  </form>`;
}

function buildDraftOrder(form,items,baseOrder={}){
  let subtotal=0;
  const draftItems=$$('.order-row',items).map(r=>{
    const quantity=Number($('.item-qty',r).value)||0;
    const unit_price=Number($('.item-price',r).value)||0;
    subtotal+=quantity*unit_price;
    return {product_id:$('.item-product-id',r).value,product_name_snapshot:$('.order-product-name b',r)?.textContent||'Producto',quantity,unit_price,line_total:quantity*unit_price,quantity_to_source:0};
  });
  const discountType=$('#discountType').value;
  const discountValue=Number($('#discountValue').value)||0;
  const delivery_cost=Number($('#deliveryCost').value)||0;
  const calculated=calculateOrderTotals(draftItems,{discountType,discountValue,deliveryCost:delivery_cost});
  const fd=Object.fromEntries(new FormData(form));
  const customer=state.customers.find(c=>c.id===fd.customer_id)||baseOrder.customer;
  return {...baseOrder,customer,customer_id:fd.customer_id,items:draftItems,subtotal:calculated.subtotal,discount_type:discountType,discount_value:discountValue,discount_amount:calculated.discount,delivery_cost,total:calculated.total,payment_method:fd.payment_method,status:fd.status||baseOrder.status||'solicitud_recibida'};
}

export async function openOrderEditor(order=null){
  try{
    await Promise.all([loadProducts(),loadCustomers()]);
    order=order?await fetchFullOrder(order):null;
  }catch(err){toast(errorMessage(err,'No fue posible cargar el pedido.'),'danger');return;}

  if(order && !canEditOrder(order.status)){
    toast('Los pedidos entregados están bloqueados para proteger inventario y reportes.','warning');
    return;
  }

  modal(order?`Editar ${order.order_number}`:'Crear pedido LIHEN',editorMarkup(order),{wide:true});

  const form=$('#orderEditorForm');
  const itemsContainer=$('#orderItems');
  const quick=$('#quickProduct');
  const quickQty=$('#quickQuantity');
  const quickPrice=$('#quickPrice');
  $('#discountType').value=order?.discount_type||'ninguno';

  // Única fuente de verdad durante la edición. La interfaz se vuelve a renderizar
  // desde este arreglo; agregar, quitar, cantidades, vista previa y guardado usan
  // exactamente los mismos datos.
  const removedItemKeys=new Set();
  let editorItems=(order?.items||[]).map(item=>{
    const product=state.products.find(p=>p.id===item.product_id);
    return {
      product_id:item.product_id,
      variant_id:item.variant_id||null,
      variant_snapshot:item.variant_snapshot||null,
      name:item.product_name_snapshot||product?.name||'Producto',
      sku:product?.sku||product?.brand||'Sin SKU',
      available_stock:Number(product?.inventory?.[0]?.available_stock)||0,
      quantity:Math.max(1,Number(item.quantity)||1),
      unit_price:Number(item.unit_price)||0
    };
  });

  function totalsFromState(){
    return calculateOrderTotals(editorItems,{
      discountType:$('#discountType').value,
      discountValue:Number($('#discountValue').value)||0,
      deliveryCost:Number($('#deliveryCost').value)||0
    });
  }

  function updateSummary(){
    const values=totalsFromState();
    $('#orderTotals').innerHTML=`<div><span>Subtotal</span><b>${money(values.subtotal)}</b></div><div><span>Descuento</span><b>− ${money(values.discount)}</b></div><div><span>Domicilio</span><b>${money(values.delivery)}</b></div><div class="total"><span>Total</span><strong>${money(values.total)}</strong></div>`;
    $('#orderItemCount').textContent=`${editorItems.length} producto(s)`;
    $('#summaryProducts').textContent=editorItems.length;
    $('#summaryUnits').textContent=values.units;
    $('#emptyOrderItems').hidden=editorItems.length>0;
    return values;
  }

  function renderItems(){
    itemsContainer.innerHTML=editorItems.map((item,index)=>`
      <article class="order-row" data-item-index="${index}">
        <div class="order-product-name"><b>${escapeHtml(item.name)}</b><small>${escapeHtml(item.sku)} · ${item.available_stock} libre(s)</small></div>
        <div class="quantity-stepper">
          <button type="button" class="qty-minus" data-index="${index}" aria-label="Restar una unidad">−</button>
          <input class="item-qty" data-index="${index}" type="number" min="1" value="${item.quantity}">
          <button type="button" class="qty-plus" data-index="${index}" aria-label="Sumar una unidad">+</button>
        </div>
        <label class="price-field">Precio<input class="item-price" data-index="${index}" type="number" min="0" value="${item.unit_price}"></label>
        <div class="line-total"><small>Subtotal</small><b>${money(item.quantity*item.unit_price)}</b></div>
        <div class="stock-note">${item.available_stock>0?`${item.available_stock} disponible(s) físicamente`:'Se debe conseguir con proveedor'}</div>
        <button type="button" class="remove-row" data-index="${index}" aria-label="Quitar ${escapeHtml(item.name)}">Eliminar</button>
      </article>`).join('');

    $$('.qty-plus',itemsContainer).forEach(button=>button.addEventListener('click',()=>{
      const index=Number(button.dataset.index);
      editorItems[index].quantity+=1;
      renderItems();
      toast('Cantidad actualizada');
    }));
    $$('.qty-minus',itemsContainer).forEach(button=>button.addEventListener('click',()=>{
      const index=Number(button.dataset.index);
      if(editorItems[index].quantity<=1)return toast('La cantidad mínima es 1. Usa Eliminar para retirarlo.','warning');
      editorItems[index].quantity-=1;
      renderItems();
      toast('Cantidad actualizada');
    }));
    $$('.item-qty',itemsContainer).forEach(input=>input.addEventListener('input',()=>{
      const index=Number(input.dataset.index);
      editorItems[index].quantity=Math.max(1,Number(input.value)||1);
      updateSummary();
      const line=input.closest('.order-row')?.querySelector('.line-total b');
      if(line)line.textContent=money(editorItems[index].quantity*editorItems[index].unit_price);
    }));
    $$('.item-price',itemsContainer).forEach(input=>input.addEventListener('input',()=>{
      const index=Number(input.dataset.index);
      editorItems[index].unit_price=Math.max(0,Number(input.value)||0);
      updateSummary();
      const line=input.closest('.order-row')?.querySelector('.line-total b');
      if(line)line.textContent=money(editorItems[index].quantity*editorItems[index].unit_price);
    }));
    $$('.remove-row',itemsContainer).forEach(button=>button.addEventListener('click',()=>{
      const index=Number(button.dataset.index);
      const item=editorItems[index];
      if(!window.confirm(`¿Deseas retirar ${item.name} del pedido?`))return;
      const before=normalizedPayload(editorItems);
      removedItemKeys.add(itemKey(item));
      editorItems.splice(index,1);
      const after=normalizedPayload(editorItems);
      publishOrderDebug({stage:'removed-locally',order_id:order?.id||null,removed:itemKey(item),before,after});
      console.info('[LIHEN] Producto retirado localmente', {removed:itemKey(item),before,after});
      renderItems();
      toast('Producto retirado. Pulsa Guardar cambios para confirmar.');
    }));
    updateSummary();
  }

  function addProduct(productId,quantity=1,unitPrice=null){
    const product=state.products.find(p=>p.id===productId);
    if(!product)return toast('No se encontró el producto seleccionado.','danger');
    const requested=Math.max(1,Number(quantity)||1);
    const existingIndex=editorItems.findIndex(item=>item.product_id===productId&&!item.variant_id);
    if(existingIndex>=0){
      editorItems[existingIndex].quantity+=requested;
      renderItems();
      toast('Este producto ya estaba en el pedido. Su cantidad fue aumentada.','warning');
      return;
    }
    const inventory=product.inventory?.[0]||{};
    editorItems.push({
      product_id:product.id,
      variant_id:null,
      variant_snapshot:null,
      name:product.name,
      sku:product.sku||product.brand||'Sin SKU',
      available_stock:Number(inventory.available_stock)||0,
      quantity:requested,
      unit_price:unitPrice===null?Number(product.sale_price)||0:Math.max(0,Number(unitPrice)||0)
    });
    renderItems();
    toast('Producto agregado al pedido');
  }

  quick.addEventListener('change',()=>{quickPrice.value=quick.selectedOptions[0]?.dataset.price||0;});
  $('#quickAddProduct').addEventListener('click',()=>{
    if(!quick.value)return toast('Selecciona un producto','danger');
    addProduct(quick.value,quickQty.value,quickPrice.value);
    quick.value='';quickQty.value=1;quickPrice.value=0;quick.focus();
  });
  ['discountType','discountValue','deliveryCost'].forEach(id=>$('#'+id).addEventListener('input',updateSummary));

  renderItems();

  $('#previewFromEditor').addEventListener('click',()=>{
    const draft=buildDraftOrderFromState(form,editorItems,order||{});
    openSummaryPreview(draft,{returnToEditor:true});
  });

  form.addEventListener('submit',async event=>{
    event.preventDefault();
    if(!editorItems.length)return toast('Agrega al menos un producto','danger');
    const button=$('button[type="submit"]',form);
    const fields=Object.fromEntries(new FormData(form));
    const payload=normalizedPayload(editorItems);
    const payloadKeys=new Set(payload.map(itemKey));
    const accidentallyReinserted=[...removedItemKeys].filter(key=>payloadKeys.has(key));
    if(accidentallyReinserted.length){
      console.error('[LIHEN] Bloqueo de seguridad: productos eliminados reaparecieron en el payload',accidentallyReinserted);
      return toast('No se guardó: un producto eliminado reapareció en los datos. Recarga y vuelve a intentarlo.','danger');
    }

    button.disabled=true;
    button.textContent=order?'Guardando…':'Creando…';
    try{
      if(order){
        const requestId=`edit-${order.id}-${Date.now()}`;
        const debugBase=publishOrderDebug({
          stage:'before-rpc',requestId,order_id:order.id,
          removed_keys:[...removedItemKeys],payload
        });
        console.groupCollapsed(`[LIHEN] Guardar edición ${requestId}`);
        console.log('Pedido a actualizar:', order.id);
        console.log('Productos eliminados durante esta edición:', [...removedItemKeys]);
        console.table(editorItems.map(item=>({
          key:itemKey(item),product_id:item.product_id,variant_id:item.variant_id||null,
          name:item.name,quantity:Number(item.quantity),unit_price:Number(item.unit_price)
        })));
        console.log('payload.items exacto enviado a Supabase:');
        console.table(payload);

        const data=await updateOrderAtomic({
          p_order_id:order.id,
          p_customer_id:fields.customer_id,
          p_payment_method:fields.payment_method,
          p_discount_type:fields.discount_type,
          p_discount_value:Number(fields.discount_value)||0,
          p_delivery_cost:Number(fields.delivery_cost)||0,
          p_internal_notes:fields.internal_notes||null,
          p_status:fields.status,
          p_items:payload
        });
        publishOrderDebug({...debugBase,stage:'rpc-response',rpc_data:data||null,rpc_error:null});
        console.log('Respuesta update_order_atomic_v2:', {data,error:null});

        // Verificación real contra la tabla: no mostramos éxito hasta comprobar
        // productos, variantes, cantidades y precios guardados.
        const savedItems=await listSavedOrderItems(order.id);
        const matches=compareOrderItems(payload,savedItems);
        const verification={requestId,expected:payload,actual:savedItems,rpc:data,matches};
        publishOrderDebug({...debugBase,stage:'verified',...verification});
        console.log('[LIHEN] Verificación posterior:',verification);
        console.groupEnd();
        if(!matches)throw new Error('Supabase respondió, pero los productos almacenados no coinciden con la edición. El formulario seguirá abierto para no perder tus cambios.');

        closeModal();
        const savedOrder=data?.order||data;
        toast(`Pedido ${savedOrder?.order_number||order.order_number} actualizado correctamente`);
      }else{
        const data=await createOrderAtomic({
          p_customer_id:fields.customer_id,
          p_delivery_address_id:null,
          p_payment_method:fields.payment_method,
          p_discount_type:fields.discount_type,
          p_discount_value:Number(fields.discount_value)||0,
          p_delivery_cost:Number(fields.delivery_cost)||0,
          p_discount_reason:null,
          p_customer_notes:null,
          p_internal_notes:fields.internal_notes||null,
          p_items:payload
        });
        closeModal();
        toast(`Pedido ${data.order_number} creado y stock reservado`);
      }
      document.dispatchEvent(new CustomEvent('lihen:refresh'));
    }catch(err){
      try{console.groupEnd();}catch(_err){}
      const message=String(err?.message||err||'Error desconocido');
      publishOrderDebug({stage:'failed',order_id:order?.id||null,payload,error:message});
      console.error('Error al guardar pedido',{error:err,payload,removed_keys:[...removedItemKeys]});
      button.disabled=false;
      button.textContent=order?'Guardar cambios':'Crear pedido';
      const auditHint=message.includes('old_data')?' La función de Supabase sigue usando una columna de auditoría inexistente; ejecuta la migración 010 incluida.':'';
      toast(`No fue posible guardar los cambios: ${message}${auditHint}`,'danger');
    }
  });
}

function buildDraftOrderFromState(form,editorItems,baseOrder={}){
  const fields=Object.fromEntries(new FormData(form));
  const discountType=fields.discount_type||'ninguno';
  const discountValue=Number(fields.discount_value)||0;
  const delivery_cost=Number(fields.delivery_cost)||0;
  const calculated=calculateOrderTotals(editorItems,{discountType,discountValue,deliveryCost:delivery_cost});
  const subtotal=calculated.subtotal;
  const discount_amount=calculated.discount;
  const customer=state.customers.find(c=>c.id===fields.customer_id)||baseOrder.customer;
  return {
    ...baseOrder,
    customer,
    customer_id:fields.customer_id,
    items:editorItems.map(item=>({
      product_id:item.product_id,
      product_name_snapshot:item.name,
      quantity:item.quantity,
      unit_price:item.unit_price,
      line_total:item.quantity*item.unit_price,
      quantity_to_source:Math.max(0,item.quantity-item.available_stock)
    })),
    subtotal,
    discount_type:discountType,
    discount_value:discountValue,
    discount_amount,
    delivery_cost,
    total:calculated.total,
    payment_method:fields.payment_method,
    status:fields.status||baseOrder.status||'solicitud_recibida'
  };
}

export function openSummaryPreview(order,{returnToEditor=false}={}){
  const message=confirmationMessage(order);
  modal('Vista previa para el cliente',`<div class="summary-preview"><div class="preview-brand"><img src="assets/logo-lihen.jpg" alt="LIHEN"><div><p class="eyebrow">RESUMEN DEL PEDIDO</p><h3>${escapeHtml(order.order_number||'Pedido sin guardar')}</h3></div></div><div class="preview-message">${escapeHtml(message).replace(/\n/g,'<br>')}</div><div class="callout"><b>Revisa antes de enviar</b><p>WhatsApp abrirá este texto para que lo revises desde la cuenta corporativa de LIHEN.</p></div></div>`,{wide:true,footer:`<button class="button ghost" data-close-modal>Volver</button><a class="button whatsapp compact-action" target="_blank" rel="noopener noreferrer" href="${whatsappUrl(order.customer?.whatsapp,message)}"><span>◉</span> Enviar resumen</a>`});
}


function directCloseMarkup(order){
  const paymentOptions=Object.entries(ORDER_PAYMENT_LABELS)
    .filter(([value])=>value!=='sin_definir')
    .map(([value,label])=>`<option value="${value}" ${order.payment_method===value?'selected':''}>${escapeHtml(label)}</option>`)
    .join('');
  return `<form id="directCloseOrderForm" class="direct-close-form">
    <div class="callout"><b>Registrar pago y entrega directamente</b><p>Úsalo cuando la clienta ya pagó y recibió el pedido, aunque no se hayan enviado el resumen o la confirmación por WhatsApp.</p></div>
    <div class="form-grid">
      <label>Método de pago<select name="payment_method" required><option value="">Selecciona el medio de pago</option>${paymentOptions}</select></label>
      <label>Referencia del pago (opcional)<input name="reference_number" placeholder="Ej. Nequi MI1988910"></label>
      <label class="full">Motivo para omitir resumen y confirmación<textarea name="reason" rows="4" minlength="10" required placeholder="Ej. La clienta pagó directamente por Nequi y recibió el pedido en el local."></textarea></label>
      <label class="full">Observación interna adicional<textarea name="notes" rows="2" placeholder="Información adicional para el historial"></textarea></label>
    </div>
    <div class="alert warning"><b>Importante:</b> el pedido quedará como <b>Entregado</b> y el pago como <b>Pagado</b>. No se marcará como cancelado porque la venta sí se realizó.</div>
    <div class="form-actions"><button type="button" class="button ghost" data-close-modal>Volver</button><button type="submit" class="button primary">Registrar pago y entrega</button></div>
  </form>`;
}

function openDirectCloseOrder(order){
  modal(`Cerrar ${order.order_number}`,directCloseMarkup(order),{wide:true});
  const form=$('#directCloseOrderForm');
  form.addEventListener('submit',async event=>{
    event.preventDefault();
    const fields=Object.fromEntries(new FormData(form));
    const reason=String(fields.reason||'').trim();
    if(reason.length<10)return toast('Escribe un motivo claro de al menos 10 caracteres.','warning');
    const button=form.querySelector('button[type="submit"]');
    button.disabled=true;button.textContent='Registrando…';
    try{
      const result=await closeOrderDirectAtomic({
        p_order_id:order.id,
        p_payment_method:fields.payment_method,
        p_reason:reason,
        p_reference_number:String(fields.reference_number||'').trim()||null,
        p_notes:String(fields.notes||'').trim()||null
      });
      closeModal();
      toast(`Pedido ${order.order_number} registrado como pagado y entregado.`);
      document.dispatchEvent(new CustomEvent('lihen:refresh'));
      await openReceipt(result?.order||{...order,status:'entregado',payment_status:'pagado',payment_method:fields.payment_method});
    }catch(err){
      button.disabled=false;button.textContent='Registrar pago y entrega';
      toast(err?.message||'No fue posible registrar el pago y la entrega.','danger');
    }
  });
}

export async function showOrder(order){
  try{
    modal('Cargando pedido', '<div class="loading"><span class="spinner"></span><p>Consultando productos y totales…</p></div>', {wide:true});
    order = await fetchFullOrder(order);
  }catch(err){
    console.error('No fue posible cargar el pedido completo', err);
    closeModal();
    toast(`No fue posible cargar los productos del pedido: ${err.message}`, 'danger');
    return;
  }

  const editable=!['entregado','cancelado'].includes(order.status);
  const canReceipt=order.status==='entregado'&&order.payment_status==='pagado';
  const itemsMarkup=(order.items||[]).length?(order.items||[]).map(i=>`<div><div><b>${escapeHtml(i.product_name_snapshot)}</b><small>${i.quantity} × ${money(i.unit_price)}${i.quantity_to_source?` · ${i.quantity_to_source} por conseguir`:''}</small></div><strong>${money(i.line_total)}</strong></div>`).join(''):'<div class="empty-line-items">No se encontraron productos asociados. Actualiza la página e intenta nuevamente.</div>';
  const canDirectClose=!['entregado','cancelado'].includes(order.status);
  const recommendation=order.status==='pendiente_proveedor'
    ?'Solicitar los productos faltantes al proveedor.'
    :order.status==='pedido_completo'
      ?'Enviar el resumen al cliente o registrar directamente el pago y la entrega si la compra ya finalizó.'
      :canReceipt
        ?'El pedido ya fue pagado y entregado. Puedes generar el comprobante final.'
        :'Continuar el seguimiento según el estado actual.';
  modal(`Pedido ${order.order_number}`,`<div class="order-detail"><div class="detail-grid"><div><span>Cliente</span><b>${escapeHtml(order.customer?.full_name||'—')}</b></div><div><span>WhatsApp</span><b>${escapeHtml(order.customer?.whatsapp||'—')}</b></div><div><span>Estado</span>${badge(order.status)}</div><div><span>Pago</span>${badge(order.payment_status)}</div></div><h3>Productos</h3><div class="line-items">${itemsMarkup}</div>${totals(order)}<div class="callout"><b>Próxima acción recomendada</b><p>${recommendation}</p></div></div>`,{wide:true,footer:`<div class="order-action-grid">${editable?'<button class="action-tile" id="editOrderBtn"><span>✎</span><b>Editar</b></button>':''}<button class="action-tile" id="previewOrderBtn"><span>▤</span><b>Resumen</b></button><a class="action-tile whatsapp-tile" target="_blank" rel="noopener noreferrer" id="confirmOrderWhatsapp"><span>◉</span><b>Enviar resumen</b></a><a class="action-tile whatsapp-tile" target="_blank" rel="noopener noreferrer" id="confirmedWhatsapp"><span>◉</span><b>Confirmar pedido</b></a>${canDirectClose?'<button class="action-tile direct-close-tile" id="directCloseOrderBtn"><span>✓</span><b>Pago y entrega</b></button>':''}<button class="action-tile ${canReceipt?'receipt-tile':'disabled-tile'}" id="orderReceiptBtn" ${canReceipt?'':'aria-disabled="true"'}><span>▧</span><b>Comprobante final</b></button></div>`});
  $('#editOrderBtn')?.addEventListener('click',()=>openOrderEditor(order));
  $('#previewOrderBtn')?.addEventListener('click',()=>openSummaryPreview(order));
  $('#directCloseOrderBtn')?.addEventListener('click',()=>openDirectCloseOrder(order));
  const confirm=$('#confirmOrderWhatsapp');if(confirm)confirm.href=whatsappUrl(order.customer?.whatsapp,confirmationMessage(order));
  const confirmed=$('#confirmedWhatsapp');if(confirmed)confirmed.href=whatsappUrl(order.customer?.whatsapp,confirmedMessage(order));
  $('#orderReceiptBtn')?.addEventListener('click',()=>{if(!canReceipt)return toast('El comprobante final se genera únicamente cuando el pedido está entregado y el pago figura como pagado.','warning');openReceipt(order);});
}
