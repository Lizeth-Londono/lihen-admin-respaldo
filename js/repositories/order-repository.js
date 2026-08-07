import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';
import { ensureOperationKey } from '../services/operation-key-service.js';

const ORDER_SELECT = '*,customer:customers(id,full_name,whatsapp),items:order_items(id,product_id,variant_id,variant_snapshot,quantity,unit_price,line_total,product_name_snapshot,quantity_from_stock,quantity_to_source,quantity_reserved,quantity_received)';

export async function listOrders(search = '', limit = 200) {
  let query = supabase.from('orders').select(ORDER_SELECT).eq('reconstruction_archived', false).order('created_at', { ascending: false });
  if (search) query = query.or(`order_number.ilike.%${search}%`);
  return unwrap(await query.limit(limit), 'No fue posible cargar los pedidos.') || [];
}

export async function getOrderById(id) {
  return unwrap(await supabase.from('orders').select(ORDER_SELECT).eq('id', id).single(), 'No fue posible cargar el pedido.');
}

export async function createOrderAtomic(payload) {
  return unwrap(await supabase.rpc('create_order_atomic_idempotent', ensureOperationKey(payload, 'crear_pedido')), 'No fue posible crear el pedido.');
}

export async function updateOrderAtomic(payload) {
  return unwrap(await supabase.rpc('update_order_atomic_v2', payload), 'No fue posible actualizar el pedido.');
}

export async function listSavedOrderItems(orderId) {
  return unwrap(await supabase.from('order_items').select('id,order_id,product_id,variant_id,quantity,unit_price,line_total,product_name_snapshot').eq('order_id', orderId), 'No fue posible verificar los productos guardados.') || [];
}


export async function closeOrderDirectAtomic(payload) {
  return unwrap(
    await supabase.rpc('close_order_direct_financial_atomic_idempotent', ensureOperationKey(payload, 'cerrar_pedido_directo')),
    'No fue posible registrar el pago y la entrega del pedido.'
  );
}


export async function createHistoricalOrderAtomic(payload) {
  return unwrap(await supabase.rpc('create_historical_order_inventory_atomic_idempotent', ensureOperationKey(payload, 'crear_pedido_historico')), 'No fue posible registrar el pedido histórico.');
}
