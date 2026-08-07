import { escapeHtml, money } from '../utils.js';

const TONES = new Set(['primary', 'warning', 'danger']);

export function normalizeConfirmationConfig(config = {}) {
  const title = String(config.title || 'Confirmar acción').trim();
  const message = String(config.message || 'Revisa la información antes de continuar.').trim();
  const confirmLabel = String(config.confirmLabel || 'Confirmar').trim();
  const cancelLabel = String(config.cancelLabel || 'Volver').trim();
  const tone = TONES.has(config.tone) ? config.tone : 'primary';
  const details = Array.isArray(config.details)
    ? config.details
        .filter((item) => item && String(item.label || '').trim())
        .map((item) => ({
          label: String(item.label).trim(),
          value: String(item.value ?? '—').trim() || '—'
        }))
    : [];

  return { title, message, confirmLabel, cancelLabel, tone, details };
}

export function buildConfirmationMarkup(config = {}) {
  const normalized = normalizeConfirmationConfig(config);
  const detailMarkup = normalized.details.length
    ? `<dl class="confirmation-summary">${normalized.details.map((item) => `
        <div>
          <dt>${escapeHtml(item.label)}</dt>
          <dd>${escapeHtml(item.value)}</dd>
        </div>`).join('')}</dl>`
    : '';

  return `
    <div class="confirmation-backdrop" data-confirmation-backdrop>
      <section class="confirmation-dialog ${normalized.tone}" role="alertdialog" aria-modal="true" aria-labelledby="confirmationTitle" aria-describedby="confirmationMessage">
        <header>
          <p class="eyebrow">CONFIRMACIÓN REQUERIDA</p>
          <h2 id="confirmationTitle">${escapeHtml(normalized.title)}</h2>
        </header>
        <div class="confirmation-body">
          <p id="confirmationMessage">${escapeHtml(normalized.message)}</p>
          ${detailMarkup}
        </div>
        <footer>
          <button type="button" class="button ghost" data-confirmation-cancel>${escapeHtml(normalized.cancelLabel)}</button>
          <button type="button" class="button ${normalized.tone === 'danger' ? 'danger' : 'primary'}" data-confirmation-accept>${escapeHtml(normalized.confirmLabel)}</button>
        </footer>
      </section>
    </div>`;
}

export function moneyDetail(label, value) {
  return { label, value: money(Number(value || 0)) };
}

export function confirmAction(config = {}) {
  const existing = document.getElementById('confirmationRoot');
  if (existing) existing.remove();

  const root = document.createElement('div');
  root.id = 'confirmationRoot';
  root.innerHTML = buildConfirmationMarkup(config);
  document.body.appendChild(root);

  const accept = root.querySelector('[data-confirmation-accept]');
  const cancel = root.querySelector('[data-confirmation-cancel]');
  const backdrop = root.querySelector('[data-confirmation-backdrop]');
  const previousFocus = document.activeElement;

  return new Promise((resolve) => {
    let settled = false;

    const finish = (result) => {
      if (settled) return;
      settled = true;
      document.removeEventListener('keydown', onKeydown);
      root.remove();
      if (previousFocus instanceof HTMLElement) previousFocus.focus();
      resolve(result);
    };

    const onKeydown = (event) => {
      if (event.key === 'Escape') finish(false);
      if (event.key === 'Enter' && document.activeElement === accept) finish(true);
    };

    accept?.addEventListener('click', () => finish(true));
    cancel?.addEventListener('click', () => finish(false));
    backdrop?.addEventListener('click', (event) => {
      if (event.target === backdrop) finish(false);
    });
    document.addEventListener('keydown', onKeydown);

    requestAnimationFrame(() => cancel?.focus());
  });
}
