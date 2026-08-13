function normalizedMessage(error) {
  return String(error?.message || error || '').trim();
}

export function isNetworkFetchError(error) {
  const message = normalizedMessage(error).toLowerCase();
  return error instanceof TypeError
    || message === 'failed to fetch'
    || message.includes('networkerror')
    || message.includes('network request failed')
    || message.includes('load failed');
}

export function errorMessage(error, fallback = 'Ocurrió un error inesperado.') {
  if (!error) return fallback;
  if (typeof error === 'string') return error;

  const message = normalizedMessage(error);
  const lower = message.toLowerCase();

  if (message === 'Invalid login credentials') {
    return 'Correo o contraseña incorrectos.';
  }

  if (isNetworkFetchError(error)) {
    return navigator.onLine === false
      ? 'Parece que no tienes conexión a internet. Revisa tu red e inténtalo nuevamente.'
      : 'No fue posible conectar con el servicio seguro de LIHEN. Inténtalo nuevamente en unos segundos.';
  }

  if (lower.includes('email not confirmed')) {
    return 'El correo todavía no ha sido confirmado.';
  }

  if (lower.includes('jwt') || lower.includes('session') || lower.includes('refresh token')) {
    return 'La sesión ya no es válida. Inicia sesión nuevamente.';
  }

  const details = [
    error.message,
    error.details,
    error.hint,
    error.code ? `Código: ${error.code}` : ''
  ].filter(Boolean);

  return details.length ? details.join(' · ') : fallback;
}

export function logAuthError(context, error) {
  const safe = {
    context,
    name: error?.name || null,
    message: normalizedMessage(error) || null,
    code: error?.code || null,
    status: error?.status || null,
    online: typeof navigator !== 'undefined' ? navigator.onLine : null
  };
  console.error('[LIHEN Auth]', safe);
}

export async function withPendingButton(button, pendingLabel, task) {
  if (!button || button.disabled) return undefined;

  const originalLabel = button.textContent;
  const originalAriaLabel = button.getAttribute('aria-label');
  button.disabled = true;
  button.setAttribute('aria-busy', 'true');
  button.setAttribute('aria-disabled', 'true');
  button.textContent = pendingLabel;

  try {
    return await task();
  } finally {
    button.disabled = false;
    button.removeAttribute('aria-busy');
    button.removeAttribute('aria-disabled');
    if (originalAriaLabel) button.setAttribute('aria-label', originalAriaLabel);
    button.textContent = originalLabel;
  }
}
