import { supabase } from '../supabase.js';
import { assertAll } from './helpers.js';

export async function fetchReportSources() {
  const results = await Promise.all([
    supabase.from('orders').select('id,status,total,discount_amount,delivery_cost,created_at,payment_status').order('created_at',{ascending:true}).limit(2000),
    supabase.from('order_items').select('quantity,line_total,product_name_snapshot,product_id').limit(5000),
    supabase.from('quick_sales').select('id,status,total,created_at,payment_method').limit(5000),
    supabase.from('quick_sale_items').select('quantity,line_total,product_name_snapshot,product_id').limit(10000),
    supabase.from('products').select('id,name,current_cost,sale_price,visible_on_website').limit(1000),
    supabase.from('suppliers').select('id,business_name,active').limit(500)
  ]);
  const [orders, orderItems, quickSales, quickSaleItems, products, suppliers] = assertAll(results, 'No fue posible cargar los reportes.');
  return { orders, orderItems, quickSales, quickSaleItems, products, suppliers };
}
