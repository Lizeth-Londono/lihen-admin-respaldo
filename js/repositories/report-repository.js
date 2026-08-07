import { supabase } from '../supabase.js';
import { assertAll } from './helpers.js';

export async function fetchReportSources() {
  const results = await Promise.all([
    supabase.from('orders').select('id,order_number,status,total,created_at,payment_status,reconstruction_archived,is_historical,financial_impact').order('created_at', { ascending: true }),
    supabase.from('order_items').select('order_id,quantity,line_total,unit_price,product_name_snapshot,product_id'),
    supabase.from('quick_sales').select('id,sale_number,status,total,created_at,payment_method,reconstruction_archived,is_historical,financial_impact'),
    supabase.from('quick_sale_items').select('sale_id,quantity,line_total,unit_price,product_name_snapshot,product_id'),
    supabase.from('products').select('id,name,current_cost,sale_price,visible_on_website,business_line,product_type'),
    supabase.from('suppliers').select('id,business_name,active'),
    supabase.from('supplier_requests').select('id,supplier_id,status,purchase_date,due_date,payment_status,reception_status,total_amount,amount_paid,balance_due,supplier:suppliers(id,business_name),is_historical,inventory_impact,financial_impact'),
    supabase.from('supplier_request_items').select('supplier_request_id,product_id,requested_quantity,received_quantity,quoted_unit_cost'),
    supabase.from('supplier_payments').select('id,supplier_request_id,supplier_id,financial_account_id,amount,payment_date,status,account:financial_accounts(id,name,code)'),
    supabase.from('financial_accounts').select('id,code,name,account_type,current_balance,initial_balance_configured,active'),
    supabase.from('financial_movements').select('id,account_id,movement_type,category,amount,occurred_at,source_type,source_id,status,reporting_excluded,account:financial_accounts(id,name,code)').order('occurred_at', { ascending: false }),
    supabase.from('product_cost_history').select('product_id,new_product_cost,purchased_unit_cost,created_at').order('created_at', { ascending: true })
  ]);
  const [orders, orderItems, quickSales, quickSaleItems, products, suppliers, supplierPurchases, supplierPurchaseItems, supplierPayments, financialAccounts, financialMovements, productCostHistory] = assertAll(results, 'No fue posible cargar los reportes.');
  return { orders, orderItems, quickSales, quickSaleItems, products, suppliers, supplierPurchases, supplierPurchaseItems, supplierPayments, financialAccounts, financialMovements, productCostHistory };
}
