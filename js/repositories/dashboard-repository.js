import { supabase } from '../supabase.js';
import { assertAll } from './helpers.js';

export async function fetchDashboardSources() {
  const results = await Promise.all([
    supabase.from('orders').select('id,order_number,status,total,created_at,customer:customers(full_name)').order('created_at',{ascending:false}).limit(8),
    supabase.from('quick_sales').select('id,sale_number,status,total,payment_method,created_at,customer:customers(full_name)').order('created_at',{ascending:false}).limit(8),
    supabase.from('inventory').select('physical_stock,reserved_stock,available_stock,pending_stock,product:products(id,name,minimum_stock)').limit(500),
    supabase.from('products').select('id,status,visible_on_website').limit(500),
    supabase.from('customers').select('id',{count:'exact',head:true}),
    supabase.from('inventory_movements').select('id,movement_type,quantity,reason,created_at,product_inventory:inventory(product:products(name)),user:profiles(full_name)').order('created_at',{ascending:false}).limit(8)
  ]);
  const [orders, quickSales, inventory, products, customers, movements] = assertAll(results, 'No fue posible cargar el dashboard.');
  return { orders, quickSales, inventory, products, customerCount: results[4].count || 0, movements };
}
