import { supabase } from './supabase.js';
import { toast } from './ui.js';

const HEADERS = ['ID interno','SKU','Línea de negocio','Categoría / tipo','Subcategoría','Producto','Marca','Proveedor','Descripción','Costo real unitario','Precio sugerido LIHEN','Stock actual','Stock reservado','Stock disponible','Stock pendiente','Stock mínimo','Visible en catálogo','Estado producto','Código catálogo'];

function safe(value) {
  const text = value == null ? '' : String(value);
  return /^[=+@-]/.test(text) ? `'${text}` : text;
}

export async function exportCurrentInventory() {
  if (!window.XLSX) throw new Error('No está disponible la librería para generar Excel.');
  const rows = [];
  let from = 0;
  const pageSize = 1000;
  while (true) {
    const { data, error } = await supabase.from('products').select('*,inventory(*),supplier_products(preferred,supplier:suppliers(business_name))').order('sku').range(from, from + pageSize - 1);
    if (error) throw error;
    rows.push(...(data || []));
    if (!data || data.length < pageSize) break;
    from += pageSize;
  }
  const mapped = rows.map(product => {
    const inventory = product.inventory?.[0] || {};
    const supplier = product.supplier_products?.find(item => item.preferred)?.supplier?.business_name || product.supplier_products?.[0]?.supplier?.business_name || '';
    return {
      'ID interno': safe(product.id), 'SKU': safe(product.sku), 'Línea de negocio': safe(product.business_line),
      'Categoría / tipo': safe(product.category), 'Subcategoría': safe(product.subcategory), 'Producto': safe(product.name),
      'Marca': safe(product.brand), 'Proveedor': safe(supplier), 'Descripción': safe(product.description),
      'Costo real unitario': Number(product.current_cost || 0), 'Precio sugerido LIHEN': Number(product.sale_price || 0),
      'Stock actual': Number(inventory.physical_stock || 0), 'Stock reservado': Number(inventory.reserved_stock || 0),
      'Stock disponible': Number(inventory.available_stock ?? Math.max(0, Number(inventory.physical_stock || 0)-Number(inventory.reserved_stock || 0))),
      'Stock pendiente': Number(inventory.pending_stock || 0), 'Stock mínimo': Number(inventory.minimum_stock || 0),
      'Visible en catálogo': product.visible_on_website ? 'Sí' : 'No', 'Estado producto': product.active === false ? 'Inactivo' : 'Activo',
      'Código catálogo': safe(product.catalog_code)
    };
  });
  const workbook = XLSX.utils.book_new();
  const instructions = XLSX.utils.aoa_to_sheet([
    ['Plantilla','LIHEN-INVENTARIO-V1'],['Uso','Edite únicamente las columnas permitidas y vuelva a importar el archivo.'],
    ['Importante','No elimine ni cambie el ID interno de productos existentes. Los productos ausentes no serán eliminados.']
  ]);
  XLSX.utils.book_append_sheet(workbook, instructions, 'Instrucciones');
  const sheet = XLSX.utils.json_to_sheet(mapped, { header: HEADERS });
  sheet['!autofilter'] = { ref: `A1:S${Math.max(1,mapped.length+1)}` };
  XLSX.utils.book_append_sheet(workbook, sheet, 'Inventario');
  const date = new Date().toISOString().slice(0,10);
  XLSX.writeFile(workbook, `Inventario_Actual_LIHEN_${date}.xlsx`);
  toast(`Inventario exportado: ${mapped.length} productos.`);
}
