import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function listFinancialAccounts() {
  return unwrap(await supabase.from('financial_accounts').select('*').order('name'), 'No fue posible cargar las cuentas.') || [];
}

export async function listFinancialMovements(limit = 200) {
  return unwrap(await supabase.from('financial_movements').select('*,account:financial_accounts(id,name,code)').order('occurred_at',{ascending:false}).limit(limit), 'No fue posible cargar los movimientos financieros.') || [];
}

export async function configureInitialBalance(payload) {
  return unwrap(await supabase.rpc('configure_initial_balance_atomic', {
    p_account_id: payload.accountId,
    p_amount: payload.amount,
    p_effective_date: payload.effectiveDate,
    p_reason: payload.reason,
    p_operation_key: payload.operationKey
  }), 'No fue posible configurar el saldo inicial.');
}

export async function registerFinancialMovement(payload) {
  return unwrap(await supabase.rpc('register_financial_movement_atomic', {
    p_account_id: payload.accountId,
    p_movement_type: payload.type,
    p_amount: payload.amount,
    p_category: payload.category,
    p_description: payload.description,
    p_occurred_at: payload.occurredAt,
    p_operation_key: payload.operationKey
  }), 'No fue posible registrar el movimiento financiero.');
}


export async function transferFinancialFunds(payload) {
  return unwrap(await supabase.rpc('transfer_financial_funds_atomic', {
    p_source_account_id: payload.sourceAccountId,
    p_destination_account_id: payload.destinationAccountId,
    p_amount: payload.amount,
    p_description: payload.description,
    p_occurred_at: payload.occurredAt,
    p_operation_key: payload.operationKey
  }), 'No fue posible transferir el dinero.');
}

export async function reverseFinancialMovement(payload) {
  return unwrap(await supabase.rpc('reverse_financial_movement_atomic', {
    p_movement_id: payload.movementId,
    p_reason: payload.reason,
    p_operation_key: payload.operationKey
  }), 'No fue posible reversar el movimiento.');
}
