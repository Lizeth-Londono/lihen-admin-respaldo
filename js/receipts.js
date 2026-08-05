import { supabase } from './supabase.js';
import { state } from './store.js';
import { $, escapeHtml, money, dateTime, whatsappUrl } from './utils.js';
import { modal, toast } from './ui.js';

function paymentLabel(value){
  return ({
    sin_definir:'Por confirmar',
    efectivo_contra_entrega:'Efectivo contra entrega',
    nequi:'Nequi',
    llave_bancaria:'Llave bancaria',
    transferencia:'Transferencia bancaria',
    otro:'Otro medio'
  })[value]||value||'Por confirmar';
}

export async function openReceipt(order){
  const {data,error}=await supabase
    .from('orders')
    .select('*,customer:customers(*),address:customer_addresses(*),items:order_items(*)')
    .eq('id',order.id)
    .single();
  if(error){toast(error.message,'danger');return;}

  const receiptNumber=`CP-${data.order_number.replace('LH-','')}`;
  const message=`Hola ${data.customer?.full_name||''} 😊\n\nTu pedido ${data.order_number} en LIHEN.CO está confirmado.\n\nTotal: ${money(data.total)}\nMedio de pago: ${paymentLabel(data.payment_method)}\nDomicilio: ${money(data.delivery_cost)}\n\nGracias por confiar en LIHEN.CO. ✨`;

  modal('Comprobante de pedido',`
    <article class="receipt-sheet" id="receiptSheet">
      <header class="receipt-brand">
        <img src="assets/logo-lihen.jpg" alt="LIHEN">
        <div><p>COMPROBANTE DE PEDIDO</p><h2>${escapeHtml(receiptNumber)}</h2></div>
      </header>
      <div class="receipt-meta">
        <div><span>Pedido</span><b>${escapeHtml(data.order_number)}</b></div>
        <div><span>Fecha</span><b>${dateTime(data.created_at)}</b></div>
        <div><span>Cliente</span><b>${escapeHtml(data.customer?.full_name||'—')}</b></div>
        <div><span>WhatsApp</span><b>${escapeHtml(data.customer?.whatsapp||'—')}</b></div>
      </div>
      <div class="receipt-address"><span>Entrega</span><b>${escapeHtml(data.address?.address_line||'Dirección por confirmar')}</b><small>${escapeHtml([data.address?.neighborhood,data.address?.city].filter(Boolean).join(' · '))}</small></div>
      <table class="receipt-table"><thead><tr><th>Producto</th><th>Cant.</th><th>Valor</th><th>Subtotal</th></tr></thead><tbody>
        ${(data.items||[]).map(i=>`<tr><td>${escapeHtml(i.product_name_snapshot)}${i.variant_snapshot?`<small>${escapeHtml(i.variant_snapshot)}</small>`:''}</td><td>${i.quantity}</td><td>${money(i.unit_price)}</td><td>${money(i.line_total)}</td></tr>`).join('')}
      </tbody></table>
      <div class="receipt-summary">
        <div><span>Subtotal</span><b>${money(data.subtotal)}</b></div>
        <div><span>Descuento</span><b>− ${money(data.discount_amount)}</b></div>
        <div><span>Domicilio</span><b>${money(data.delivery_cost)}</b></div>
        <div class="receipt-total"><span>Total</span><strong>${money(data.total)}</strong></div>
      </div>
      <div class="receipt-payment"><div><span>Medio de pago</span><b>${escapeHtml(paymentLabel(data.payment_method))}</b></div><div><span>Estado del pago</span><b>${escapeHtml(data.payment_status)}</b></div></div>
      ${Number(data.delivery_cost)===0?'<div class="receipt-gift"><b>🎉 Domicilio sin costo</b><p>Beneficio especial de inauguración LIHEN.</p></div>':''}
      <footer class="receipt-footer"><p>Gracias por confiar en LIHEN.CO.</p><span>Beauty Care · Style</span></footer>
    </article>`,{
      wide:true,
      footer:`<button class="button ghost" id="printReceiptBtn">Imprimir / Guardar PDF</button><a class="button whatsapp" target="_blank" href="${whatsappUrl(data.customer?.whatsapp,message)}">Enviar mensaje por WhatsApp</a>`
    });
  $('#printReceiptBtn')?.addEventListener('click',()=>window.print());
}
