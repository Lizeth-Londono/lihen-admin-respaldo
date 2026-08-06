export function unwrap(result, fallbackMessage = 'No fue posible completar la operación.') {
  if (result?.error) {
    const error = new Error(result.error.message || fallbackMessage);
    error.code = result.error.code;
    error.details = result.error.details;
    error.hint = result.error.hint;
    throw error;
  }
  return result?.data;
}

export function assertAll(results, fallbackMessage) {
  for (const result of results) unwrap(result, fallbackMessage);
  return results.map(result => result.data);
}
