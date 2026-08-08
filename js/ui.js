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
import { NAVIGATION_ITEMS } from './constants.js';
export { login, passwordSetup } from './ui-auth.js';

let lastFocusedElement = null;

export function toast(message, type = 'success') {
  let root = $('#toastRoot');

  if (!root) {
    root = document.createElement('div');
    root.id = 'toastRoot';
    document.body.appendChild(root);
  }

  const element = document.createElement('div');
  element.className = `toast ${type}`;
  element.setAttribute('role', type === 'danger' ? 'alert' : 'status');
  element.setAttribute('aria-live', type === 'danger' ? 'assertive' : 'polite');
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
    <div class="loading" role="status" aria-live="polite" aria-busy="true">
      <span class="spinner" aria-hidden="true"></span>
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
    <div class="empty" role="status">
      <span>${icon}</span>
      <h3>${escapeHtml(title)}</h3>
      <p>${escapeHtml(text)}</p>
      ${action}
    </div>
  `;
}



export function shell(content) {
  const profile = state.profile || {};
  const route = NAVIGATION_ITEMS.find((item) => item.id === state.route) || NAVIGATION_ITEMS[0];

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

        <nav aria-label="Navegación principal">
          ${NAVIGATION_ITEMS.map(({ id, icon, label }) => `
            <button
              type="button"
              data-route="${id}"
              class="nav-item ${state.route === id ? 'active' : ''}"
              ${state.route === id ? 'aria-current="page"' : ''}
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

      <button
        type="button"
        class="sidebar-overlay"
        id="sidebarOverlay"
        aria-label="Cerrar menú"
        tabindex="-1"
      ></button>

      <div class="workspace">
        <header class="topbar">
          <button
            class="icon-button mobile-menu"
            id="menuBtn"
            type="button"
            aria-label="Abrir menú"
            aria-controls="sidebar"
            aria-expanded="false"
          >
            ☰
          </button>

          <div>
            <small>LIHEN.CO · CENTRO OPERATIVO</small>
            <h1>${escapeHtml(route.label)}</h1>
          </div>

          <div class="top-actions">
            <span class="live-dot">
              <i></i>
              Conectado
            </span>

            <button class="button primary" type="button" data-action="${state.route==='quick-sales'?'new-quick-sale':'new-order'}">${state.route==='quick-sales'?'+ Nueva venta':'+ Nuevo pedido'}</button>
          </div>
        </header>

        <main class="content" id="mainContent" tabindex="-1">
          ${content}
        </main>
      </div>
    </div>

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

  lastFocusedElement = document.activeElement;
  document.body.classList.add('modal-open');
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

  document.addEventListener('keydown', handleModalKeydown);

  requestAnimationFrame(() => {
    const dialog = $('.modal', modalRoot);
    const firstFocusable = dialog?.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    firstFocusable?.focus();
  });
}

function handleModalKeydown(event) {
  if (event.key === 'Escape') {
    closeModal();
    return;
  }

  if (event.key !== 'Tab') return;
  const dialog = $('.modal');
  if (!dialog) return;
  const focusable = [...dialog.querySelectorAll('button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')];
  if (!focusable.length) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

export function closeModal() {
  const root = $('#modalRoot');

  if (root) {
    root.innerHTML = '';
  }

  document.removeEventListener('keydown', handleModalKeydown);
  document.body.classList.remove('modal-open');
  if (lastFocusedElement instanceof HTMLElement) lastFocusedElement.focus();
  lastFocusedElement = null;
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