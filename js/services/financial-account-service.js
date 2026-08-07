export function summarizeAccounts(accounts = []) {
  const active = accounts.filter(account => account.active !== false);
  const total = active.reduce((sum, account) => sum + Number(account.current_balance || 0), 0);
  const find = code => Number(active.find(account => account.code === code)?.current_balance || 0);
  return { total, nequi: find('nequi'), cash: find('efectivo') };
}

export function validateMoneyMovement({ amount, type }) {
  const numeric = Number(amount);
  if (!Number.isFinite(numeric) || numeric <= 0) throw new Error('El valor debe ser mayor que cero.');
  if (!['ingreso','egreso','ajuste_positivo','ajuste_negativo'].includes(type)) throw new Error('Tipo de movimiento no permitido.');
  return numeric;
}
