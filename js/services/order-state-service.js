const STATE_RULES = Object.freeze({
  solicitud_recibida: { editable: true, actions: ['edit','send-summary','cancel'] },
  validando_disponibilidad: { editable: true, actions: ['edit','send-summary','cancel'] },
  pendiente_proveedor: { editable: true, actions: ['edit','send-summary','cancel'] },
  productos_solicitados: { editable: true, actions: ['edit','send-summary','cancel'] },
  recepcion_parcial: { editable: true, actions: ['edit','send-summary','cancel'] },
  pedido_completo: { editable: true, actions: ['edit','send-summary','confirm','cancel'] },
  esperando_medio_pago: { editable: true, actions: ['edit','send-summary','confirm','cancel'] },
  confirmado_cliente: { editable: true, actions: ['edit','send-confirmed','receipt'] },
  preparando_entrega: { editable: true, actions: ['edit','send-confirmed','receipt'] },
  enviado: { editable: false, actions: ['send-confirmed','receipt'] },
  entregado: { editable: false, actions: ['receipt'] },
  cancelado: { editable: false, actions: [] }
});

export function getOrderStateRule(status) {
  return STATE_RULES[status] || { editable: true, actions: ['edit'] };
}

export function canEditOrder(status) {
  return getOrderStateRule(status).editable;
}

export function canPerformOrderAction(status, action) {
  return getOrderStateRule(status).actions.includes(action);
}
