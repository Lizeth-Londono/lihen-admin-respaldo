import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { normalizeProductSearch, filterProductMatches } from '../js/components/product-search.js';

const component = readFileSync(new URL('../js/components/product-search.js', import.meta.url), 'utf8');
const sales = readFileSync(new URL('../js/sales.js', import.meta.url), 'utf8');
const orders = readFileSync(new URL('../js/order-workflow.js', import.meta.url), 'utf8');
const purchases = readFileSync(new URL('../js/supplier-purchases.js', import.meta.url), 'utf8');
const views = readFileSync(new URL('../js/views.js', import.meta.url), 'utf8');
const css = readFileSync(new URL('../css/app.css', import.meta.url), 'utf8');

const products = [
  { id:'1', name:'Lápiz Delineador Cejas Samy', sku:'BC-081', brand:'Samy', inventory:[{available_stock:2}] },
  { id:'2', name:'ACEITE DE CASTOR', sku:'BC-359', brand:'LIHEN.CO', inventory:[{available_stock:0}] },
  { id:'3', name:'ACONDICIONADOR CERAMIDA', sku:'BC-085', inventory:[{available_stock:5}] },
  ...Array.from({length:30},(_,i)=>({id:`x${i}`,name:`Producto ${i}`,sku:`BC-${String(400+i).padStart(3,'0')}`}))
];

test('buscador normaliza mayúsculas y tildes', () => {
  assert.equal(normalizeProductSearch('  LÁPIZ  '), 'lapiz');
  assert.equal(filterProductMatches(products,'lapiz')[0].sku, 'BC-081');
  assert.equal(filterProductMatches(products,'ACEITE DE CASTOR')[0].sku, 'BC-359');
});

test('buscador encuentra por SKU y limita solo la visualización', () => {
  assert.equal(filterProductMatches(products,'BC-085')[0].name, 'ACONDICIONADOR CERAMIDA');
  assert.equal(filterProductMatches(products,'',20).length, 20);
  assert.equal(filterProductMatches(products,'BC-429',20)[0].sku, 'BC-429');
});

test('componente expone combobox accesible y navegación por teclado', () => {
  assert.match(component, /role=\"combobox\"/);
  assert.match(component, /role=\"listbox\"/);
  assert.match(component, /role=\"option\"/);
  assert.match(component, /ArrowDown/);
  assert.match(component, /ArrowUp/);
  assert.match(component, /Enter/);
  assert.match(component, /Escape/);
  assert.match(component, /No encontramos productos/);
});

test('venta rápida usa buscador escribible y conserva precio/stock', () => {
  assert.match(sales, /createProductSearch/);
  assert.match(sales, /saleProductSearch/);
  assert.match(sales, /selected\.inventory\?\.\[0\]\?\.available_stock/);
  assert.match(sales, /price\.value=Number\(product\.sale_price\)/);
  assert.doesNotMatch(sales, /id=\"saleProduct\"/);
});

test('crear pedido usa buscador escribible y conserva addProduct por id', () => {
  assert.match(orders, /createProductSearch/);
  assert.match(orders, /quickProductSearch/);
  assert.match(orders, /addProduct\(selected\.id/);
  assert.doesNotMatch(orders, /id=\"quickProduct\"/);
});

test('compra a proveedor monta un buscador independiente por fila', () => {
  assert.match(purchases, /data-purchase-product-search/);
  assert.match(purchases, /fieldName:'product_id'/);
  assert.match(purchases, /mountPurchaseProductSearch\(form\.querySelector\('\[data-purchase-item\]:last-child'\)\)/);
  assert.match(purchases, /input\[name=\"product_id\"\]/);
  assert.doesNotMatch(purchases, /select name=\"product_id\"/);
});

test('inventario conserva búsqueda por nombre y SKU del catálogo completo', () => {
  assert.match(views, /Buscar por nombre, SKU, código, marca o categoría/);
  assert.match(views, /p\.name,p\.sku,p\.catalog_code/);
});

test('dropdown global tiene límite visual, scroll y z-index dentro de modales', () => {
  assert.match(css, /\.product-search-results\{/);
  assert.match(css, /max-height:280px/);
  assert.match(css, /overflow-y:auto/);
  assert.match(css, /z-index:80/);
});
