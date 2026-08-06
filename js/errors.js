export function errorMessage(error, fallback = 'Ocurrió un error inesperado.') {
  if (!error) return fallback;
  if (typeof error === 'string') return error;

  const details = [
    error.message,
    error.details,
    error.hint,
    error.code ? `Código: ${error.code}` : ''
  ].filter(Boolean);

  return details.length ? details.join(' · ') : fallback;
}

export async function withPendingButton(button, pendingLabel, task) {
  if (!button || button.disabled) return undefined;

  const originalLabel = button.textContent;
  button.disabled = true;
  button.textContent = pendingLabel;

  try {
    return await task();
  } finally {
    button.disabled = false;
    button.textContent = originalLabel;
  }
}
