import { state, loadFinancialAccounts } from './store.js';
import { $, escapeHtml, money } from './utils.js';
import { modal, closeModal, toast } from './ui.js';
import { confirmAction, moneyDetail } from './services/confirmation-service.js';
import { createOperationKey } from './services/operation-key-service.js';
import { configureInitialBalance, registerFinancialMovement, transferFinancialFunds, reverseFinancialMovement } from './repositories/financial-account-repository.js';
import { validateMoneyMovement } from './services/financial-account-service.js';

function dateInputValue(date = new Date()) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}
function dateTimeInputValue(date = new Date()) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

export async function configureAccountBalance(accountId) {
  await loadFinancialAccounts();
  const account = state.financialAccounts.find((item) => item.id === accountId);
  if (!account) return toast('Cuenta no encontrada.', 'danger');
  modal(`Configurar saldo inicial · ${account.name}`, `<form id="initialBalanceForm" class="form-grid"><label>Saldo inicial<input name="amount" type="number" min="0" step="1" value="0" required></label><label>Fecha de inicio<input name="effective_date" type="date" value="${dateInputValue()}" required></label><label class="full">Justificación<textarea name="reason" rows="3" required placeholder="Ejemplo: saldo real verificado al iniciar el control financiero"></textarea></label><div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary">Configurar saldo</button></div></form>`);
  $('#initialBalanceForm').addEventListener('submit', async (event) => {
    event.preventDefault(); const data = Object.fromEntries(new FormData(event.currentTarget)); const amount = Number(data.amount);
    try {
      if (!Number.isFinite(amount) || amount < 0) throw new Error('El saldo inicial no puede ser negativo.');
      if (String(data.reason || '').trim().length < 8) throw new Error('Escribe una justificación clara.');
      const accepted = await confirmAction({ title: 'Configurar saldo inicial', message: 'Este valor será el punto de partida de la cuenta.', confirmLabel: 'Configurar saldo', details: [{ label: 'Cuenta', value: account.name }, moneyDetail('Saldo inicial', amount), { label: 'Fecha', value: data.effective_date }] });
      if (!accepted) return;
      await configureInitialBalance({ accountId, amount, effectiveDate: data.effective_date, reason: data.reason, operationKey: createOperationKey('saldo_inicial') });
      closeModal(); toast('Saldo inicial configurado.'); document.dispatchEvent(new CustomEvent('lihen:refresh'));
    } catch (error) { toast(error.message, 'danger'); }
  });
}

export async function newFinancialMovement() {
  await loadFinancialAccounts();
  const accounts = state.financialAccounts.filter((item) => item.active !== false && item.initial_balance_configured);
  if (!accounts.length) return toast('Configura primero el saldo inicial de una cuenta.', 'warning');
  modal('Nuevo movimiento financiero', `<form id="financialMovementForm" class="form-grid"><label class="full">Cuenta<select name="account_id" required><option value="">Selecciona</option>${accounts.map((account) => `<option value="${account.id}">${escapeHtml(account.name)} · ${money(account.current_balance)}</option>`).join('')}</select></label><label>Tipo<select name="type"><option value="ingreso">Ingreso</option><option value="egreso">Egreso</option><option value="ajuste_positivo">Ajuste positivo</option><option value="ajuste_negativo">Ajuste negativo</option></select></label><label>Valor<input name="amount" type="number" min="1" step="1" required></label><label>Categoría<input name="category" required placeholder="Ejemplo: gasto operativo"></label><label>Fecha y hora<input name="occurred_at" type="datetime-local" value="${dateTimeInputValue()}" required></label><label class="full">Descripción<textarea name="description" rows="3" required></textarea></label><div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary">Registrar movimiento</button></div></form>`);
  $('#financialMovementForm').addEventListener('submit', async (event) => {
    event.preventDefault(); const data = Object.fromEntries(new FormData(event.currentTarget));
    try {
      const amount = validateMoneyMovement({ amount: data.amount, type: data.type });
      const account = accounts.find((item) => item.id === data.account_id); if (!account) throw new Error('Selecciona una cuenta válida.');
      const delta = ['ingreso', 'ajuste_positivo'].includes(data.type) ? amount : -amount;
      const accepted = await confirmAction({ title: 'Registrar movimiento', message: 'Este movimiento cambiará el saldo real de la cuenta.', confirmLabel: 'Registrar movimiento', tone: delta < 0 ? 'warning' : 'primary', details: [{ label: 'Cuenta', value: account.name }, { label: 'Tipo', value: data.type.replaceAll('_', ' ') }, moneyDetail('Valor', amount), moneyDetail('Saldo posterior estimado', Number(account.current_balance) + delta)] });
      if (!accepted) return;
      await registerFinancialMovement({ accountId: account.id, type: data.type, amount, category: data.category, description: data.description, occurredAt: new Date(data.occurred_at).toISOString(), operationKey: createOperationKey('movimiento_financiero') });
      closeModal(); toast('Movimiento registrado.'); document.dispatchEvent(new CustomEvent('lihen:refresh'));
    } catch (error) { toast(error.message, 'danger'); }
  });
}


export async function transferBetweenAccounts() {
  await loadFinancialAccounts();
  const accounts = state.financialAccounts.filter((item) => item.active !== false && item.initial_balance_configured);
  if (accounts.length < 2) return toast('Necesitas al menos dos cuentas configuradas para transferir dinero.', 'warning');
  const options = accounts.map((account) => `<option value="${account.id}">${escapeHtml(account.name)} · ${money(account.current_balance)}</option>`).join('');
  modal('Transferir entre cuentas', `<form id="financialTransferForm" class="form-grid"><label>Cuenta origen<select name="source_account_id" required><option value="">Selecciona</option>${options}</select></label><label>Cuenta destino<select name="destination_account_id" required><option value="">Selecciona</option>${options}</select></label><label>Valor<input name="amount" type="number" min="1" step="1" required></label><label>Fecha y hora<input name="occurred_at" type="datetime-local" value="${dateTimeInputValue()}" required></label><label class="full">Descripción<textarea name="description" rows="3" required placeholder="Ejemplo: traslado de efectivo a Nequi"></textarea></label><div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary">Transferir</button></div></form>`);
  $('#financialTransferForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.currentTarget));
    try {
      const source = accounts.find((item) => item.id === data.source_account_id);
      const destination = accounts.find((item) => item.id === data.destination_account_id);
      const amount = Number(data.amount);
      if (!source || !destination) throw new Error('Selecciona ambas cuentas.');
      if (source.id === destination.id) throw new Error('Las cuentas deben ser diferentes.');
      if (!(amount > 0)) throw new Error('El valor debe ser mayor que cero.');
      if (amount > Number(source.current_balance || 0)) throw new Error('La cuenta origen no tiene saldo suficiente.');
      const accepted = await confirmAction({ title: 'Transferir dinero', message: 'El total de LIHEN no cambiará; solo se moverá dinero entre cuentas.', confirmLabel: 'Transferir', details: [{ label: 'Origen', value: source.name }, { label: 'Destino', value: destination.name }, moneyDetail('Valor', amount), moneyDetail('Saldo origen posterior', Number(source.current_balance) - amount), moneyDetail('Saldo destino posterior', Number(destination.current_balance) + amount)] });
      if (!accepted) return;
      await transferFinancialFunds({ sourceAccountId: source.id, destinationAccountId: destination.id, amount, description: data.description, occurredAt: new Date(data.occurred_at).toISOString(), operationKey: createOperationKey('transferencia_cuentas') });
      closeModal(); toast('Transferencia registrada.'); document.dispatchEvent(new CustomEvent('lihen:refresh'));
    } catch (error) { toast(error.message, 'danger'); }
  });
}

export async function reverseMovement(movementId) {
  await loadFinancialAccounts();
  const movement = state.financialMovements.find((item) => item.id === movementId);
  if (!movement) return toast('Movimiento no encontrado.', 'danger');
  const reason = window.prompt('Escribe el motivo de la reversión:')?.trim();
  if (!reason) return;
  try {
    const accepted = await confirmAction({ title: 'Reversar movimiento', message: 'El movimiento original se conservará y se creará un movimiento inverso.', confirmLabel: 'Reversar', tone: 'danger', details: [{ label: 'Cuenta', value: movement.account?.name || 'Cuenta' }, { label: 'Tipo', value: String(movement.movement_type || '').replaceAll('_',' ') }, moneyDetail('Valor', movement.amount), { label: 'Motivo', value: reason }] });
    if (!accepted) return;
    await reverseFinancialMovement({ movementId, reason, operationKey: createOperationKey('reversion_movimiento') });
    toast('Movimiento reversado.'); document.dispatchEvent(new CustomEvent('lihen:refresh'));
  } catch (error) { toast(error.message, 'danger'); }
}
