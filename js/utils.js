export const $ = (selector, root = document) => root.querySelector(selector);
export const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
export const money = value => new Intl.NumberFormat('es-CO', { style:'currency', currency:'COP', maximumFractionDigits:0 }).format(Number(value) || 0);
export const dateTime = value => value ? new Intl.DateTimeFormat('es-CO', { dateStyle:'medium', timeStyle:'short' }).format(new Date(value)) : '—';
export const dateOnly = value => value ? new Intl.DateTimeFormat('es-CO', { dateStyle:'medium' }).format(new Date(`${value}T12:00:00`)) : '—';
export const escapeHtml = value => String(value ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
export const normalizePhone = value => String(value || '').replace(/\D/g, '');
export const colombiaPhone = value => {
  let phone=normalizePhone(value);
  if(phone.startsWith('00')) phone=phone.slice(2);
  if(phone.length===10) phone=`57${phone}`;
  return phone;
};
export const whatsappUrl = (phone, message) => `https://wa.me/${colombiaPhone(phone)}?text=${encodeURIComponent(message)}`;
export const initials = name => String(name || 'LI').split(/\s+/).slice(0,2).map(x => x[0]).join('').toUpperCase();
export const debounce = (fn, wait=250) => { let t; return (...args) => { clearTimeout(t); t=setTimeout(() => fn(...args), wait); }; };
export const statusLabel = value => ({
  solicitud_recibida:'Solicitud recibida',validando_disponibilidad:'Validando disponibilidad',pendiente_proveedor:'Pendiente de proveedor',productos_solicitados:'Productos solicitados',recepcion_parcial:'Recepción parcial',pedido_completo:'Pedido completo',esperando_medio_pago:'Esperando medio de pago',confirmado_cliente:'Confirmado con cliente',preparando_entrega:'Preparando entrega',enviado:'Enviado',entregado:'Entregado',cancelado:'Cancelado',
  pendiente:'Pendiente',parcial:'Parcial',pagado:'Pagado',reembolsado:'Reembolsado',completada:'Completada',anulada:'Anulada',activo:'Activo',borrador:'Borrador',oculto:'Oculto',descontinuado:'Descontinuado'
}[value] || String(value || '—').replaceAll('_',' '));
export const statusTone = value => {
  if (['entregado','pagado','pedido_completo','confirmado_cliente','completada','activo'].includes(value)) return 'success';
  if (['cancelado','anulada','descontinuado','no_disponible'].includes(value)) return 'danger';
  if (['pendiente_proveedor','productos_solicitados','recepcion_parcial','pendiente'].includes(value)) return 'warning';
  return 'neutral';
};
