import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

const ORDER_SELECT = '*,customer:customers(id,full_name,whatsapp),items:order_items(id,product_id,variant_id,variant_snapshot,quantity,unit_price,line_total,product_name_snapshot,quantity_from_stock,quantity_to_source,quantity_reserved,quantity_received)';

export async function listOrders(search = '', limit = 200) {
  let query = supabase.from('orders').select(ORDER_SELECT).order('created_at', { ascending: false });
  if (search) query = query.or(`order_number.ilike.%${search}%`);
  return unwrap(await query.limit(limit), 'No fue posible cargar los pedidos.') || [];
}

export async function getOrderById(id) {
  return unwrap(await supabase.from('orders').select(ORDER_SELECT).eq('id', id).single(), 'No fue posible cargar el pedido.');
}

export async function createOrderAtomic(payload) {
  return unwrap(await supabase.rpc('create_order_atomic', payload), 'No fue posible crear el pedido.');
}

export async function updateOrderAtomic(payload) {
  return unwrap(await supabase.rpc('update_order_atomic_v2', payload), 'No fue posible actualizar el pedido.');
}

export async function listSavedOrderItems(orderId) {
  return unwrap(await supabase.from('order_items').select('id,order_id,product_id,variant_id,quantity,unit_price,line_total,product_name_snapshot').eq('order_id', orderId), 'No fue posible verificar los productos guardados.') || [];
}
