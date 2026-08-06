const strategies = Object.freeze({
  ninguno: () => 0,
  porcentaje: (subtotal, value) => subtotal * Math.min(value, 100) / 100,
  valor_fijo: (subtotal, value) => Math.min(value, subtotal)
});

export function calculateDiscountByStrategy(subtotal, type = 'ninguno', value = 0) {
  const safeSubtotal = Math.max(0, Number(subtotal) || 0);
  const safeValue = Math.max(0, Number(value) || 0);
  return (strategies[type] || strategies.ninguno)(safeSubtotal, safeValue);
}

export function isSupportedDiscount(type) {
  return Object.hasOwn(strategies, type);
}
