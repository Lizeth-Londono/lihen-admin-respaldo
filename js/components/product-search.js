import { escapeHtml } from '../utils.js';

let productSearchInstance = 0;

export function normalizeProductSearch(value = '') {
  return String(value ?? '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

export function productSearchText(product = {}) {
  return normalizeProductSearch([
    product.name,
    product.sku,
    product.catalog_code,
    product.brand,
    product.category,
    product.subcategory
  ].filter(Boolean).join(' '));
}

export function filterProductMatches(products = [], query = '', limit = 20) {
  const normalized = normalizeProductSearch(query);
  const source = normalized
    ? products.filter((product) => productSearchText(product).includes(normalized))
    : products;
  return source.slice(0, Math.max(1, Number(limit) || 20));
}

function stockOf(product) {
  return Number(product?.inventory?.[0]?.available_stock) || 0;
}

function resultMarkup(product, index, activeIndex, showPrice) {
  const sku = product.sku || product.catalog_code || 'Sin SKU';
  const price = Number(product.sale_price) || 0;
  return `<button type="button" class="product-search-option${index === activeIndex ? ' is-active' : ''}" role="option" aria-selected="${index === activeIndex ? 'true' : 'false'}" data-product-result="${escapeHtml(product.id)}">
    <span class="product-search-option-main"><b>${escapeHtml(product.name || 'Producto')}</b><small>${escapeHtml(sku)} · Stock ${stockOf(product)}</small></span>
    ${showPrice ? `<span class="product-search-option-price">$ ${new Intl.NumberFormat('es-CO', { maximumFractionDigits: 0 }).format(price)}</span>` : ''}
  </button>`;
}

/**
 * Combobox reutilizable de productos. Busca localmente sobre el catálogo ya
 * cargado en state.products; no hace consultas por tecla ni altera negocio.
 */
export function createProductSearch({
  mount,
  products = [],
  placeholder = 'Buscar producto por nombre o SKU',
  selectedProductId = '',
  fieldName = '',
  maxResults = 20,
  showPrice = false,
  onSelect = () => {},
  onClear = () => {}
} = {}) {
  if (!mount) throw new Error('createProductSearch requiere un contenedor válido.');

  productSearchInstance += 1;
  const listboxId = `product-search-listbox-${productSearchInstance}`;
  mount.classList.add('product-search-mount');
  mount.innerHTML = `<div class="product-search-combobox">
    <input class="product-search-input" type="search" autocomplete="off" spellcheck="false" placeholder="${escapeHtml(placeholder)}" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="${listboxId}" aria-activedescendant="">
    ${fieldName ? `<input type="hidden" name="${escapeHtml(fieldName)}" value="">` : ''}
    <button type="button" class="product-search-clear" aria-label="Limpiar producto" title="Cambiar producto" hidden>×</button>
    <div class="product-search-results" id="${listboxId}" role="listbox" hidden></div>
  </div>`;

  const input = mount.querySelector('.product-search-input');
  const hidden = fieldName ? mount.querySelector('input[type="hidden"]') : null;
  const results = mount.querySelector('.product-search-results');
  const clearButton = mount.querySelector('.product-search-clear');
  let currentProducts = Array.isArray(products) ? products : [];
  let selected = null;
  let matches = [];
  let activeIndex = -1;

  const close = () => {
    results.hidden = true;
    input.setAttribute('aria-expanded', 'false');
    input.setAttribute('aria-activedescendant', '');
    activeIndex = -1;
  };

  const renderResults = () => {
    matches = filterProductMatches(currentProducts, input.value, maxResults);
    activeIndex = matches.length ? Math.min(Math.max(activeIndex, 0), matches.length - 1) : -1;
    const query = input.value.trim();
    results.innerHTML = matches.length
      ? matches.map((product, index) => resultMarkup(product, index, activeIndex, showPrice)).join('')
      : `<div class="product-search-empty">No encontramos productos para “${escapeHtml(query)}”.</div>`;
    results.hidden = false;
    input.setAttribute('aria-expanded', 'true');
    input.setAttribute('aria-activedescendant', activeIndex >= 0 ? `${listboxId}-option-${activeIndex}` : '');
    [...results.querySelectorAll('[data-product-result]')].forEach((button, index) => {
      button.id = `${listboxId}-option-${index}`;
    });
  };

  const clear = ({ notify = true, focus = false } = {}) => {
    selected = null;
    if (hidden) hidden.value = '';
    input.value = '';
    input.removeAttribute('data-selected-product-id');
    input.readOnly = false;
    clearButton.hidden = true;
    close();
    if (notify) onClear();
    if (focus) {
      input.focus();
      renderResults();
    }
  };

  const select = (product, { notify = true } = {}) => {
    if (!product) return;
    selected = product;
    const sku = product.sku || product.catalog_code || 'Sin SKU';
    input.value = `${product.name || 'Producto'} · ${sku}`;
    input.dataset.selectedProductId = product.id;
    input.readOnly = true;
    if (hidden) hidden.value = product.id;
    clearButton.hidden = false;
    close();
    if (notify) onSelect(product);
  };

  const moveActive = (direction) => {
    if (results.hidden) renderResults();
    if (!matches.length) return;
    activeIndex = activeIndex < 0 ? 0 : (activeIndex + direction + matches.length) % matches.length;
    results.querySelectorAll('[data-product-result]').forEach((button, index) => {
      const active = index === activeIndex;
      button.classList.toggle('is-active', active);
      button.setAttribute('aria-selected', active ? 'true' : 'false');
      if (active) {
        input.setAttribute('aria-activedescendant', button.id);
        button.scrollIntoView({ block: 'nearest' });
      }
    });
  };

  input.addEventListener('focus', () => {
    if (!selected) renderResults();
  });
  input.addEventListener('input', () => {
    if (selected) clear({ notify: true });
    activeIndex = 0;
    renderResults();
  });
  input.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown') { event.preventDefault(); moveActive(1); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); moveActive(-1); }
    else if (event.key === 'Enter' && !results.hidden && activeIndex >= 0) {
      event.preventDefault(); select(matches[activeIndex]);
    } else if (event.key === 'Escape') {
      event.preventDefault(); close();
    }
  });
  results.addEventListener('mousedown', (event) => {
    const button = event.target.closest('[data-product-result]');
    if (!button) return;
    event.preventDefault();
    select(currentProducts.find((product) => String(product.id) === button.dataset.productResult));
  });
  clearButton.addEventListener('click', () => clear({ notify: true, focus: true }));
  mount.addEventListener('focusout', () => {
    setTimeout(() => { if (!mount.contains(document.activeElement)) close(); }, 0);
  });

  const initial = currentProducts.find((product) => String(product.id) === String(selectedProductId));
  if (initial) select(initial, { notify: false });

  return {
    clear,
    select,
    getSelected: () => selected,
    getSelectedId: () => selected?.id || '',
    setProducts(nextProducts = []) { currentProducts = Array.isArray(nextProducts) ? nextProducts : []; },
    focus() { input.focus(); },
    input,
    hidden
  };
}
