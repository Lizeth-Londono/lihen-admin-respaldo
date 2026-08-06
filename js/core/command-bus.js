const commands = new Map();

export function registerCommand(name, handler) {
  if (!name || typeof handler !== 'function') throw new TypeError('Comando inválido.');
  commands.set(name, handler);
}

export async function executeCommand(name, context = {}) {
  const handler = commands.get(name);
  if (!handler) throw new Error(`Acción no registrada: ${name}`);
  return handler(context);
}

export function hasCommand(name) {
  return commands.has(name);
}
