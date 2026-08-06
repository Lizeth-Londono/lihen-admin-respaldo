import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function listCustomers(search = '', limit = 300) {
  let query = supabase.from('customers').select('*,addresses:customer_addresses(*)').order('full_name');
  if (search) query = query.or(`full_name.ilike.%${search}%,whatsapp.ilike.%${search}%`);
  return unwrap(await query.limit(limit), 'No fue posible cargar los clientes.') || [];
}

export async function createCustomer(payload) {
  return unwrap(await supabase.from('customers').insert(payload).select().single(), 'No fue posible crear el cliente.');
}

export async function updateCustomer(id, payload) {
  return unwrap(await supabase.from('customers').update(payload).eq('id', id).select('id').maybeSingle(), 'No fue posible actualizar el cliente.');
}

export async function createAddress(payload) {
  return unwrap(await supabase.from('customer_addresses').insert(payload), 'No fue posible guardar la dirección.');
}

export async function updateAddress(id, payload) {
  return unwrap(await supabase.from('customer_addresses').update(payload).eq('id', id), 'No fue posible actualizar la dirección.');
}
