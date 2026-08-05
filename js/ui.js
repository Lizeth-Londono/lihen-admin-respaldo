import {
  $,
  $$,
  escapeHtml,
  initials,
  money,
  statusLabel,
  statusTone,
  dateTime
} from './utils.js';

import { state } from './store.js';

export function toast(message, type = 'success') {
  let root = $('#toastRoot');

  if (!root) {
    root = document.createElement('div');
    root.id = 'toastRoot';
    document.body.appendChild(root);
  }

  const element = document.createElement('div');
  element.className = `toast ${type}`;
  element.textContent = message;

  root.append(element);

  requestAnimationFrame(() => {
    element.classList.add('show');
  });

  setTimeout(() => {
    element.classList.remove('show');

    setTimeout(() => {
      element.remove();
    }, 250);
  }, 3200);
}

export function spinner(label = 'Cargando información…') {
  return `
    <div class="loading">
      <span class="spinner"></span>
      <p>${escapeHtml(label)}</p>
    </div>
  `;
}

export function badge(value) {
  return `
    <span class="status ${statusTone(value)}">
      ${escapeHtml(statusLabel(value))}
    </span>
  `;
}

export function metric(icon, label, value, detail, tone = 'gold') {
  return `
    <article class="metric ${tone}">
      <div class="metric-icon">${icon}</div>

      <div>
        <span>${escapeHtml(label)}</span>
        <strong>${value}</strong>
        <small>${escapeHtml(detail)}</small>
      </div>
    </article>
  `;
}

export function empty(icon, title, text, action = '') {
  return `
    <div class="empty">
      <span>${icon}</span>
      <h3>${escapeHtml(title)}</h3>
      <p>${escapeHtml(text)}</p>
      ${action}
    </div>
  `;
}

const NAV = [
  ['dashboard', '⌂', 'Inicio'],
  ['orders', '▤', 'Pedidos'],
  ['inventory', '▦', 'Inventario y catálogo'],
  ['suppliers', '◇', 'Proveedores'],
  ['customers', '♡', 'Clientes'],
  ['receipts', '▧', 'Comprobantes'],
  ['movements', '↺', 'Movimientos'],
  ['reports', '↗', 'Reportes'],
  ['settings', '⚙', 'Configuración']
];

export function shell(content) {
  const profile = state.profile || {};
  const route = NAV.find((item) => item[0] === state.route) || NAV[0];

  return `
    <div class="app-shell">
      <aside class="sidebar" id="sidebar">
        <div class="brand">
          <img src="assets/logo-lihen.jpg" alt="Logo LIHEN">

          <div>
            <b>LIHEN</b>
            <span>Administración</span>
          </div>
        </div>

        <nav>
          ${NAV.map(([id, icon, label]) => `
            <button
              type="button"
              data-route="${id}"
              class="nav-item ${state.route === id ? 'active' : ''}"
            >
              <span>${icon}</span>
              ${label}
            </button>
          `).join('')}
        </nav>

        <div class="sidebar-footer">
          <div class="avatar">
            ${initials(profile.full_name)}
          </div>

          <div>
            <b>${escapeHtml(profile.full_name || 'Cofundadora')}</b>
            <span>Cofundadora</span>
          </div>

          <button
            class="icon-button"
            id="logoutBtn"
            type="button"
            title="Cerrar sesión"
            aria-label="Cerrar sesión"
          >
            ↪
          </button>
        </div>
      </aside>

      <div class="workspace">
        <header class="topbar">
          <button
            class="icon-button mobile-menu"
            id="menuBtn"
            type="button"
            aria-label="Abrir menú"
          >
            ☰
          </button>

          <div>
            <small>LIHEN.CO · CENTRO OPERATIVO</small>
            <h1>${escapeHtml(route[2])}</h1>
          </div>

          <div class="top-actions">
            <span class="live-dot">
              <i></i>
              Conectado
            </span>

            <button
              class="button primary"
              type="button"
              data-action="new-order"
            >
              + Nuevo pedido
            </button>
          </div>
        </header>

        <main class="content">
          ${content}
        </main>
      </div>
    </div>

    <div id="modalRoot"></div>
    <div id="toastRoot"></div>
  `;
}

export function login(error = '') {
  return `
    <main class="login-page">
      <section class="login-visual">
        <div class="orb one"></div>
        <div class="orb two"></div>

        <div class="login-quote">
          <span>Beauty Care · Style</span>

          <h2>
            Todo lo que LIHEN necesita para operar,
            en un solo lugar.
          </h2>

          <p>
            Inventario, pedidos, proveedores, clientes y comprobantes
            con control seguro.
          </p>
        </div>
      </section>

      <section class="login-panel">
        <form id="loginForm" class="login-card">
          <img src="assets/logo-lihen.jpg" alt="LIHEN">

          <p class="eyebrow">PLATAFORMA PRIVADA</p>

          <h1>Bienvenidas a LIHEN</h1>

          <p>
            Ingresa con tu cuenta individual de cofundadora.
          </p>

          ${
            error
              ? `<div class="alert danger">${escapeHtml(error)}</div>`
              : ''
          }

          <label>
            Correo electrónico

            <input
              name="email"
              type="email"
              autocomplete="email"
              required
              placeholder="nombre@lihen.co"
            >
          </label>

          <label>
            Contraseña

            <input
              name="password"
              type="password"
              autocomplete="current-password"
              required
              minlength="8"
              placeholder="••••••••"
            >
          </label>

          <button
            class="button primary wide"
            type="submit"
          >
            Ingresar de forma segura
          </button>

          <button
            class="text-button login-help"
            id="forgotPasswordBtn"
            type="button"
          >
            ¿Olvidaste tu contraseña?
          </button>

          <small class="privacy">
            Los datos administrativos solo están disponibles
            para cuentas autorizadas.
          </small>
        </form>
      </section>
    </main>

    <div id="modalRoot"></div>
    <div id="toastRoot"></div>
  `;
}

export function passwordSetup(error = '') {
  return `
    <main class="login-page">
      <section class="login-visual">
        <div class="orb one"></div>
        <div class="orb two"></div>

        <div class="login-quote">
          <span>ACCESO SEGURO</span>

          <h2>
            Activa tu cuenta de cofundadora.
          </h2>

          <p>
            Crea una contraseña personal para entrar
            al centro operativo privado de LIHEN.
          </p>
        </div>
      </section>

      <section class="login-panel">
        <form id="passwordSetupForm" class="login-card">
          <img src="assets/logo-lihen.jpg" alt="LIHEN">

          <p class="eyebrow">CONFIGURACIÓN DE ACCESO</p>

          <h1>Crear contraseña</h1>

          <p>
            La contraseña debe tener mínimo 8 caracteres.
          </p>

          ${
            error
              ? `<div class="alert danger">${escapeHtml(error)}</div>`
              : ''
          }

          <label>
            Nueva contraseña

            <input
              name="password"
              type="password"
              autocomplete="new-password"
              required
              minlength="8"
              placeholder="••••••••"
            >
          </label>

          <label>
            Confirmar contraseña

            <input
              name="confirm_password"
              type="password"
              autocomplete="new-password"
              required
              minlength="8"
              placeholder="••••••••"
            >
          </label>

          <button
            class="button primary wide"
            type="submit"
          >
            Guardar y entrar
          </button>

          <small class="privacy">
            Cada cofundadora debe usar una contraseña individual.
          </small>
        </form>
      </section>
    </main>

    <div id="modalRoot"></div>
    <div id="toastRoot"></div>
  `;
}

export function modal(
  title,
  body,
  {
    wide = false,
    footer = ''
  } = {}
) {
  let modalRoot = $('#modalRoot');

  if (!modalRoot) {
    modalRoot = document.createElement('div');
    modalRoot.id = 'modalRoot';
    document.body.appendChild(modalRoot);
  }

  modalRoot.innerHTML = `
    <div class="modal-backdrop">
      <section
        class="modal ${wide ? 'wide' : ''}"
        role="dialog"
        aria-modal="true"
        aria-labelledby="modalTitle"
      >
        <header>
          <div>
            <p class="eyebrow">LIHEN ADMIN</p>
            <h2 id="modalTitle">${escapeHtml(title)}</h2>
          </div>

          <button
            class="icon-button"
            type="button"
            data-close-modal
            aria-label="Cerrar ventana"
          >
            ×
          </button>
        </header>

        <div class="modal-body">
          ${body}
        </div>

        ${
          footer
            ? `<footer>${footer}</footer>`
            : ''
        }
      </section>
    </div>
  `;

  $$('[data-close-modal]').forEach((button) => {
    button.addEventListener('click', closeModal);
  });

  const backdrop = $('.modal-backdrop');

  backdrop?.addEventListener('click', (event) => {
    if (event.target === backdrop) {
      closeModal();
    }
  });

  document.addEventListener('keydown', handleModalEscape);
}

function handleModalEscape(event) {
  if (event.key === 'Escape') {
    closeModal();
  }
}

export function closeModal() {
  const root = $('#modalRoot');

  if (root) {
    root.innerHTML = '';
  }

  document.removeEventListener('keydown', handleModalEscape);
}

export function formatMovement(movement) {
  const name =
    movement.inventory?.product?.name ||
    movement.product_inventory?.product?.name ||
    'Producto';

  return `
    <div class="activity">
      <span class="activity-mark"></span>

      <div>
        <b>
          ${escapeHtml(statusLabel(movement.movement_type))}:
          ${escapeHtml(name)}
        </b>

        <p>
          ${
            escapeHtml(
              movement.reason ||
              `${movement.quantity} unidad(es)`
            )
          }
        </p>

        <small>
          ${dateTime(movement.created_at)}
          ·
          ${escapeHtml(movement.user?.full_name || 'Sistema')}
        </small>
      </div>
    </div>
  `;
}

export function totals(order) {
  return `
    <div class="totals">
      <div>
        <span>Subtotal</span>
        <b>${money(order.subtotal)}</b>
      </div>

      <div>
        <span>Descuento</span>
        <b>− ${money(order.discount_amount)}</b>
      </div>

      <div>
        <span>Domicilio</span>
        <b>${money(order.delivery_cost)}</b>
      </div>

      <div class="grand">
        <span>Total</span>
        <strong>${money(order.total)}</strong>
      </div>
    </div>
  `;
}