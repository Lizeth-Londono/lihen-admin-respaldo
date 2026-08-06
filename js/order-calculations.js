import { calculateDiscountByStrategy } from './services/discount-service.js';

export function calculateDiscount(subtotal, type, value) {
  return calculateDiscountByStrategy(subtotal, type, value);
}

export function calculateOrderTotals(items, {
  discountType = 'ninguno',
  discountValue = 0,
  deliveryCost = 0
} = {}) {
  const normalizedItems = Array.isArray(items) ? items : [];
  const subtotal = normalizedItems.reduce((sum, item) => {
    return sum + (Math.max(0, Number(item.quantity) || 0) * Math.max(0, Number(item.unit_price) || 0));
  }, 0);
  const units = normalizedItems.reduce((sum, item) => sum + Math.max(0, Number(item.quantity) || 0), 0);
  const discount = calculateDiscountByStrategy(subtotal, discountType, discountValue);
  const delivery = Math.max(0, Number(deliveryCost) || 0);

  return {
    subtotal,
    units,
    discount,
    delivery,
    total: Math.max(0, subtotal - discount + delivery)
  };
}
