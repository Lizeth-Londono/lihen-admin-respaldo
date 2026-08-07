export function normalizePurchaseItems(items = []) {
  const merged = new Map();
  for (const raw of items) {
    const productId = String(raw.product_id || '').trim();
    const quantity = Number(raw.quantity_requested);
    const cost = Number(raw.quoted_unit_cost);
    if (!productId) throw new Error('Cada producto debe tener un identificador válido.');
    if (!Number.isInteger(quantity) || quantity <= 0) throw new Error('La cantidad debe ser un entero mayor que cero.');
    if (!Number.isFinite(cost) || cost < 0) throw new Error('El costo unitario no puede ser negativo.');
    const current = merged.get(productId);
    if (current) current.quantity_requested += quantity;
    else merged.set(productId, { product_id: productId, quantity_requested: quantity, quoted_unit_cost: cost });
  }
  if (!merged.size) throw new Error('La compra debe incluir al menos un producto.');
  return [...merged.values()];
}

export function calculatePurchaseTotals(items = [], extras = {}) {
  const subtotal = items.reduce((sum, item) => sum + Number(item.quantity_requested || 0) * Number(item.quoted_unit_cost || 0), 0);
  const discount = Math.max(0, Number(extras.discountAmount || 0));
  const tax = Math.max(0, Number(extras.taxAmount || 0));
  const freight = Math.max(0, Number(extras.freightAmount || 0));
  return { subtotal, total: Math.max(0, subtotal - discount + tax + freight) };
}

export function summarizePurchase(purchase) {
  const total = Number(purchase.total_amount || 0);
  const paid = Number(purchase.amount_paid || 0);
  return { total, paid, pending: Math.max(0, total - paid) };
}
