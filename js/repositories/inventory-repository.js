import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function listMovements(limit = 300) {
  return unwrap(await supabase.from('inventory_movements').select('*,inventory(product:products(name)),user:profiles(full_name),order:orders(order_number),supplier_request:supplier_requests(request_number)').order('created_at', { ascending: false }).limit(limit), 'No fue posible cargar los movimientos.') || [];
}

export async function createInventory(payload) {
  return unwrap(await supabase.from('inventory').insert(payload), 'No fue posible crear el inventario.');
}

export async function adjustInventoryAtomic(payload) {
  return unwrap(await supabase.rpc('adjust_inventory_atomic', payload), 'No fue posible ajustar el inventario.');
}
