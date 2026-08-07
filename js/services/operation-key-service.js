const FALLBACK_RANDOM_BYTES = 16;

function fallbackUuid() {
  const bytes = new Uint8Array(FALLBACK_RANDOM_BYTES);
  globalThis.crypto?.getRandomValues?.(bytes);
  if (!bytes.some(Boolean)) {
    for (let i = 0; i < bytes.length; i += 1) bytes[i] = Math.floor(Math.random() * 256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map(value => value.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function createOperationKey(operationType) {
  const normalized = String(operationType || 'operacion')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '') || 'operacion';
  const uuid = globalThis.crypto?.randomUUID?.() || fallbackUuid();
  return `${normalized}:${uuid}`;
}

export function ensureOperationKey(payload, operationType) {
  if (payload?.p_operation_key) return payload;
  return { ...payload, p_operation_key: createOperationKey(operationType) };
}
