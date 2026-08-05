import {
  state,
  loadSession,
  signIn,
  signOut,
  updatePassword,
  sendPasswordReset,
  isAuthCallback,
  markPasswordRecovery,
  clearPasswordRecovery,
  isPasswordRecoveryPending
} from './store.js';
import { supabase } from './supabase.js';
import { $, $$ } from './utils.js';
import {
  shell,
  login,
  passwordSetup,
  toast,
  closeModal,
  modal
} from './ui.js';
import { renderRoute, showOrder } from './views.js';
import {
  newCustomer,
  newSupplier,
  newProduct,
  newOrder,
  importCatalog,
  inventoryAdjustment
} from './forms.js';

const app = $('#app');
let bootFinished = false;
let renderingPasswordSetup = false;

/*
 * Supabase emite PASSWORD_RECOVERY cuando la usuaria llega desde el enlace
 * enviado por correo. Este listener debe registrarse antes de iniciar la app,
 * porque detectSessionInUrl puede limpiar el token de la dirección rápidamente.
 */
supabase.auth.onAuthStateChange((event, session) => {
  state.session = session;

  if (event === 'PASSWORD_RECOVERY') {
    markPasswordRecovery();

    window.setTimeout(() => {
      renderPasswordSetup();
    }, 0);
    return;
  }

  if (event === 'SIGNED_OUT') {
    clearPasswordRecovery();

    if (bootFinished) {
      renderLogin();
    }
  }
});

async function boot() {
  app.innerHTML = `
    <div class="splash">
      <img src="assets/logo-lihen.jpg" alt="LIHEN">
      <span></span>
      <p>Preparando LIHEN Admin…</p>
    </div>
  `;

  try {
    await loadSession();

    /*
     * Damos un instante al cliente de Supabase para emitir PASSWORD_RECOVERY.
     * El marcador de sessionStorage evita que la vista se pierda al recargar.
     */
    await new Promise((resolve) => window.setTimeout(resolve, 120));

    if (
      state.session &&
      (isPasswordRecoveryPending() || isAuthCallback())
    ) {
      renderPasswordSetup();
      bootFinished = true;
      return;
    }

    if (state.session) {
      await renderApp();
    } else {
      renderLogin();
    }
  } catch (error) {
    console.error(error);
    renderLogin(
      'No fue posible conectar con Supabase. Revisa la conexión.'
    );
  } finally {
    bootFinished = true;
  }
}

function renderLogin(error = '') {
  renderingPasswordSetup = false;
  app.innerHTML = login(error);

  $('#loginForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();

    const formData = new FormData(event.currentTarget);
    const button = $('button[type="submit"]', event.currentTarget);

    button.disabled = true;
    button.textContent = 'Ingresando…';

    try {
      clearPasswordRecovery();
      await signIn(
        formData.get('email'),
        formData.get('password')
      );
      await renderApp();
    } catch (error) {
      renderLogin(
        error.message === 'Invalid login credentials'
          ? 'Correo o contraseña incorrectos.'
          : error.message
      );
    }
  });
}

function renderPasswordSetup(error = '') {
  if (!state.session) {
    renderLogin(
      'El enlace de recuperación venció o no contiene una sesión válida. Solicita uno nuevo.'
    );
    return;
  }

  renderingPasswordSetup = true;
  markPasswordRecovery();
  app.innerHTML = passwordSetup(error);

  $('#passwordSetupForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();

    const formData = new FormData(event.currentTarget);
    const password = formData.get('password');
    const confirmation = formData.get('confirm_password');
    const button = $('button[type="submit"]', event.currentTarget);

    if (password !== confirmation) {
      renderPasswordSetup('Las contraseñas no coinciden.');
      return;
    }

    button.disabled = true;
    button.textContent = 'Guardando…';

    try {
      await updatePassword(password);
      clearPasswordRecovery();
      cleanAuthUrl();
      await loadSession();
      toast('Contraseña actualizada correctamente');
      renderingPasswordSetup = false;
      await renderApp();
    } catch (error) {
      renderPasswordSetup(error.message);
    }
  });
}

function cleanAuthUrl() {
  const cleanUrl = `${window.location.origin}${window.location.pathname}`;
  window.history.replaceState({}, document.title, cleanUrl);
}

function showPasswordReset() {
  modal(
    'Recuperar contraseña',
    `
      <form id="resetPasswordForm" class="form-grid">
        <label class="full">
          Correo de la cofundadora
          <input
            name="email"
            type="email"
            autocomplete="email"
            required
          >
        </label>

        <p class="full privacy">
          Recibirás un enlace seguro para crear una contraseña nueva.
        </p>

        <div class="form-actions full">
          <button
            type="button"
            class="button ghost"
            data-close-modal
          >
            Cancelar
          </button>

          <button class="button primary" type="submit">
            Enviar enlace
          </button>
        </div>
      </form>
    `
  );

  const form = $('#resetPasswordForm');

  if (!form) {
    toast(
      'No fue posible abrir la recuperación de contraseña.',
      'danger'
    );
    return;
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();

    const button = $('button[type="submit"]', event.currentTarget);
    const email = new FormData(event.currentTarget).get('email');

    button.disabled = true;
    button.textContent = 'Enviando…';

    try {
      clearPasswordRecovery();
      await sendPasswordReset(email);
      closeModal();
      toast('Revisa tu correo para continuar');
    } catch (error) {
      button.disabled = false;
      button.textContent = 'Enviar enlace';
      toast(
        error.message || 'No fue posible enviar el enlace.',
        'danger'
      );
    }
  });
}

async function renderApp() {
  if (isPasswordRecoveryPending() || renderingPasswordSetup) {
    renderPasswordSetup();
    return;
  }

  app.innerHTML = shell('<div id="viewRoot"></div>');
  await refresh();
  bindGlobal();
}

async function refresh() {
  const root = $('#viewRoot');
  if (!root) return;

  root.innerHTML = await renderRoute();
  bindContent();
}

function bindGlobal() {
  $$('[data-route]').forEach((button) => {
    button.addEventListener('click', () => {
      navigate(button.dataset.route);
    });
  });

  $('#logoutBtn')?.addEventListener('click', async () => {
    clearPasswordRecovery();
    await signOut();
    renderLogin();
  });

  $('#menuBtn')?.addEventListener('click', () => {
    $('#sidebar')?.classList.toggle('open');
  });

  bindContent();
}

function bindContent() {
  $$('[data-route]').forEach((button) => {
    if (!button.dataset.bound) {
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        navigate(button.dataset.route);
      });
    }
  });

  $$('[data-action]').forEach((button) => {
    if (!button.dataset.bound) {
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        action(button.dataset.action, button.dataset);
      });
    }
  });

  $$('[data-order-id]').forEach((button) => {
    button.addEventListener('click', () => {
      const order =
        state.orders.find((item) => item.id === button.dataset.orderId) ||
        state.dashboard?.recentOrders.find(
          (item) => item.id === button.dataset.orderId
        );

      if (order) showOrder(order);
    });
  });

  $('#orderStatus')?.addEventListener('change', (event) => {
    $$('tbody tr').forEach((row) => {
      row.hidden =
        event.target.value &&
        !row.innerText
          .toLowerCase()
          .includes(
            event.target.selectedOptions[0].text.toLowerCase()
          );
    });
  });

  const bindTableSearch = (selector) => {
    $(selector)?.addEventListener('input', (event) => {
      const query = event.target.value.trim().toLowerCase();

      $$('tbody tr').forEach((row) => {
        row.hidden =
          query &&
          !row.innerText.toLowerCase().includes(query);
      });
    });
  };

  bindTableSearch('#orderSearch');
  bindTableSearch('#productSearch');
  bindTableSearch('#customerSearch');

  $('#supplierSearch')?.addEventListener('input', (event) => {
    const query = event.target.value.trim().toLowerCase();

    $$('.supplier-card').forEach((card) => {
      card.hidden =
        query &&
        !card.innerText.toLowerCase().includes(query);
    });
  });

  $('#productVisibility')?.addEventListener('change', (event) => {
    $$('tbody tr').forEach((row) => {
      const text = row.innerText.toLowerCase();

      row.hidden =
        (event.target.value === 'visible' &&
          !text.includes('publicado')) ||
        (event.target.value === 'hidden' &&
          !text.includes('oculto'));
    });
  });
}

async function navigate(route) {
  state.route = route;
  $('#sidebar')?.classList.remove('open');
  app.innerHTML = shell('<div id="viewRoot"></div>');
  await refresh();
  bindGlobal();
}

function action(name, dataset = {}) {
  const actions = {
    'new-order': newOrder,
    'new-product': newProduct,
    'new-supplier': newSupplier,
    'new-customer': newCustomer,
    'import-catalog': importCatalog,
    'inventory-adjustment': inventoryAdjustment,
    'generate-receipt': () => {
      toast(
        'Abre un pedido para generar su comprobante.',
        'warning'
      );
    }
  };

  const selectedAction = actions[name] || (() => {});
  selectedAction(dataset);
}

document.addEventListener('click', (event) => {
  const forgotButton = event.target.closest('#forgotPasswordBtn');

  if (forgotButton) {
    event.preventDefault();
    showPasswordReset();
  }
});

document.addEventListener('lihen:refresh', refresh);

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    closeModal();
  }
});

boot();
