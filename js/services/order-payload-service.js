export function orderItemKey(item) {
  return `${item.product_id}:${item.variant_id || ''}`;
}

export function normalizeOrderItems(items) {
  return (Array.isArray(items) ? items : []).map(item => ({
    product_id: String(item.product_id),
    variant_id: item.variant_id || null,
    variant_snapshot: item.variant_snapshot || null,
    quantity: Math.max(1, Number(item.quantity) || 1),
    unit_price: Math.max(0, Number(item.unit_price) || 0)
  }));
}

export function compareOrderItems(expected, saved) {
  const normalizeMap = rows => new Map(normalizeOrderItems(rows).map(row => [orderItemKey(row), row]));
  const expectedMap = normalizeMap(expected);
  const savedMap = normalizeMap(saved);
  if (expectedMap.size !== savedMap.size) return false;
  for (const [key, item] of expectedMap) {
    const candidate = savedMap.get(key);
    if (!candidate || candidate.quantity !== item.quantity || candidate.unit_price !== item.unit_price) return false;
  }
  return true;
}
