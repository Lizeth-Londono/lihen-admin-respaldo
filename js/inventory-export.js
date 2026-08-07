import { supabase } from './supabase.js';
import { toast } from './ui.js';
import { INVENTORY_HEADERS, INVENTORY_TEMPLATE_VERSION } from './services/inventory-workbook-service.js';

let xlsxLoadPromise = null;
async function ensureXlsx() {
  if (window.XLSX) return window.XLSX;
  if (!xlsxLoadPromise) {
    xlsxLoadPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';
      script.async = true;
      script.onload = () => window.XLSX ? resolve(window.XLSX) : reject(new Error('El generador de Excel no quedó disponible.'));
      script.onerror = () => reject(new Error('No se pudo cargar el generador de Excel. Revisa la conexión.'));
      document.head.appendChild(script);
    }).catch(error => { xlsxLoadPromise = null; throw error; });
  }
  return xlsxLoadPromise;
}

function safe(value) {
  const text = value == null ? '' : String(value);
  return /^[=+@-]/.test(text) ? `'${text}` : text;
}

function productStatus(product) {
  const status = String(product?.status ?? '').trim().toLowerCase();
  if (status === 'inactivo' || product?.active === false) return 'Inactivo';
  return 'Activo';
}

export async function exportCurrentInventory() {
  const XLSXLib = await ensureXlsx();
  const rows = [];
  let from = 0;
  const pageSize = 1000;
  while (true) {
    const { data, error } = await supabase
      .from('products')
      .select('*,inventory(*),supplier_products(preferred,supplier:suppliers(business_name))')
      .order('sku')
      .range(from, from + pageSize - 1);
    if (error) throw error;
    rows.push(...(data || []));
    if (!data || data.length < pageSize) break;
    from += pageSize;
  }

  const mapped = rows.map(product => {
    const inventory = product.inventory?.[0] || {};
    const supplier = product.supplier_products?.find(item => item.preferred)?.supplier?.business_name
      || product.supplier_products?.[0]?.supplier?.business_name
      || '';
    return {
      'ID interno': safe(product.id),
      'SKU': safe(product.sku),
      'Línea de negocio': safe(product.business_line),
      'Categoría / tipo': safe(product.category),
      'Subcategoría': safe(product.subcategory),
      'Producto': safe(product.name),
      'Marca': safe(product.brand),
      'Proveedor': safe(supplier),
      'Descripción': safe(product.description),
      'Costo real unitario': Number(product.current_cost || 0),
      'Precio sugerido LIHEN': Number(product.sale_price || 0),
      'Stock actual': Number(inventory.physical_stock || 0),
      'Stock reservado': Number(inventory.reserved_stock || 0),
      'Stock disponible': Number(inventory.available_stock ?? Math.max(0, Number(inventory.physical_stock || 0) - Number(inventory.reserved_stock || 0))),
      'Stock pendiente': Number(inventory.pending_stock || 0),
      'Stock mínimo': Number(product.minimum_stock || 0),
      'Visible en catálogo': product.visible_on_website ? 'Sí' : 'No',
      'Estado producto': productStatus(product),
      'Código catálogo': safe(product.catalog_code)
    };
  });

  const workbook = XLSXLib.utils.book_new();
  workbook.Props = {
    Title: 'Inventario actual de LIHEN.CO',
    Subject: 'Plantilla editable y reimportable de inventario',
    Author: 'LIHEN.CO',
    Comments: INVENTORY_TEMPLATE_VERSION
  };
  const instructions = XLSXLib.utils.aoa_to_sheet([
    ['Plantilla', INVENTORY_TEMPLATE_VERSION],
    ['Uso', 'Edite únicamente las columnas permitidas y vuelva a importar el archivo.'],
    ['Identificación', 'Los productos existentes se identifican primero por ID interno y después por SKU.'],
    ['Celdas vacías', 'Una celda vacía conserva el valor actual; un cero escrito expresamente sí propone actualizar a cero.'],
    ['Columnas protegidas', 'No edite ID interno, Stock reservado, Stock disponible ni Stock pendiente. Son campos informativos.'],
    ['Importante', 'Los productos ausentes del archivo no serán eliminados, ocultados ni desactivados.']
  ]);
  instructions['!cols'] = [{ wch: 22 }, { wch: 110 }];
  XLSXLib.utils.book_append_sheet(workbook, instructions, 'Instrucciones');

  const sheet = XLSXLib.utils.json_to_sheet(mapped, { header: INVENTORY_HEADERS });
  sheet['!autofilter'] = { ref: `A1:S${Math.max(1, mapped.length + 1)}` };
  sheet['!freeze'] = { xSplit: 0, ySplit: 1, topLeftCell: 'A2', activePane: 'bottomLeft', state: 'frozen' };
  sheet['!cols'] = [
    { wch: 38 }, { wch: 14 }, { wch: 18 }, { wch: 25 }, { wch: 20 }, { wch: 34 }, { wch: 20 }, { wch: 30 }, { wch: 52 },
    { wch: 20 }, { wch: 22 }, { wch: 14 }, { wch: 16 }, { wch: 16 }, { wch: 15 }, { wch: 14 }, { wch: 18 }, { wch: 16 }, { wch: 18 }
  ];
  XLSXLib.utils.book_append_sheet(workbook, sheet, 'Inventario');

  const date = new Date().toISOString().slice(0, 10);
  XLSXLib.writeFile(workbook, `Inventario_Actual_LIHEN_${date}.xlsx`, { compression: true });
  toast(`Inventario exportado: ${mapped.length} productos.`);
}
