import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function listSupplierPurchases(supplierId = null) {
  let query = supabase
    .from('supplier_requests')
    .select('*,supplier:suppliers(id,business_name),items:supplier_request_items(*,product:products(id,name,sku,catalog_code)),payments:supplier_payments(id,amount,status,payment_date,account:financial_accounts(id,name,code))')
    .order('created_at', { ascending: false });
  if (supplierId) query = query.eq('supplier_id', supplierId);
  return unwrap(await query, 'No fue posible cargar las compras del proveedor.') || [];
}

export async function createSupplierPurchase(payload) {
  return unwrap(await supabase.rpc('create_supplier_purchase_atomic', {
    p_supplier_id: payload.supplierId,
    p_purchase_date: payload.purchaseDate,
    p_expected_date: payload.expectedDate || null,
    p_invoice_number: payload.invoiceNumber || null,
    p_due_date: payload.dueDate || null,
    p_discount_amount: payload.discountAmount || 0,
    p_tax_amount: payload.taxAmount || 0,
    p_freight_amount: payload.freightAmount || 0,
    p_notes: payload.notes || null,
    p_items: payload.items,
    p_operation_key: payload.operationKey
  }), 'No fue posible registrar la compra al proveedor.');
}

export async function confirmSupplierPurchase(id, operationKey) {
  return unwrap(await supabase.rpc('confirm_supplier_purchase_atomic', {
    p_supplier_request_id: id,
    p_operation_key: operationKey
  }), 'No fue posible confirmar la compra.');
}

export async function receiveSupplierPurchase(id, items, notes, operationKey) {
  return unwrap(await supabase.rpc('receive_supplier_purchase_v2_atomic', {
    p_supplier_request_id: id,
    p_items: items,
    p_notes: notes || null,
    p_operation_key: operationKey
  }), 'No fue posible registrar la recepción.');
}

export async function registerSupplierPayment(payload) {
  return unwrap(await supabase.rpc('register_supplier_payment_atomic', {
    p_supplier_request_id: payload.purchaseId,
    p_account_id: payload.accountId,
    p_amount: payload.amount,
    p_payment_method: payload.paymentMethod,
    p_paid_at: payload.paidAt,
    p_reference_number: payload.referenceNumber || null,
    p_notes: payload.notes || null,
    p_operation_key: payload.operationKey
  }), 'No fue posible registrar el pago al proveedor.');
}


export async function createHistoricalSupplierPurchase(payload) {
  return unwrap(await supabase.rpc('register_historical_supplier_purchase_atomic', {
    p_supplier_id: payload.supplierId,
    p_purchase_date: payload.purchaseDate,
    p_invoice_number: payload.invoiceNumber || null,
    p_due_date: payload.dueDate || null,
    p_discount_amount: payload.discountAmount || 0,
    p_tax_amount: payload.taxAmount || 0,
    p_freight_amount: payload.freightAmount || 0,
    p_historical_paid_amount: payload.historicalPaidAmount || 0,
    p_historical_payment_method: payload.historicalPaymentMethod || null,
    p_historical_payment_date: payload.historicalPaymentDate || null,
    p_source_reference: payload.sourceReference || null,
    p_notes: payload.notes || null,
    p_items: payload.items,
    p_operation_key: payload.operationKey
  }), 'No fue posible registrar la compra histórica.');
}
