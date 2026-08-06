const listeners = new Map();

export function subscribe(eventName, listener) {
  if (!listeners.has(eventName)) listeners.set(eventName, new Set());
  listeners.get(eventName).add(listener);
  return () => listeners.get(eventName)?.delete(listener);
}

export function publish(eventName, payload) {
  listeners.get(eventName)?.forEach(listener => listener(payload));
  document.dispatchEvent(new CustomEvent(eventName, { detail: payload }));
}
