import {
  state,
  loadSession,
  signIn,
  signOut,
  updatePassword,
  sendPasswordReset,
  isAuthCallback
} from './store.js';
import { $, $$ } from './utils.js';
import { errorMessage, withPendingButton } from './errors.js';
import { shell, login, passwordSetup, toast, closeModal, modal } from './ui.js';
import { renderRoute, showOrder } from './views.js';
import {
  newCustomer,
  newSupplier,
  newProduct,
  newOrder,
  importCatalog,
  inventoryAdjustment
} from './forms.js';
import { editCustomer, editSupplier, editProduct } from './editors.js';
import {
  importInventory,
  importBundledInventory,
  importSuppliers,
  importCustomers
} from './imports.js';
import { newQuickSale, quickSaleReceipt } from './sales.js';
import { exportCurrentInventory } from './inventory-export.js';
import { newSupplierPurchase, newHistoricalSupplierPurchase, viewSupplierPurchases } from './supplier-purchases.js';
import { importSupplierPurchases, exportSupplierPurchaseConsolidated, downloadSupplierPurchaseTemplate } from './supplier-purchase-bulk.js';
import { newFinancialMovement, configureAccountBalance, transferBetweenAccounts, reverseMovement } from './financial-accounts.js';
import { registerCommand, executeCommand } from './core/command-bus.js';
import { subscribe } from './core/event-bus.js';

if (window.__lihenBootTimer) clearTimeout(window.__lihenBootTimer);

const app = $('#app');

[
  ['new-order', newOrder],
  ['new-quick-sale', newQuickSale],
  ['new-product', newProduct],
  ['new-supplier', newSupplier],
  ['new-customer', newCustomer],
  ['import-catalog', importCatalog],
  ['import-inventory', importInventory],
  ['import-bundled-inventory', importBundledInventory],
  ['import-suppliers', importSuppliers],
  ['import-customers', importCustomers],
  ['inventory-adjustment', inventoryAdjustment],
  ['export-inventory', exportCurrentInventory],
  ['import-supplier-purchases', importSupplierPurchases],
  ['export-supplier-purchases', exportSupplierPurchaseConsolidated],
  ['download-supplier-purchase-template', downloadSupplierPurchaseTemplate],
  ['new-financial-movement', newFinancialMovement],
  ['transfer-financial-funds', transferBetweenAccounts],
  ['retry-route', refresh],
  ['generate-receipt', () => toast('Abre un pedido para generar su comprobante.', 'warning')]
].forEach(([name, handler]) => registerCommand(name, handler));


async function boot() {
  app.innerHTML = '<div class="splash"><img src="assets/logo-lihen.jpg" alt="LIHEN"><span></span><p>Preparando LIHEN Admin…</p></div>';

  try {
    await loadSession();

    if (isAuthCallback() && state.session) {
      renderPasswordSetup();
      return;
    }

    if (state.session) await renderApp();
    else renderLogin();
  } catch (error) {
    console.error(error);
    renderLogin('No fue posible conectar con Supabase. Revisa la conexión.');
  }
}

function renderLogin(error = '') {
  app.innerHTML = login(error);

  $('#loginForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const formData = new FormData(form);
    const button = $('button[type="submit"]', form);

    try {
      await withPendingButton(button, 'Ingresando…', async () => {
        await signIn(formData.get('email'), formData.get('password'));
        await renderApp();
      });
    } catch (loginError) {
      const message = loginError.message === 'Invalid login credentials'
        ? 'Correo o contraseña incorrectos.'
        : errorMessage(loginError);
      renderLogin(message);
    }
  });
}

function renderPasswordSetup(error = '') {
  app.innerHTML = passwordSetup(error);

  $('#passwordSetupForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const formData = new FormData(form);
    const password = formData.get('password');
    const confirmation = formData.get('confirm_password');
    const button = $('button[type="submit"]', form);

    if (password !== confirmation) {
      renderPasswordSetup('Las contraseñas no coinciden.');
      return;
    }

    try {
      await withPendingButton(button, 'Guardando…', async () => {
        await updatePassword(password);
        history.replaceState({}, document.title, location.pathname);
        await loadSession();
        toast('Contraseña creada correctamente');
        await renderApp();
      });
    } catch (setupError) {
      renderPasswordSetup(errorMessage(setupError));
    }
  });
}

function showPasswordReset() {
  modal('Recuperar contraseña', `
    <form id="resetPasswordForm" class="form-grid">
      <label class="full">Correo de la cofundadora
        <input name="email" type="email" autocomplete="email" required>
      </label>
      <p class="full privacy">Recibirás un enlace seguro para crear una contraseña nueva.</p>
      <div class="form-actions full">
        <button type="button" class="button ghost" data-close-modal>Cancelar</button>
        <button class="button primary" type="submit">Enviar enlace</button>
      </div>
    </form>
  `);

  const form = $('#resetPasswordForm');
  if (!form) {
    toast('No fue posible abrir la recuperación de contraseña.', 'danger');
    return;
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = $('button[type="submit"]', event.currentTarget);
    const email = new FormData(event.currentTarget).get('email');

    try {
      await withPendingButton(button, 'Enviando…', async () => {
        await sendPasswordReset(email);
        closeModal();
        toast('Revisa tu correo para continuar');
      });
    } catch (resetError) {
      toast(errorMessage(resetError, 'No fue posible enviar el enlace.'), 'danger');
    }
  });
}

async function renderApp() {
  app.innerHTML = shell('<div id="viewRoot" aria-live="polite"></div>');
  await refresh();
  requestAnimationFrame(() => $('#mainContent')?.focus({ preventScroll: true }));
}

async function refresh() {
  const root = $('#viewRoot');
  if (!root) return;

  root.setAttribute('aria-busy', 'true');
  root.innerHTML = await renderRoute();
  root.removeAttribute('aria-busy');
  bindViewFilters();
}

function setMobileMenu(open) {
  const sidebar = $('#sidebar');
  if (!sidebar) return;

  const isOpen = Boolean(open);
  sidebar.classList.toggle('open', isOpen);
  $('#sidebarOverlay')?.classList.toggle('open', isOpen);
  $('#menuBtn')?.setAttribute('aria-expanded', String(isOpen));
  document.body.classList.toggle('menu-open', isOpen);
}

function toggleMobileMenu() {
  setMobileMenu(!$('#sidebar')?.classList.contains('open'));
}

async function navigate(route) {
  state.route = route;
  setMobileMenu(false);
  app.innerHTML = shell('<div id="viewRoot" aria-live="polite"></div>');
  await refresh();
}

async function executeAction(name, dataset = {}) {
  return executeCommand(name, dataset);
}

function findOrder(orderId) {
  return state.orders.find((order) => order.id === orderId)
    || state.dashboard?.recentOrders?.find((order) => order.id === orderId);
}

async function handleApplicationClick(event) {
  const menuButton = event.target.closest('#menuBtn');
  if (menuButton) {
    event.preventDefault();
    toggleMobileMenu();
    return;
  }

  if (event.target.closest('#sidebarOverlay')) {
    setMobileMenu(false);
    return;
  }

  if (event.target.closest('#forgotPasswordBtn')) {
    event.preventDefault();
    showPasswordReset();
    return;
  }

  if (event.target.closest('#logoutBtn')) {
    setMobileMenu(false);
    await signOut();
    renderLogin();
    return;
  }

  const routeTarget = event.target.closest('[data-route]');
  if (routeTarget) {
    await navigate(routeTarget.dataset.route);
    return;
  }

  const actionTarget = event.target.closest('[data-action]');
  if (actionTarget) {
    await executeAction(actionTarget.dataset.action, actionTarget.dataset);
    return;
  }

  const saleTarget = event.target.closest('[data-quick-sale-id]');
  if (saleTarget) {
    const sale = state.quickSales.find((item) => item.id === saleTarget.dataset.quickSaleId);
    if (sale) quickSaleReceipt(sale);
    return;
  }

  const orderTarget = event.target.closest('[data-order-id]');
  if (orderTarget) {
    const order = findOrder(orderTarget.dataset.orderId);
    if (order) showOrder(order);
    return;
  }

  const customerTarget = event.target.closest('[data-edit-customer]');
  if (customerTarget) {
    editCustomer(customerTarget.dataset.editCustomer);
    return;
  }

  const supplierTarget = event.target.closest('[data-edit-supplier]');
  if (supplierTarget) {
    editSupplier(supplierTarget.dataset.editSupplier);
    return;
  }

  const newPurchaseTarget = event.target.closest('[data-new-supplier-purchase]');
  if (newPurchaseTarget) {
    await newSupplierPurchase(newPurchaseTarget.dataset.newSupplierPurchase);
    return;
  }

  const historicalPurchaseTarget = event.target.closest('[data-new-historical-purchase]');
  if (historicalPurchaseTarget) {
    await newHistoricalSupplierPurchase(historicalPurchaseTarget.dataset.newHistoricalPurchase);
    return;
  }

  const purchaseHistoryTarget = event.target.closest('[data-view-supplier-purchases]');
  if (purchaseHistoryTarget) {
    await viewSupplierPurchases(purchaseHistoryTarget.dataset.viewSupplierPurchases);
    return;
  }

  const reverseMovementTarget = event.target.closest('[data-reverse-financial-movement]');
  if (reverseMovementTarget) {
    await reverseMovement(reverseMovementTarget.dataset.reverseFinancialMovement);
    return;
  }

  const initialBalanceTarget = event.target.closest('[data-configure-account]');
  if (initialBalanceTarget) {
    await configureAccountBalance(initialBalanceTarget.dataset.configureAccount);
    return;
  }

  const productTarget = event.target.closest('[data-edit-product]');
  if (productTarget) editProduct(productTarget.dataset.editProduct);
}

function bindTableSearch(selector) {
  $(selector)?.addEventListener('input', (event) => {
    const query = event.target.value.trim().toLowerCase();
    $$('tbody tr').forEach((row) => {
      row.hidden = Boolean(query && !row.innerText.toLowerCase().includes(query));
    });
  });
}

function bindViewFilters() {
  $('#orderStatus')?.addEventListener('change', (event) => {
    const selectedLabel = event.target.selectedOptions[0].text.toLowerCase();
    $$('tbody tr').forEach((row) => {
      row.hidden = Boolean(event.target.value && !row.innerText.toLowerCase().includes(selectedLabel));
    });
  });

  bindTableSearch('#orderSearch');
  bindTableSearch('#quickSaleSearch');
  bindTableSearch('#productSearch');
  bindTableSearch('#customerSearch');

  $('#supplierSearch')?.addEventListener('input', (event) => {
    const query = event.target.value.trim().toLowerCase();
    $$('.supplier-card').forEach((card) => {
      card.hidden = Boolean(query && !card.innerText.toLowerCase().includes(query));
    });
  });

  $('#productVisibility')?.addEventListener('change', (event) => {
    $$('tbody tr').forEach((row) => {
      const text = row.innerText.toLowerCase();
      row.hidden = (event.target.value === 'visible' && !text.includes('publicado'))
        || (event.target.value === 'hidden' && !text.includes('oculto'));
    });
  });
}

document.addEventListener('click', (event) => {
  handleApplicationClick(event).catch((error) => {
    console.error(error);
    toast(errorMessage(error), 'danger');
  });
});
document.addEventListener('lihen:refresh', refresh);
subscribe('inventory:updated', refresh);
subscribe('orders:updated', refresh);
subscribe('sales:updated', refresh);
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    setMobileMenu(false);
    closeModal();
  }
});

boot();
