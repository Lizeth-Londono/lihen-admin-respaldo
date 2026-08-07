import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function importInventoryBatchAtomic(payload) {
  return unwrap(
    await supabase.rpc('import_inventory_batch_atomic', payload),
    'No fue posible aplicar la importación de inventario.'
  );
}
