import { createQuickSaleAtomic, cancelQuickSaleAtomic } from './repositories/quick-sale-repository.js';
import { QUICK_SALE_QUICK_SALE_PAYMENT_LABELS } from './constants.js';
import { state, loadProducts, loadCustomers, loadQuickSales } from './store.js';
import { $, $$, escapeHtml, money, dateTime, whatsappUrl } from './utils.js';
import { modal, closeModal, toast } from './ui.js';

let saleItems=[];

function optionMarkup(p){
  const inv=p.inventory?.[0]||{};
  return `<option value="${p.id}" data-price="${Number(p.sale_price)||0}" data-stock="${Number(inv.available_stock)||0}">${escapeHtml(p.name)} · ${escapeHtml(p.sku||p.brand||'Sin SKU')} · Stock ${Number(inv.available_stock)||0}</option>`;
}
function itemKey(item){return `${item.product_id}:${item.variant_id||''}`;}
function totals(){
  const subtotal=saleItems.reduce((sum,i)=>sum+i.quantity*i.unit_price,0);
  const type=$('#quickSaleDiscountType')?.value||'ninguno';
  const value=Number($('#quickSaleDiscountValue')?.value)||0;
  const discount=type==='porcentaje'?subtotal*Math.min(value,100)/100:type==='valor_fijo'?Math.min(value,subtotal):0;
  return {subtotal,discount,total:Math.max(0,subtotal-discount),units:saleItems.reduce((s,i)=>s+i.quantity,0)};
}
function renderSaleItems(){
  const root=$('#quickSaleItems');
  if(!root)return;
  root.innerHTML=saleItems.length?saleItems.map((i,index)=>`<article class="sale-item-card">
    <div><b>${escapeHtml(i.name)}</b><small>${escapeHtml(i.sku)} · ${i.stock} disponible(s)</small></div>
    <div class="quantity-stepper"><button type="button" data-sale-minus="${index}">−</button><input data-sale-qty="${index}" type="number" min="1" max="${i.stock}" value="${i.quantity}"><button type="button" data-sale-plus="${index}">+</button></div>
    <label>Precio<input data-sale-price="${index}" type="number" min="0" value="${i.unit_price}"></label>
    <strong>${money(i.quantity*i.unit_price)}</strong>
    <button type="button" class="remove-line" data-sale-remove="${index}">Eliminar</button>
  </article>`).join(''):`<div class="order-items-empty">Agrega los productos vendidos.</div>`;
  const t=totals();
  $('#quickSaleCount').textContent=`${saleItems.length} producto(s) · ${t.units} unidad(es)`;
  $('#quickSaleTotals').innerHTML=`<div><span>Subtotal</span><b>${money(t.subtotal)}</b></div><div><span>Descuento</span><b>− ${money(t.discount)}</b></div><div class="total"><span>Total</span><strong>${money(t.total)}</strong></div>`;
  bindRows();
}
function bindRows(){
  $$('[data-sale-minus]').forEach(b=>b.onclick=()=>{const i=Number(b.dataset.saleMinus);saleItems[i].quantity=Math.max(1,saleItems[i].quantity-1);renderSaleItems();});
  $$('[data-sale-plus]').forEach(b=>b.onclick=()=>{const i=Number(b.dataset.salePlus);saleItems[i].quantity=Math.min(saleItems[i].stock,saleItems[i].quantity+1);renderSaleItems();});
  $$('[data-sale-remove]').forEach(b=>b.onclick=()=>{saleItems.splice(Number(b.dataset.saleRemove),1);renderSaleItems();toast('Producto retirado de la venta');});
  $$('[data-sale-qty]').forEach(input=>input.oninput=()=>{const i=Number(input.dataset.saleQty);saleItems[i].quantity=Math.max(1,Math.min(saleItems[i].stock,Number(input.value)||1));renderSaleItems();});
  $$('[data-sale-price]').forEach(input=>input.oninput=()=>{saleItems[Number(input.dataset.salePrice)].unit_price=Math.max(0,Number(input.value)||0);renderSaleItems();});
}

export async function newQuickSale(){
  await Promise.all([loadProducts(),loadCustomers()]);
  saleItems=[];
  modal('Nueva venta rápida',`<form id="quickSaleForm" class="quick-sale-form">
    <div class="form-grid">
      <label class="full">Cliente (opcional)<select name="customer_id"><option value="">Consumidor final</option>${state.customers.map(c=>`<option value="${c.id}">${escapeHtml(c.full_name)} · ${escapeHtml(c.whatsapp||'Sin teléfono')}</option>`).join('')}</select></label>
    </div>
    <section class="quick-product-box sale-quick-box">
      <div class="quick-product-heading"><p class="eyebrow">VENTA INMEDIATA</p><h3>Agregar producto</h3><small>El stock se descontará al guardar.</small></div>
      <label class="quick-product-search">Producto<select id="saleProduct"><option value="">Buscar producto</option>${state.products.map(optionMarkup).join('')}</select></label>
      <div class="quick-product-fields"><label>Cantidad<input id="saleQuantity" type="number" min="1" value="1"></label><label>Precio<input id="salePrice" type="number" min="0" value="0"></label><button type="button" class="button secondary quick-add" id="saleAdd">+ Agregar</button></div>
    </section>
    <section class="order-items-section"><div class="section-title"><div><p class="eyebrow">PRODUCTOS VENDIDOS</p><h3 id="quickSaleCount">0 productos</h3></div></div><div id="quickSaleItems" class="sale-items-list"></div></section>
    <div class="form-grid">
      <label>Método de pago<select name="payment_method" required>${Object.entries(QUICK_SALE_PAYMENT_LABELS).map(([v,l])=>`<option value="${v}">${l}</option>`).join('')}</select></label>
      <label>Referencia / comprobante<input name="payment_reference" placeholder="Ej. Nequi MI1988910"></label>
      <label>Tipo de descuento<select id="quickSaleDiscountType" name="discount_type"><option value="ninguno">Sin descuento</option><option value="porcentaje">Porcentaje</option><option value="valor_fijo">Valor fijo</option></select></label>
      <label>Valor del descuento<input id="quickSaleDiscountValue" name="discount_value" type="number" min="0" value="0"></label>
      <label class="full">Observaciones<textarea name="notes" rows="2"></textarea></label>
    </div>
    <div id="quickSaleTotals" class="order-totals sale-totals"></div>
    <div class="form-actions"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary" type="submit">Guardar venta</button></div>
  </form>`,{wide:true});

  const product=$('#saleProduct'),quantity=$('#saleQuantity'),price=$('#salePrice');
  product.onchange=()=>{const opt=product.selectedOptions[0];price.value=Number(opt?.dataset.price)||0;quantity.max=Number(opt?.dataset.stock)||1;};
  $('#saleAdd').onclick=()=>{
    const opt=product.selectedOptions[0];if(!product.value){toast('Selecciona un producto','warning');return;}
    const qty=Math.max(1,Number(quantity.value)||1),stock=Number(opt.dataset.stock)||0;
    if(qty>stock){toast(`Solo hay ${stock} unidad(es) disponibles`,'danger');return;}
    const key=`${product.value}:`;const existing=saleItems.find(i=>itemKey(i)===key);
    if(existing){if(existing.quantity+qty>stock){toast(`La cantidad supera el stock disponible (${stock})`,'danger');return;}existing.quantity+=qty;toast('El producto ya estaba en la venta; se sumó la cantidad.');}
    else saleItems.push({product_id:product.value,variant_id:null,variant_snapshot:null,name:opt.textContent.split(' · ')[0],sku:opt.textContent.split(' · ')[1]||'',stock,quantity:qty,unit_price:Math.max(0,Number(price.value)||0)});
    product.value='';quantity.value=1;price.value=0;renderSaleItems();product.focus();
  };
  $('#quickSaleDiscountType').onchange=renderSaleItems;$('#quickSaleDiscountValue').oninput=renderSaleItems;renderSaleItems();
  $('#quickSaleForm').onsubmit=async e=>{
    e.preventDefault();if(!saleItems.length){toast('Agrega al menos un producto','warning');return;}
    const button=$('button[type="submit"]',e.currentTarget),fd=Object.fromEntries(new FormData(e.currentTarget));button.disabled=true;button.textContent='Guardando…';
    const payload=saleItems.map(i=>({product_id:i.product_id,variant_id:i.variant_id,variant_snapshot:i.variant_snapshot,quantity:i.quantity,unit_price:i.unit_price}));
    try{
      const data=await createQuickSaleAtomic({p_customer_id:fd.customer_id||null,p_payment_method:fd.payment_method,p_payment_reference:fd.payment_reference||null,p_discount_type:fd.discount_type,p_discount_value:Number(fd.discount_value)||0,p_notes:fd.notes||null,p_items:payload});closeModal();toast(`Venta ${data.sale.sale_number} registrada y stock actualizado`);document.dispatchEvent(new CustomEvent('lihen:refresh'));
    }catch(err){button.disabled=false;button.textContent='Guardar venta';toast(err.message||'No fue posible registrar la venta','danger');}
  };
}

export function quickSaleReceipt(sale){
  const customer=sale.customer?.full_name||'Consumidor final';
  const msg=`Hola, ${customer==='Consumidor final'?'':customer+' '}🤎\n\nGracias por comprar en LIHEN.CO.\n\nVenta: ${sale.sale_number}\nTotal pagado: ${money(sale.total)}\nMétodo de pago: ${QUICK_SALE_PAYMENT_LABELS[sale.payment_method]||sale.payment_method}\n\nEsperamos que disfrutes mucho tus productos y que muy pronto vuelvas a elegirnos ✨\n\nLIHEN.CO\nBeauty Care | Style`;
  modal(`Venta ${sale.sale_number}`,`<article class="receipt-sheet"><header class="receipt-brand"><img src="assets/logo-lihen.jpg"><div><p>COMPROBANTE DE VENTA RÁPIDA</p><h2>${escapeHtml(sale.sale_number)}</h2></div></header><div class="receipt-meta"><div><span>Fecha</span><b>${dateTime(sale.created_at)}</b></div><div><span>Cliente</span><b>${escapeHtml(customer)}</b></div><div><span>Pago</span><b>${escapeHtml(QUICK_SALE_PAYMENT_LABELS[sale.payment_method]||sale.payment_method)}</b></div><div><span>Referencia</span><b>${escapeHtml(sale.payment_reference||'—')}</b></div></div><table class="receipt-table"><thead><tr><th>Producto</th><th>Cant.</th><th>Valor</th><th>Total</th></tr></thead><tbody>${(sale.items||[]).map(i=>`<tr><td>${escapeHtml(i.product_name_snapshot)}</td><td>${i.quantity}</td><td>${money(i.unit_price)}</td><td>${money(i.line_total)}</td></tr>`).join('')}</tbody></table><div class="receipt-summary"><div><span>Subtotal</span><b>${money(sale.subtotal)}</b></div><div><span>Descuento</span><b>− ${money(sale.discount_amount)}</b></div><div class="receipt-total"><span>Total pagado</span><strong>${money(sale.total)}</strong></div></div>${sale.status==='anulada'?'<div class="alert danger"><b>Venta anulada</b><br>El stock fue reintegrado.</div>':''}<footer class="receipt-footer"><p>Gracias por elegir LIHEN.CO</p><span>Beauty Care | Style</span></footer></article>`,{wide:true,footer:`${sale.status==='completada'?'<button class="button ghost" id="cancelQuickSaleBtn">Anular venta</button>':''}<button class="button ghost" id="printQuickSale">Descargar / Guardar PDF</button>${sale.customer?.whatsapp&&sale.status==='completada'?`<a class="button whatsapp" target="_blank" rel="noopener noreferrer" href="${whatsappUrl(sale.customer.whatsapp,msg)}">Enviar por WhatsApp</a>`:''}`});
  $('#printQuickSale')?.addEventListener('click',()=>window.print());
  $('#cancelQuickSaleBtn')?.addEventListener('click',async()=>{await cancelQuickSale(sale);closeModal();});
}

export async function cancelQuickSale(sale){
  const reason=prompt(`Motivo para anular ${sale.sale_number}:`);if(reason===null)return;
  if(!confirm('La venta será anulada y las unidades volverán al stock. ¿Continuar?'))return;
  const {error}=await supabase.rpc('cancel_quick_sale_atomic',{p_sale_id:sale.id,p_reason:reason||'Anulación administrativa'});
  if(error){toast(error.message,'danger');return;}toast('Venta anulada y stock reintegrado');await loadQuickSales();document.dispatchEvent(new CustomEvent('lihen:refresh'));
}
