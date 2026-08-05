import { supabase } from './supabase.js';
import { state, loadProducts, loadCustomers, loadOrders } from './store.js';
import { APP_CONFIG } from './config.js';
import { $, $$, escapeHtml, money, statusLabel, whatsappUrl } from './utils.js';
import { modal, closeModal, toast, badge, totals } from './ui.js';
import { openReceipt } from './receipts.js';

const PAYMENT_LABELS={sin_definir:'Por confirmar',efectivo_contra_entrega:'Efectivo contra entrega',nequi:'Nequi',llave_bancaria:'Llave bancaria',transferencia:'Transferencia bancaria',otro:'Otro'};
const ORDER_STATUSES=['solicitud_recibida','validando_disponibilidad','pendiente_proveedor','productos_solicitados','recepcion_parcial','pedido_completo','esperando_medio_pago','confirmado_cliente','preparando_entrega','enviado','entregado','cancelado'];

function productOption(p){
  const inv=p.inventory?.[0]||{};
  const search=[p.name,p.sku,p.brand,p.category].filter(Boolean).join(' · ');
  return `<option value="${p.id}" data-price="${Number(p.sale_price)||0}" data-stock="${Number(inv.available_stock)||0}" data-name="${escapeHtml(p.name)}">${escapeHtml(search)} · Stock ${Number(inv.available_stock)||0}</option>`;
}
function editorMarkup(order){
  const editing=Boolean(order);
  return `<form id="orderEditorForm" class="order-editor">
    <section class="order-editor-sticky">
      <div class="form-grid"><label class="full">Cliente<select name="customer_id" required><option value="">Selecciona un cliente</option>${state.customers.map(c=>`<option value="${c.id}" ${order?.customer_id===c.id?'selected':''}>${escapeHtml(c.full_name)} · ${escapeHtml(c.whatsapp)}</option>`).join('')}</select></label></div>
      <div class="quick-product-box">
        <div><p class="eyebrow">AGREGAR PRODUCTO</p><h3>Selección rápida</h3></div>
        <label class="quick-product-search">Producto<select id="quickProduct"><option value="">Busca por nombre, SKU, marca o categoría</option>${state.products.map(productOption).join('')}</select></label>
        <label>Cantidad<input id="quickQuantity" type="number" min="1" value="1"></label>
        <label>Precio<input id="quickPrice" type="number" min="0" value="0"></label>
        <button type="button" class="button secondary" id="quickAddProduct">+ Agregar</button>
      </div>
      <p class="quick-help">Agrega varios productos desde aquí sin desplazarte. La lista se actualiza debajo.</p>
    </section>
    <section class="order-items-section"><div class="section-title"><div><p class="eyebrow">PRODUCTOS AGREGADOS</p><h3 id="orderItemCount">0 productos</h3></div></div><div id="orderItems" class="order-builder compact"></div></section>
    <section class="order-editor-summary">
      <div class="form-grid">
        <label>Tipo de descuento<select name="discount_type" id="discountType"><option value="ninguno">Sin descuento</option><option value="porcentaje">Porcentaje</option><option value="valor_fijo">Valor fijo</option></select></label>
        <label>Valor del descuento<input name="discount_value" id="discountValue" type="number" min="0" value="${Number(order?.discount_value)||0}"></label>
        <label>Costo domicilio<input name="delivery_cost" id="deliveryCost" type="number" min="0" value="${Number(order?.delivery_cost)||0}"></label>
        <label>Método de pago<select name="payment_method">${Object.entries(PAYMENT_LABELS).map(([v,l])=>`<option value="${v}" ${order?.payment_method===v?'selected':''}>${l}</option>`).join('')}</select></label>
        ${editing?`<label>Estado<select name="status">${ORDER_STATUSES.map(v=>`<option value="${v}" ${order.status===v?'selected':''}>${statusLabel(v)}</option>`).join('')}</select></label>`:''}
        <label class="full">Notas internas<textarea name="internal_notes" rows="3">${escapeHtml(order?.internal_notes||'')}</textarea></label>
      </div>
      <div id="orderTotals" class="order-totals"></div>
      <div class="form-actions"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary" type="submit">${editing?'Guardar cambios':'Crear pedido'}</button></div>
    </section>
  </form>`;
}

export async function openOrderEditor(order=null){
  await Promise.all([loadProducts(),loadCustomers()]);
  if(order?.status==='entregado'){
    toast('Los pedidos entregados están bloqueados para proteger inventario y reportes.','warning');
    return;
  }
  modal(order?`Editar ${order.order_number}`:'Crear pedido LIHEN',editorMarkup(order),{wide:true});
  const form=$('#orderEditorForm'), items=$('#orderItems'), quick=$('#quickProduct'), quickQty=$('#quickQuantity'), quickPrice=$('#quickPrice');
  $('#discountType').value=order?.discount_type||'ninguno';
  function calculate(){
    let subtotal=0;
    $$('.order-row',items).forEach(r=>subtotal+=(Number($('.item-qty',r).value)||0)*(Number($('.item-price',r).value)||0));
    const type=$('#discountType').value,value=Number($('#discountValue').value)||0;
    const discount=type==='porcentaje'?subtotal*value/100:type==='valor_fijo'?Math.min(value,subtotal):0;
    const delivery=Number($('#deliveryCost').value)||0,total=Math.max(0,subtotal-discount+delivery);
    $('#orderTotals').innerHTML=`<div><span>Subtotal</span><b>${money(subtotal)}</b></div><div><span>Descuento</span><b>− ${money(discount)}</b></div><div><span>Domicilio</span><b>${money(delivery)}</b></div><div class="total"><span>Total</span><strong>${money(total)}</strong></div>`;
    $('#orderItemCount').textContent=`${$$('.order-row',items).length} producto(s)`;
    return{subtotal,discount,delivery,total};
  }
  function addItem(productId,quantity=1,unitPrice=null){
    const product=state.products.find(p=>p.id===productId); if(!product)return;
    const existing=$$('.order-row',items).find(r=>$('.item-product-id',r).value===productId);
    if(existing){$('.item-qty',existing).value=Number($('.item-qty',existing).value)+Number(quantity);calculate();toast('Cantidad actualizada en el producto existente');return;}
    const inv=product.inventory?.[0]||{}, row=document.createElement('div'); row.className='order-row';
    row.innerHTML=`<input class="item-product-id" type="hidden" value="${product.id}"><div class="order-product-name"><b>${escapeHtml(product.name)}</b><small>${escapeHtml(product.sku||product.brand||'Sin SKU')} · ${Number(inv.available_stock)||0} libre(s)</small></div><label>Cantidad<input class="item-qty" type="number" min="1" value="${Number(quantity)||1}"></label><label>Precio<input class="item-price" type="number" min="0" value="${unitPrice ?? (Number(product.sale_price)||0)}"></label><div class="stock-note">${Number(inv.available_stock)>0?`${Number(inv.available_stock)} disponible(s) físicamente`:'Se debe conseguir con proveedor'}</div><button type="button" class="remove-row" aria-label="Quitar producto">×</button>`;
    items.append(row);['.item-qty','.item-price'].forEach(sel=>$(sel,row).addEventListener('input',calculate));$('.remove-row',row).addEventListener('click',()=>{row.remove();calculate();});calculate();
  }
  quick.addEventListener('change',()=>{quickPrice.value=quick.selectedOptions[0]?.dataset.price||0;});
  $('#quickAddProduct').addEventListener('click',()=>{if(!quick.value)return toast('Selecciona un producto','danger');addItem(quick.value,quickQty.value,Number(quickPrice.value));quick.value='';quickQty.value=1;quickPrice.value=0;quick.focus();});
  ['discountType','discountValue','deliveryCost'].forEach(id=>$('#'+id).addEventListener('input',calculate));
  for(const item of order?.items||[]) addItem(item.product_id,item.quantity,item.unit_price);
  calculate();
  form.addEventListener('submit',async e=>{
    e.preventDefault();const button=$('button[type="submit"]',form),fd=Object.fromEntries(new FormData(form)),rows=$$('.order-row',items);if(!rows.length)return toast('Agrega al menos un producto','danger');
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
    }catch(err){button.disabled=false;button.textContent=order?'Guardar cambios':'Crear pedido';toast(err.message,'danger');}
  });
}

function productLines(order){return (order.items||[]).map(i=>`• ${i.product_name_snapshot} — ${i.quantity} ${i.quantity===1?'unidad':'unidades'} — ${money(i.line_total)}`).join('\n');}
export function confirmationMessage(order){return `Hola, ${order.customer?.full_name||''} 👋\n\nGracias por elegir LIHEN.CO ✨\n\nTe compartimos el resumen de tu pedido para que puedas revisarlo:\n\nPedido: ${order.order_number}\n\nProductos:\n${productLines(order)}\n\nSubtotal: ${money(order.subtotal)}\nDescuento: ${money(order.discount_amount)}\nDomicilio: ${money(order.delivery_cost)}\nTotal: ${money(order.total)}\n\nMétodo de pago: ${PAYMENT_LABELS[order.payment_method]||'Por confirmar'}\n\nPor favor confírmanos:\n1. Si los productos y cantidades están correctos.\n2. Si deseas agregar o retirar algún producto.\n3. Tu método de pago: efectivo contra entrega, Nequi, llave bancaria o transferencia.\n\nCuando tengamos tu confirmación, continuaremos con la preparación de tu pedido.\n\nConoce nuestro catálogo:\n${APP_CONFIG.catalogUrl}\n\nLIHEN.CO\nBeauty Care · Style`;}
export function confirmedMessage(order){const pending=(order.items||[]).some(i=>Number(i.quantity_to_source)>0);return `Hola, ${order.customer?.full_name||''} 👋\n\nTu pedido LIHEN.CO fue confirmado correctamente ✨\n\nPedido: ${order.order_number}\nTotal: ${money(order.total)}\nMétodo de pago: ${PAYMENT_LABELS[order.payment_method]||'Por confirmar'}\nEstado: ${statusLabel(order.status)}\n\n${pending?'Algunos productos están siendo solicitados al proveedor. Te mantendremos informada sobre el avance.':'Estamos preparando tus productos. Te avisaremos cuando el pedido esté listo para entrega.'}\n\nGracias por confiar en LIHEN.CO 🤎`;}

export function showOrder(order){
  const editable=!['entregado','cancelado'].includes(order.status);
  modal(`Pedido ${order.order_number}`,`<div class="order-detail"><div class="detail-grid"><div><span>Cliente</span><b>${escapeHtml(order.customer?.full_name||'—')}</b></div><div><span>WhatsApp</span><b>${escapeHtml(order.customer?.whatsapp||'—')}</b></div><div><span>Estado</span>${badge(order.status)}</div><div><span>Pago</span>${badge(order.payment_status)}</div></div><h3>Productos</h3><div class="line-items">${(order.items||[]).map(i=>`<div><div><b>${escapeHtml(i.product_name_snapshot)}</b><small>${i.quantity} × ${money(i.unit_price)}${i.quantity_to_source?` · ${i.quantity_to_source} por conseguir`:''}</small></div><strong>${money(i.line_total)}</strong></div>`).join('')}</div>${totals(order)}<div class="callout"><b>Próxima acción recomendada</b><p>${order.status==='pendiente_proveedor'?'Solicitar los productos faltantes al proveedor.':order.status==='pedido_completo'?'Enviar el resumen al cliente y confirmar el medio de pago.':'Continuar el seguimiento según el estado actual.'}</p></div></div>`,{wide:true,footer:`${editable?'<button class="button ghost" id="editOrderBtn">Editar pedido</button>':''}<a class="button whatsapp" target="_blank" rel="noopener noreferrer" id="confirmOrderWhatsapp">Enviar resumen para confirmar</a><a class="button whatsapp" target="_blank" rel="noopener noreferrer" id="confirmedWhatsapp">Enviar pedido confirmado</a><button class="button primary" id="orderReceiptBtn">Generar comprobante</button>`});
  $('#editOrderBtn')?.addEventListener('click',()=>openOrderEditor(order));
  const confirm=$('#confirmOrderWhatsapp');if(confirm)confirm.href=whatsappUrl(order.customer?.whatsapp,confirmationMessage(order));
  const confirmed=$('#confirmedWhatsapp');if(confirmed)confirmed.href=whatsappUrl(order.customer?.whatsapp,confirmedMessage(order));
  $('#orderReceiptBtn')?.addEventListener('click',()=>openReceipt(order));
}
