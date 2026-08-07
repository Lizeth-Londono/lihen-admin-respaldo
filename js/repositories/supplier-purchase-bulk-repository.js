import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

async function paged(table, select, order = 'created_at') {
  const rows = []; let from = 0; const size = 1000;
  while (true) {
    const result = await supabase.from(table).select(select).order(order, { ascending:false }).range(from, from + size - 1);
    const data = unwrap(result, `No fue posible consultar ${table}.`) || [];
    rows.push(...data); if (data.length < size) break; from += size;
  }
  return rows;
}

export async function fetchSupplierPurchaseExportData() {
  const [suppliers, purchases, accounts] = await Promise.all([
    paged('suppliers', 'id,business_name,contact_name,whatsapp,city,active,supplier_products(product_id)'),
    paged('supplier_requests', '*,supplier:suppliers(id,business_name),items:supplier_request_items(*,product:products(id,sku,name,category,brand)),payments:supplier_payments(*,account:financial_accounts(id,name))'),
    paged('financial_accounts', 'id,name,code,active')
  ]);
  return { suppliers, purchases, accounts };
}

export async function importSupplierPurchasesBatch(payload) {
  return unwrap(await supabase.rpc('import_supplier_purchases_batch_atomic', { p_payload: payload, p_operation_key: payload.operation_key }), 'No fue posible aplicar la importación masiva de compras.');
}
