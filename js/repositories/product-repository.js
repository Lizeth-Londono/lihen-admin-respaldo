import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

const PRODUCT_SELECT = '*,inventory(id,physical_stock,reserved_stock,available_stock,pending_stock,average_cost),product_images(id,public_url,is_main,sort_order),supplier_products(preferred,supplier:suppliers(id,business_name,whatsapp))';

export async function listProducts(search = '', limit = 300) {
  let query = supabase.from('products').select(PRODUCT_SELECT).order('name');
  if (search) query = query.ilike('name', `%${search}%`);
  return unwrap(await query.limit(limit), 'No fue posible cargar los productos.') || [];
}

export async function findProductBySku(sku, excludedId = null) {
  let query = supabase.from('products').select('id,name').ilike('sku', sku);
  if (excludedId) query = query.neq('id', excludedId);
  return unwrap(await query.maybeSingle(), 'No fue posible validar el SKU.');
}

export async function createProduct(payload) {
  return unwrap(await supabase.from('products').insert(payload).select().single(), 'No fue posible crear el producto.');
}

export async function createProductAtomic({ product, initialPhysicalStock = 0, supplierId = null }) {
  return unwrap(await supabase.rpc('create_product_atomic', {
    p_product: product,
    p_initial_physical_stock: Number(initialPhysicalStock) || 0,
    p_supplier_id: supplierId || null
  }), 'No fue posible crear el producto de forma atómica.');
}

export async function updateProduct(id, payload) {
  return unwrap(await supabase.from('products').update(payload).eq('id', id).select('id,name,status,visible_on_website').maybeSingle(), 'No fue posible actualizar el producto.');
}

export async function upsertCatalogProducts(rows) {
  return unwrap(await supabase.from('products').upsert(rows, { onConflict: 'catalog_code' }), 'No fue posible importar el catálogo.');
}
