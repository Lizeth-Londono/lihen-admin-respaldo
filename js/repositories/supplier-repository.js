import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function listSuppliers(search = '', limit = 300) {
  let query = supabase.from('suppliers').select('*,supplier_products(id,preferred,product:products(id,name))').order('business_name');
  if (search) query = query.or(`business_name.ilike.%${search}%,whatsapp.ilike.%${search}%`);
  return unwrap(await query.limit(limit), 'No fue posible cargar los proveedores.') || [];
}

export async function createSupplier(payload) {
  return unwrap(await supabase.from('suppliers').insert(payload), 'No fue posible crear el proveedor.');
}

export async function updateSupplier(id, payload) {
  return unwrap(await supabase.from('suppliers').update(payload).eq('id', id).select('id').maybeSingle(), 'No fue posible actualizar el proveedor.');
}
