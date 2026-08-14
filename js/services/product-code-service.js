const normalize = value => String(value ?? '')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .trim()
  .toLowerCase()
  .replace(/\s+/g, ' ');

const LINE_PREFIX = Object.freeze({
  'beauty care': 'BC',
  style: 'ST'
});

export function skuPrefixForBusinessLine(businessLine) {
  return LINE_PREFIX[normalize(businessLine)] || null;
}

export function suggestNextProductSku(products = [], businessLine) {
  const prefix = skuPrefixForBusinessLine(businessLine);
  if (!prefix) return '';

  let max = 0;
  const matcher = new RegExp(`^${prefix}-(\\d+)$`, 'i');
  for (const product of products || []) {
    const match = String(product?.sku ?? '').trim().match(matcher);
    if (!match) continue;
    const value = Number(match[1]);
    if (Number.isInteger(value) && value > max) max = value;
  }
  return `${prefix}-${String(max + 1).padStart(3, '0')}`;
}

export function normalizeCatalogCode(value) {
  const trimmed = String(value ?? '').trim();
  return trimmed || null;
}

export function normalizedCatalogCodeKey(value) {
  const normalized = normalizeCatalogCode(value);
  return normalized ? normalize(normalized) : '';
}
