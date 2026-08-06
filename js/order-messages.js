import { APP_CONFIG } from './config.js';
import { ORDER_PAYMENT_LABELS } from './constants.js';
import { money, statusLabel } from './utils.js';

function productLines(order) {
  const lines = (order.items || []).map((item) => {
    const unitLabel = item.quantity === 1 ? 'unidad' : 'unidades';
    return `• ${item.product_name_snapshot} — ${item.quantity} ${unitLabel} — ${money(item.line_total)}`;
  });

  return lines.length
    ? lines.join('\n')
    : '• No se encontraron productos asociados. Revisa el pedido antes de enviarlo.';
}

export function confirmationMessage(order) {
  return `Hola, ${order.customer?.full_name || ''} 👋\n\nGracias por elegir LIHEN.CO ✨\n\nTe compartimos el resumen de tu pedido para que puedas revisarlo:\n\nPedido: ${order.order_number || 'Por asignar'}\n\nProductos:\n${productLines(order)}\n\nSubtotal: ${money(order.subtotal)}\nDescuento: ${money(order.discount_amount)}\nDomicilio: ${money(order.delivery_cost)}\nTotal: ${money(order.total)}\n\nMétodo de pago: ${ORDER_PAYMENT_LABELS[order.payment_method] || 'Por confirmar'}\n\nPor favor confírmanos:\n1. Si los productos y cantidades están correctos.\n2. Si deseas agregar o retirar algún producto.\n3. Tu método de pago: efectivo contra entrega, Nequi, llave bancaria o transferencia.\n\nCuando tengamos tu confirmación, continuaremos con la preparación de tu pedido.\n\nConoce nuestro catálogo:\n${APP_CONFIG.catalogUrl}\n\nLIHEN.CO\nBeauty Care | Style`;
}

export function confirmedMessage(order) {
  const hasPendingProducts = (order.items || []).some((item) => Number(item.quantity_to_source) > 0);
  const progressMessage = hasPendingProducts
    ? 'Algunos productos están siendo solicitados al proveedor. Te mantendremos informada sobre el avance.'
    : 'Estamos preparando tus productos. Te avisaremos cuando el pedido esté listo para entrega.';

  return `Hola, ${order.customer?.full_name || ''} 👋\n\nTu pedido LIHEN.CO fue confirmado correctamente ✨\n\nPedido: ${order.order_number}\nTotal: ${money(order.total)}\nMétodo de pago: ${ORDER_PAYMENT_LABELS[order.payment_method] || 'Por confirmar'}\nEstado: ${statusLabel(order.status)}\n\n${progressMessage}\n\nGracias por confiar en LIHEN.CO 🤎`;
}
