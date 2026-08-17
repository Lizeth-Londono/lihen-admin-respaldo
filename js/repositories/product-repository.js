import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

const PRODUCT_SELECT = '*,inventory(id,physical_stock,reserved_stock,available_stock,pending_stock,average_cost),product_images(id,public_url,is_main,sort_order),supplier_products(preferred,supplier:suppliers(id,business_name,whatsapp))';
const PRODUCT_PAGE_SIZE = 200;

/**
 * Carga el catálogo administrativo completo por páginas.
 *
 * Antes esta consulta aplicaba limit(300), por lo que state.products y todos
 * los selectores/buscadores que dependen de él quedaban truncados a 300 filas.
 * La paginación evita depender de un límite arbitrario y mantiene un orden
 * estable (nombre + id) entre páginas.
 */
export async function listProducts(search = '') {
  const products = [];
  const normalizedSearch = String(search || '').trim();
  let from = 0;

  while (true) {
    let query = supabase
      .from('products')
      .select(PRODUCT_SELECT)
      .order('name')
      .order('id')
      .range(from, from + PRODUCT_PAGE_SIZE - 1);

    // Se conserva compatibilidad con los consumidores que usan búsqueda remota.
    // El buscador de Inventario carga todo el catálogo y filtra localmente por
    // nombre, SKU, código catálogo, marca y categoría (ver views.js/main.js).
    if (normalizedSearch) query = query.ilike('name', `%${normalizedSearch}%`);

    const page = unwrap(await query, 'No fue posible cargar los productos.') || [];
    products.push(...page);

    if (page.length < PRODUCT_PAGE_SIZE) break;
    from += PRODUCT_PAGE_SIZE;
  }

  return products;
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
