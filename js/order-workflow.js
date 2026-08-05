import { supabase } from './supabase.js';
import { state, loadProducts, loadCustomers } from './store.js';
import { APP_CONFIG } from './config.js';
import { $, $$, escapeHtml, money, statusLabel, whatsappUrl } from './utils.js';
import { modal, closeModal, toast, badge, totals } from './ui.js';
import { openReceipt } from './receipts.js';

const PAYMENT_LABELS={sin_definir:'Por confirmar',efectivo_contra_entrega:'Efectivo contra entrega',nequi:'Nequi',llave_bancaria:'Llave bancaria',transferencia:'Transferencia bancaria',otro:'Otro'};
const ORDER_STATUSES=['solicitud_recibida','validando_disponibilidad','pendiente_proveedor','productos_solicitados','recepcion_parcial','pedido_completo','esperando_medio_pago','confirmado_cliente','preparando_entrega','enviado','entregado','cancelado'];

function productOption(p){
  const inv=p.inventory?.[0]||{};
  const search=[p.name,p.sku,p.brand,p.category].filter(Boolean).join(' · ');
  return `<option value="${p.id}" data-price="${Number(p.sale_price)||0}" data-stock="${Number(inv.available_stock)||0}">${escapeHtml(search)} · Stock ${Number(inv.available_stock)||0}</option>`;
}

async function fetchFullOrder(order){
  if(!order?.id) return order;
  const {data,error}=await supabase.from('orders').select('*,customer:customers(id,full_name,whatsapp),items:order_items(id,product_id,variant_id,variant_snapshot,quantity,unit_price,line_total,product_name_snapshot,quantity_from_stock,quantity_to_source,quantity_reserved,quantity_received)').eq('id',order.id).single();
  if(error) throw error;
  return data;
}

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
        <label>Método de pago<select name="payment_method">${Object.entries(PAYMENT_LABELS).map(([v,l])=>`<option value="${v}" ${order?.payment_method===v?'selected':''}>${l}</option>`).join('')}</select></label>
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
  const discount_amount=discountType==='porcentaje'?subtotal*discountValue/100:discountType==='valor_fijo'?Math.min(discountValue,subtotal):0;
  const delivery_cost=Number($('#deliveryCost').value)||0;
  const fd=Object.fromEntries(new FormData(form));
  const customer=state.customers.find(c=>c.id===fd.customer_id)||baseOrder.customer;
  return {...baseOrder,customer,customer_id:fd.customer_id,items:draftItems,subtotal,discount_type:discountType,discount_value:discountValue,discount_amount,delivery_cost,total:Math.max(0,subtotal-discount_amount+delivery_cost),payment_method:fd.payment_method,status:fd.status||baseOrder.status||'solicitud_recibida'};
}

export async function openOrderEditor(order=null){
  try{
    await Promise.all([loadProducts(),loadCustomers()]);
    order=order?await fetchFullOrder(order):null;
  }catch(err){toast(`No fue posible cargar el pedido: ${err.message}`,'danger');return;}
  if(order?.status==='entregado'){
    toast('Los pedidos entregados están bloqueados para proteger inventario y reportes.','warning');
    return;
  }
  modal(order?`Editar ${order.order_number}`:'Crear pedido LIHEN',editorMarkup(order),{wide:true});
  const form=$('#orderEditorForm'), items=$('#orderItems'), quick=$('#quickProduct'), quickQty=$('#quickQuantity'), quickPrice=$('#quickPrice');
  $('#discountType').value=order?.discount_type||'ninguno';

  function calculate(){
    let subtotal=0,units=0;
    const rows=$$('.order-row',items);
    rows.forEach(r=>{const q=Number($('.item-qty',r).value)||0;subtotal+=q*(Number($('.item-price',r).value)||0);units+=q;const line=$('.item-line-total',r);if(line)line.textContent=money(q*(Number($('.item-price',r).value)||0));});
    const type=$('#discountType').value,value=Number($('#discountValue').value)||0;
    const discount=type==='porcentaje'?subtotal*value/100:type==='valor_fijo'?Math.min(value,subtotal):0;
    const delivery=Number($('#deliveryCost').value)||0,total=Math.max(0,subtotal-discount+delivery);
    $('#orderTotals').innerHTML=`<div><span>Subtotal</span><b>${money(subtotal)}</b></div><div><span>Descuento</span><b>− ${money(discount)}</b></div><div><span>Domicilio</span><b>${money(delivery)}</b></div><div class="total"><span>Total</span><strong>${money(total)}</strong></div>`;
    $('#orderItemCount').textContent=`${rows.length} producto(s)`;
    $('#summaryProducts').textContent=rows.length;
    $('#summaryUnits').textContent=units;
    $('#emptyOrderItems').hidden=rows.length>0;
    return{subtotal,discount,delivery,total};
  }

  function removeItem(row){
    const name=$('.order-product-name b',row)?.textContent||'este producto';
    if(!window.confirm(`¿Deseas retirar ${name} del pedido?`))return;
    row.remove();calculate();toast('Producto retirado del pedido');
  }

  function addItem(productId,quantity=1,unitPrice=null,{silent=false}={}){
    const product=state.products.find(p=>p.id===productId); if(!product)return;
    const existing=$$('.order-row',items).find(r=>$('.item-product-id',r).value===productId);
    if(existing){
      $('.item-qty',existing).value=Math.max(1,Number($('.item-qty',existing).value)+Number(quantity));
      calculate();
      if(!silent)toast('Este producto ya estaba en el pedido. Su cantidad fue aumentada.','warning');
      return;
    }
    const inv=product.inventory?.[0]||{}, row=document.createElement('div'); row.className='order-row';
    row.innerHTML=`<input class="item-product-id" type="hidden" value="${product.id}"><div class="order-product-name"><b>${escapeHtml(product.name)}</b><small>${escapeHtml(product.sku||product.brand||'Sin SKU')} · ${Number(inv.available_stock)||0} libre(s)</small></div><div class="quantity-stepper"><button type="button" class="qty-minus" aria-label="Restar">−</button><input class="item-qty" type="number" min="1" value="${Number(quantity)||1}"><button type="button" class="qty-plus" aria-label="Sumar">+</button></div><label class="price-field">Precio<input class="item-price" type="number" min="0" value="${unitPrice ?? (Number(product.sale_price)||0)}"></label><div class="line-total"><small>Subtotal</small><b class="item-line-total">${money((Number(quantity)||1)*(unitPrice ?? (Number(product.sale_price)||0)))}</b></div><div class="stock-note">${Number(inv.available_stock)>0?`${Number(inv.available_stock)} disponible(s) físicamente`:'Se debe conseguir con proveedor'}</div><button type="button" class="remove-row" aria-label="Quitar producto">Eliminar</button>`;
    items.append(row);
    $('.qty-plus',row).addEventListener('click',()=>{$('.item-qty',row).value=Number($('.item-qty',row).value)+1;calculate();toast('Cantidad actualizada');});
    $('.qty-minus',row).addEventListener('click',()=>{const input=$('.item-qty',row);if(Number(input.value)<=1)return toast('La cantidad mínima es 1. Usa Eliminar para retirarlo.','warning');input.value=Number(input.value)-1;calculate();toast('Cantidad actualizada');});
    ['.item-qty','.item-price'].forEach(sel=>$(sel,row).addEventListener('input',calculate));
    $('.remove-row',row).addEventListener('click',()=>removeItem(row));
    calculate();
    if(!silent)toast('Producto agregado al pedido');
  }

  quick.addEventListener('change',()=>{quickPrice.value=quick.selectedOptions[0]?.dataset.price||0;});
  $('#quickAddProduct').addEventListener('click',()=>{if(!quick.value)return toast('Selecciona un producto','danger');addItem(quick.value,quickQty.value,Number(quickPrice.value));quick.value='';quickQty.value=1;quickPrice.value=0;quick.focus();});
  ['discountType','discountValue','deliveryCost'].forEach(id=>$('#'+id).addEventListener('input',calculate));
  for(const item of order?.items||[]) addItem(item.product_id,item.quantity,item.unit_price,{silent:true});
  calculate();

  $('#previewFromEditor').addEventListener('click',()=>openSummaryPreview(buildDraftOrder(form,items,order||{}),{returnToEditor:true}));

  form.addEventListener('submit',async e=>{
    e.preventDefault();
    const button=$('button[type="submit"]',form),fd=Object.fromEntries(new FormData(form)),rows=$$('.order-row',items);
    if(!rows.length)return toast('Agrega al menos un producto','danger');
    const payload=rows.map(r=>({product_id:$('.item-product-id',r).value,variant_id:null,variant_snapshot:null,quantity:Number($('.item-qty',r).value),unit_price:Number($('.item-price',r).value)}));
    button.disabled=true;button.textContent=order?'Guardando…':'Creando…';
    try{
      if(order){
        const {data,error}=await supabase.rpc('update_order_atomic',{p_order_id:order.id,p_customer_id:fd.customer_id,p_payment_method:fd.payment_method,p_discount_type:fd.discount_type,p_discount_value:Number(fd.discount_value)||0,p_delivery_cost:Number(fd.delivery_cost)||0,p_internal_notes:fd.internal_notes||null,p_status:fd.status,p_items:payload});if(error)throw error;
        closeModal();toast(`Pedido ${data.order_number} actualizado correctamente`);
      }else{
        const {data,error}=await supabase.rpc('create_order_atomic',{p_customer_id:fd.customer_id,p_delivery_address_id:null,p_payment_method:fd.payment_method,p_discount_type:fd.discount_type,p_discount_value:Number(fd.discount_value)||0,p_delivery_cost:Number(fd.delivery_cost)||0,p_discount_reason:null,p_customer_notes:null,p_internal_notes:fd.internal_notes||null,p_items:payload});if(error)throw error;
        closeModal();toast(`Pedido ${data.order_number} creado y stock reservado`);
      }
      document.dispatchEvent(new CustomEvent('lihen:refresh'));
    }catch(err){console.error('Error al guardar pedido',err);button.disabled=false;button.textContent=order?'Guardar cambios':'Crear pedido';toast(`No fue posible guardar los cambios: ${err.message}`,'danger');}
  });
}

function productLines(order){return (order.items||[]).map(i=>`• ${i.product_name_snapshot} — ${i.quantity} ${i.quantity===1?'unidad':'unidades'} — ${money(i.line_total)}`).join('\n');}
export function confirmationMessage(order){return `Hola, ${order.customer?.full_name||''} 👋\n\nGracias por elegir LIHEN.CO ✨\n\nTe compartimos el resumen de tu pedido para que puedas revisarlo:\n\nPedido: ${order.order_number||'Por asignar'}\n\nProductos:\n${productLines(order)}\n\nSubtotal: ${money(order.subtotal)}\nDescuento: ${money(order.discount_amount)}\nDomicilio: ${money(order.delivery_cost)}\nTotal: ${money(order.total)}\n\nMétodo de pago: ${PAYMENT_LABELS[order.payment_method]||'Por confirmar'}\n\nPor favor confírmanos:\n1. Si los productos y cantidades están correctos.\n2. Si deseas agregar o retirar algún producto.\n3. Tu método de pago: efectivo contra entrega, Nequi, llave bancaria o transferencia.\n\nCuando tengamos tu confirmación, continuaremos con la preparación de tu pedido.\n\nConoce nuestro catálogo:\n${APP_CONFIG.catalogUrl}\n\nLIHEN.CO\nBeauty Care | Style`;}
export function confirmedMessage(order){const pending=(order.items||[]).some(i=>Number(i.quantity_to_source)>0);return `Hola, ${order.customer?.full_name||''} 👋\n\nTu pedido LIHEN.CO fue confirmado correctamente ✨\n\nPedido: ${order.order_number}\nTotal: ${money(order.total)}\nMétodo de pago: ${PAYMENT_LABELS[order.payment_method]||'Por confirmar'}\nEstado: ${statusLabel(order.status)}\n\n${pending?'Algunos productos están siendo solicitados al proveedor. Te mantendremos informada sobre el avance.':'Estamos preparando tus productos. Te avisaremos cuando el pedido esté listo para entrega.'}\n\nGracias por confiar en LIHEN.CO 🤎`;}

export function openSummaryPreview(order,{returnToEditor=false}={}){
  const message=confirmationMessage(order);
  modal('Vista previa para el cliente',`<div class="summary-preview"><div class="preview-brand"><img src="assets/logo-lihen.jpg" alt="LIHEN"><div><p class="eyebrow">RESUMEN DEL PEDIDO</p><h3>${escapeHtml(order.order_number||'Pedido sin guardar')}</h3></div></div><div class="preview-message">${escapeHtml(message).replace(/\n/g,'<br>')}</div><div class="callout"><b>Revisa antes de enviar</b><p>WhatsApp abrirá este texto para que lo revises desde la cuenta corporativa de LIHEN.</p></div></div>`,{wide:true,footer:`<button class="button ghost" data-close-modal>Volver</button><a class="button whatsapp compact-action" target="_blank" rel="noopener noreferrer" href="${whatsappUrl(order.customer?.whatsapp,message)}"><span>◉</span> Enviar resumen</a>`});
}

export function showOrder(order){
  const editable=!['entregado','cancelado'].includes(order.status);
  const canReceipt=order.status==='entregado'&&order.payment_status==='pagado';
  const itemsMarkup=(order.items||[]).length?(order.items||[]).map(i=>`<div><div><b>${escapeHtml(i.product_name_snapshot)}</b><small>${i.quantity} × ${money(i.unit_price)}${i.quantity_to_source?` · ${i.quantity_to_source} por conseguir`:''}</small></div><strong>${money(i.line_total)}</strong></div>`).join(''):'<div class="empty-line-items">No se encontraron productos asociados. Actualiza la página e intenta nuevamente.</div>';
  modal(`Pedido ${order.order_number}`,`<div class="order-detail"><div class="detail-grid"><div><span>Cliente</span><b>${escapeHtml(order.customer?.full_name||'—')}</b></div><div><span>WhatsApp</span><b>${escapeHtml(order.customer?.whatsapp||'—')}</b></div><div><span>Estado</span>${badge(order.status)}</div><div><span>Pago</span>${badge(order.payment_status)}</div></div><h3>Productos</h3><div class="line-items">${itemsMarkup}</div>${totals(order)}<div class="callout"><b>Próxima acción recomendada</b><p>${order.status==='pendiente_proveedor'?'Solicitar los productos faltantes al proveedor.':order.status==='pedido_completo'?'Enviar el resumen al cliente y confirmar el medio de pago.':'Continuar el seguimiento según el estado actual.'}</p></div></div>`,{wide:true,footer:`<div class="order-action-grid">${editable?'<button class="action-tile" id="editOrderBtn"><span>✎</span><b>Editar</b></button>':''}<button class="action-tile" id="previewOrderBtn"><span>▤</span><b>Resumen</b></button><a class="action-tile whatsapp-tile" target="_blank" rel="noopener noreferrer" id="confirmOrderWhatsapp"><span>◉</span><b>Enviar resumen</b></a><a class="action-tile whatsapp-tile" target="_blank" rel="noopener noreferrer" id="confirmedWhatsapp"><span>◉</span><b>Confirmar pedido</b></a><button class="action-tile ${canReceipt?'receipt-tile':'disabled-tile'}" id="orderReceiptBtn" ${canReceipt?'':'aria-disabled="true"'}><span>▧</span><b>Comprobante final</b></button></div>`});
  $('#editOrderBtn')?.addEventListener('click',()=>openOrderEditor(order));
  $('#previewOrderBtn')?.addEventListener('click',()=>openSummaryPreview(order));
  const confirm=$('#confirmOrderWhatsapp');if(confirm)confirm.href=whatsappUrl(order.customer?.whatsapp,confirmationMessage(order));
  const confirmed=$('#confirmedWhatsapp');if(confirmed)confirmed.href=whatsappUrl(order.customer?.whatsapp,confirmedMessage(order));
  $('#orderReceiptBtn')?.addEventListener('click',()=>{if(!canReceipt)return toast('El comprobante final se genera únicamente cuando el pedido está entregado y el pago figura como pagado.','warning');openReceipt(order);});
}
