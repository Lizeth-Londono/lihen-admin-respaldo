import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function listQuickSales(search = '', limit = 300) {
  let query = supabase.from('quick_sales').select('*,customer:customers(id,full_name,whatsapp),items:quick_sale_items(*)').order('created_at', { ascending: false });
  if (search) query = query.or(`sale_number.ilike.%${search}%`);
  return unwrap(await query.limit(limit), 'No fue posible cargar las ventas rápidas.') || [];
}

export async function createQuickSaleAtomic(payload) {
  return unwrap(await supabase.rpc('create_quick_sale_atomic', payload), 'No fue posible registrar la venta rápida.');
}

export async function cancelQuickSaleAtomic(payload) {
  return unwrap(await supabase.rpc('cancel_quick_sale_atomic', payload), 'No fue posible anular la venta rápida.');
}
