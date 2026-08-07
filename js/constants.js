export const NAVIGATION_ITEMS = Object.freeze([
  Object.freeze({ id: 'dashboard', icon: '⌂', label: 'Inicio' }),
  Object.freeze({ id: 'orders', icon: '▤', label: 'Pedidos' }),
  Object.freeze({ id: 'quick-sales', icon: '🛒', label: 'Ventas rápidas' }),
  Object.freeze({ id: 'inventory', icon: '▦', label: 'Inventario y catálogo' }),
  Object.freeze({ id: 'suppliers', icon: '◇', label: 'Proveedores' }),
  Object.freeze({ id: 'customers', icon: '♡', label: 'Clientes' }),
  Object.freeze({ id: 'receipts', icon: '▧', label: 'Comprobantes' }),
  Object.freeze({ id: 'movements', icon: '↺', label: 'Movimientos' }),
  Object.freeze({ id: 'reports', icon: '↗', label: 'Reportes' }),
  Object.freeze({ id: 'cash', icon: '$', label: 'Caja y cuentas' }),
  Object.freeze({ id: 'settings', icon: '⚙', label: 'Configuración' })
]);

export const ORDER_PAYMENT_LABELS = Object.freeze({
  sin_definir: 'Por confirmar',
  efectivo_contra_entrega: 'Efectivo contra entrega',
  nequi: 'Nequi',
  llave_bancaria: 'Llave bancaria',
  transferencia: 'Transferencia bancaria',
  otro: 'Otro'
});

export const QUICK_SALE_PAYMENT_LABELS = Object.freeze({
  efectivo: 'Efectivo',
  nequi: 'Nequi',
  transferencia: 'Transferencia',
  llave_bancaria: 'Llave bancaria',
  datafono: 'Datáfono',
  otro: 'Otro'
});

export const ORDER_STATUSES = Object.freeze([
  'solicitud_recibida',
  'validando_disponibilidad',
  'pendiente_proveedor',
  'productos_solicitados',
  'recepcion_parcial',
  'pedido_completo',
  'esperando_medio_pago',
  'confirmado_cliente',
  'preparando_entrega',
  'enviado',
  'entregado',
  'cancelado'
]);
