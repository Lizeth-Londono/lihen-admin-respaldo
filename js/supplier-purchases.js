import { state, loadProducts, loadSupplierPurchases, loadFinancialAccounts } from './store.js';
import { $, escapeHtml, money, dateTime, statusLabel } from './utils.js';
import { modal, closeModal, toast, badge } from './ui.js';
import { confirmAction, moneyDetail } from './services/confirmation-service.js';
import { createOperationKey } from './services/operation-key-service.js';
import { normalizePurchaseItems, calculatePurchaseTotals, summarizePurchase } from './services/supplier-purchase-service.js';
import { createSupplierPurchase, createHistoricalSupplierPurchase, confirmSupplierPurchase, receiveSupplierPurchase, registerSupplierPayment } from './repositories/supplier-purchase-repository.js';

function dateInputValue(date = new Date()) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

function dateTimeInputValue(date = new Date()) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

function purchaseItemRow(productId = '') {
  const options = state.products.map((product) => `<option value="${product.id}" ${product.id === productId ? 'selected' : ''}>${escapeHtml(product.sku || product.catalog_code || 'Sin código')} · ${escapeHtml(product.name)}</option>`).join('');
  return `<div class="purchase-item-row" data-purchase-item>
    <label class="purchase-product">Producto<select name="product_id" required><option value="">Selecciona</option>${options}</select></label>
    <label>Cantidad<input name="quantity_requested" type="number" min="1" step="1" value="1" required></label>
    <label>Costo unitario<input name="quoted_unit_cost" type="number" min="0" step="1" value="0" required></label>
    <div class="purchase-item-total"><span>Subtotal</span><b data-line-total>${money(0)}</b></div>
    <button class="icon-button" type="button" data-remove-purchase-item aria-label="Quitar producto">×</button>
  </div>`;
}

function collectItems(form) {
  return [...form.querySelectorAll('[data-purchase-item]')].map((row) => ({
    product_id: $('select[name="product_id"]', row)?.value,
    quantity_requested: $('input[name="quantity_requested"]', row)?.value,
    quoted_unit_cost: $('input[name="quoted_unit_cost"]', row)?.value
  }));
}

function updateTotals(form) {
  const items = [...form.querySelectorAll('[data-purchase-item]')].map((row) => {
    const quantity = Number($('input[name="quantity_requested"]', row)?.value || 0);
    const cost = Number($('input[name="quoted_unit_cost"]', row)?.value || 0);
    $('[data-line-total]', row).textContent = money(quantity * cost);
    return { quantity_requested: quantity, quoted_unit_cost: cost };
  });
  const totals = calculatePurchaseTotals(items, {
    discountAmount: form.elements.discount_amount?.value,
    taxAmount: form.elements.tax_amount?.value,
    freightAmount: form.elements.freight_amount?.value
  });
  $('[data-purchase-subtotal]', form).textContent = money(totals.subtotal);
  $('[data-purchase-total]', form).textContent = money(totals.total);
  return totals;
}

export async function newSupplierPurchase(supplierId, { historical = false } = {}) {
  const supplier = state.suppliers.find((item) => item.id === supplierId);
  if (!supplier) return toast('Proveedor no encontrado.', 'danger');
  await loadProducts();
  modal(`${historical ? 'Compra histórica' : 'Nueva compra'} · ${supplier.business_name}`, `<form id="supplierPurchaseForm" class="form-grid purchase-form">
    <label>Fecha de compra<input name="purchase_date" type="date" value="${dateInputValue()}" required></label>
    <label>Fecha esperada<input name="expected_date" type="date"></label>
    <label>Número de factura<input name="invoice_number" maxlength="100"></label>
    <label>Fecha límite de pago<input name="due_date" type="date"></label>
    <section class="full purchase-items-section"><header><div><p class="eyebrow">PRODUCTOS</p><h3>Detalle de la compra</h3></div><button class="button secondary" type="button" data-add-purchase-item>+ Agregar producto</button></header><div data-purchase-items>${purchaseItemRow()}</div></section>
    <label>Descuento<input name="discount_amount" type="number" min="0" step="1" value="0"></label>
    <label>Impuestos<input name="tax_amount" type="number" min="0" step="1" value="0"></label>
    <label>Flete / domicilio<input name="freight_amount" type="number" min="0" step="1" value="0"></label>
    ${historical ? `<label>Valor pagado históricamente<input name="historical_paid_amount" type="number" min="0" step="1" value="0"></label><label>Medio de pago histórico<select name="historical_payment_method"><option value="">Sin registrar</option><option value="nequi">Nequi</option><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option><option value="otro">Otro</option></select></label><label>Fecha del pago histórico<input name="historical_payment_date" type="date"></label><label>Referencia / origen<input name="source_reference" placeholder="Excel, imagen, factura..."></label><div class="callout full"><b>Registro histórico sin impacto</b><p>No aumentará el inventario actual ni descontará dinero de Nequi o efectivo.</p></div>` : ``}
    <div class="purchase-totals"><span>Subtotal <b data-purchase-subtotal>${money(0)}</b></span><span>Total <strong data-purchase-total>${money(0)}</strong></span></div>
    <label class="full">Observaciones<textarea name="notes" rows="3"></textarea></label>
    <div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button>${historical ? '<button class="button primary" type="submit" name="purchase_action" value="historical">Registrar compra histórica</button>' : '<button class="button secondary" type="submit" name="purchase_action" value="draft">Guardar borrador</button><button class="button primary" type="submit" name="purchase_action" value="confirm">Confirmar compra</button>'}</div>
  </form>`, { wide: true });

  const form = $('#supplierPurchaseForm');
  form.addEventListener('input', () => updateTotals(form));
  form.addEventListener('click', (event) => {
    if (event.target.closest('[data-add-purchase-item]')) {
      $('[data-purchase-items]', form).insertAdjacentHTML('beforeend', purchaseItemRow());
      updateTotals(form);
    }
    const remove = event.target.closest('[data-remove-purchase-item]');
    if (remove) {
      const rows = form.querySelectorAll('[data-purchase-item]');
      if (rows.length === 1) return toast('La compra debe conservar al menos un producto.', 'warning');
      remove.closest('[data-purchase-item]').remove();
      updateTotals(form);
    }
  });
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    try {
      const data = Object.fromEntries(new FormData(form));
      const requestedAction = historical ? 'historical' : (event.submitter?.value || 'confirm');
      const items = normalizePurchaseItems(collectItems(form));
      const totals = calculatePurchaseTotals(items, { discountAmount: data.discount_amount, taxAmount: data.tax_amount, freightAmount: data.freight_amount });
      const accepted = await confirmAction({
        title: historical ? 'Registrar compra histórica' : requestedAction === 'draft' ? 'Guardar compra en borrador' : 'Confirmar compra',
        message: historical
          ? 'Se registrará solo para trazabilidad. El inventario y las cuentas actuales no cambiarán.'
          : requestedAction === 'draft'
            ? 'La compra quedará guardada para completarla después. No modificará inventario físico ni caja.'
            : 'La compra quedará confirmada y lista para recibir mercancía o registrar pagos. Confirmarla no descuenta dinero ni aumenta el inventario físico.',
        confirmLabel: historical ? 'Registrar compra histórica' : requestedAction === 'draft' ? 'Guardar borrador' : 'Confirmar compra',
        details: [{ label: 'Proveedor', value: supplier.business_name }, { label: 'Productos', value: String(items.length) }, moneyDetail('Total', totals.total)]
      });
      if (!accepted) return;
      const commonPayload = {
        supplierId,
        purchaseDate: data.purchase_date,
        expectedDate: data.expected_date,
        invoiceNumber: data.invoice_number,
        dueDate: data.due_date,
        discountAmount: Number(data.discount_amount || 0),
        taxAmount: Number(data.tax_amount || 0),
        freightAmount: Number(data.freight_amount || 0),
        notes: data.notes,
        items
      };
      if (historical) {
        await createHistoricalSupplierPurchase({
          ...commonPayload,
          historicalPaidAmount: Number(data.historical_paid_amount || 0),
          historicalPaymentMethod: data.historical_payment_method,
          historicalPaymentDate: data.historical_payment_date,
          sourceReference: data.source_reference,
          operationKey: createOperationKey('compra_historica_proveedor')
        });
      } else {
        const createKey = createOperationKey('crear_compra_proveedor');
        const purchase = await createSupplierPurchase({ ...commonPayload, operationKey: createKey });
        if (requestedAction === 'confirm') {
          await confirmSupplierPurchase(purchase.id, `${createKey}:confirm`);
        }
      }
      closeModal();
      toast(historical
        ? 'Compra histórica registrada sin afectar inventario ni caja.'
        : requestedAction === 'draft'
          ? 'Compra guardada como borrador.'
          : 'Compra confirmada. Ya puedes recibir mercancía o registrar el pago.');
      document.dispatchEvent(new CustomEvent('lihen:refresh'));
    } catch (error) { toast(error.message, 'danger'); }
  });
  updateTotals(form);
}

function purchaseActions(purchase) {
  const actions = [];
  if (purchase.is_historical) return '<span class="privacy">Registro histórico · sin impacto actual</span>';
  if (purchase.status === 'borrador') actions.push(`<button class="button primary" data-confirm-purchase="${purchase.id}">Confirmar compra</button>`);
  if (!['borrador', 'cancelada'].includes(purchase.status) && purchase.reception_status !== 'completa') actions.push(`<button class="button secondary" data-receive-purchase="${purchase.id}">Recibir mercancía</button>`);
  if (!['borrador', 'cancelada'].includes(purchase.status) && Number(purchase.balance_due || 0) > 0) actions.push(`<button class="button secondary" data-pay-purchase="${purchase.id}">Registrar pago</button>`);
  return actions.join('');
}

export async function viewSupplierPurchases(supplierId) {
  const supplier = state.suppliers.find((item) => item.id === supplierId);
  const purchases = await loadSupplierPurchases(supplierId);
  modal(`Compras · ${supplier?.business_name || 'Proveedor'}`, purchases.length ? `<div class="purchase-history">${purchases.map((purchase) => {
    const summary = summarizePurchase(purchase);
    return `<article class="purchase-card" data-purchase-card="${purchase.id}"><header><div><p class="eyebrow">${escapeHtml(purchase.invoice_number || 'SIN FACTURA')}</p><h3>${dateTime(purchase.purchase_date || purchase.created_at)}</h3></div><div>${purchase.is_historical ? badge('histórica') : ''} ${badge(purchase.status)} ${badge(purchase.payment_status || 'pendiente')}</div></header><div class="purchase-summary"><span>Total <b>${money(summary.total)}</b></span><span>Pagado <b>${money(summary.paid)}</b></span><span>Pendiente <b>${money(summary.pending)}</b></span></div><div class="purchase-products">${(purchase.items || []).map((item) => `<div><span>${escapeHtml(item.product?.name || 'Producto')}</span><b>${item.quantity_requested} × ${money(item.quoted_unit_cost)}</b></div>`).join('')}</div><footer>${purchaseActions(purchase)}</footer></article>`;
  }).join('')}</div>` : `<div class="empty"><span>◇</span><h3>Sin compras</h3><p>Aún no se han registrado compras para este proveedor.</p><button class="button primary" data-new-purchase-from-history="${supplierId}">Registrar primera compra</button></div>`, { wide: true });

  const root = $('#modalRoot');
  root.addEventListener('click', async (event) => {
    const first = event.target.closest('[data-new-purchase-from-history]');
    if (first) { closeModal(); return newSupplierPurchase(first.dataset.newPurchaseFromHistory); }
    const confirmButton = event.target.closest('[data-confirm-purchase]');
    if (confirmButton) return handleConfirmPurchase(confirmButton.dataset.confirmPurchase, supplierId);
    const receiveButton = event.target.closest('[data-receive-purchase]');
    if (receiveButton) return openReceivePurchase(receiveButton.dataset.receivePurchase, supplierId);
    const payButton = event.target.closest('[data-pay-purchase]');
    if (payButton) return openSupplierPayment(payButton.dataset.payPurchase, supplierId);
  }, { once: false });
}

async function handleConfirmPurchase(purchaseId, supplierId) {
  const purchase = state.supplierPurchases.find((item) => item.id === purchaseId);
  const accepted = await confirmAction({ title: 'Confirmar compra', message: 'Al confirmar, la compra quedará lista para registrar recepciones.', confirmLabel: 'Confirmar compra', details: [moneyDetail('Total', purchase?.total_amount)] });
  if (!accepted) return;
  try { await confirmSupplierPurchase(purchaseId, createOperationKey('confirmar_compra')); toast('Compra confirmada.'); closeModal(); await viewSupplierPurchases(supplierId); } catch (error) { toast(error.message, 'danger'); }
}

async function openReceivePurchase(purchaseId, supplierId) {
  const purchase = state.supplierPurchases.find((item) => item.id === purchaseId);
  if (!purchase) return;
  modal('Recibir mercancía', `<form id="receivePurchaseForm" class="form-grid"><p class="full privacy">Registra únicamente las unidades recibidas en esta entrega.</p>${(purchase.items || []).map((item) => { const received = Number(item.quantity_received || 0); const pending = Math.max(0, Number(item.quantity_requested || 0) - received); return `<label class="full">${escapeHtml(item.product?.name || 'Producto')} · pendiente ${pending}<input name="qty_${item.id}" data-item-id="${item.id}" data-product-id="${item.product_id}" data-max="${pending}" type="number" min="0" max="${pending}" step="1" value="${pending}"></label>`; }).join('')}<label class="full">Observaciones<textarea name="notes" rows="3"></textarea></label><div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary">Registrar recepción</button></div></form>`);
  $('#receivePurchaseForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    try {
      const items = [...form.querySelectorAll('[data-item-id]')].map((input) => ({ supplier_request_item_id: input.dataset.itemId, product_id: input.dataset.productId, quantity_received: Number(input.value), final_unit_cost: Number(purchase.items.find((item) => item.id === input.dataset.itemId)?.quoted_unit_cost || 0) })).filter((item) => item.quantity_received > 0);
      if (!items.length) throw new Error('Indica al menos una cantidad recibida.');
      const accepted = await confirmAction({ title: 'Registrar recepción', message: 'Las unidades recibidas aumentarán el inventario físico.', confirmLabel: 'Recibir mercancía', details: [{ label: 'Unidades', value: String(items.reduce((sum, item) => sum + item.quantity_received, 0)) }] });
      if (!accepted) return;
      await receiveSupplierPurchase(purchaseId, items, form.elements.notes.value, createOperationKey('recibir_compra'));
      toast('Recepción registrada.'); closeModal(); await viewSupplierPurchases(supplierId);
    } catch (error) { toast(error.message, 'danger'); }
  });
}

async function openSupplierPayment(purchaseId, supplierId) {
  const purchase = state.supplierPurchases.find((item) => item.id === purchaseId);
  await loadFinancialAccounts();
  const accounts = state.financialAccounts.filter((account) => account.active !== false && account.initial_balance_configured);
  modal('Registrar pago a proveedor', `<form id="supplierPaymentForm" class="form-grid">
    <label class="full">Origen del dinero<select name="payment_source"><option value="lihen">Cuenta de LIHEN</option><option value="external">Dinero personal / externo</option></select></label>
    <label class="full" data-lihen-account-field>Cuenta LIHEN<select name="account_id"><option value="">Selecciona</option>${accounts.map((account) => `<option value="${account.id}">${escapeHtml(account.name)} · ${money(account.current_balance)}</option>`).join('')}</select></label>
    <div class="callout full" data-external-payment-note hidden><b>Pago fuera de caja LIHEN</b><p>Este pago reducirá la deuda con el proveedor, pero no descontará dinero de Nequi ni del efectivo de LIHEN.</p></div>
    <label>Valor<input name="amount" type="number" min="1" max="${Number(purchase.balance_due || 0)}" value="${Number(purchase.balance_due || 0)}" required></label>
    <label>Fecha y hora<input name="paid_at" type="datetime-local" value="${dateTimeInputValue()}" required></label>
    <label>Medio de pago<select name="payment_method"><option value="nequi">Nequi</option><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option><option value="otro">Otro</option></select></label>
    <label>Referencia<input name="reference_number"></label>
    <label class="full">Observaciones<textarea name="notes" rows="3"></textarea></label>
    <div class="form-actions full"><button type="button" class="button ghost" data-close-modal>Cancelar</button><button class="button primary">Registrar pago</button></div>
  </form>`);
  const form = $('#supplierPaymentForm');
  const sourceSelect = form.elements.payment_source;
  const accountField = $('[data-lihen-account-field]', form);
  const externalNote = $('[data-external-payment-note]', form);
  const syncSource = () => {
    const external = sourceSelect.value === 'external';
    accountField.hidden = external;
    externalNote.hidden = !external;
    form.elements.account_id.required = !external;
    if (external) form.elements.account_id.value = '';
  };
  sourceSelect.addEventListener('change', syncSource);
  syncSource();
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(event.currentTarget));
    const external = data.payment_source === 'external';
    const account = external ? null : accounts.find((item) => item.id === data.account_id);
    const amount = Number(data.amount);
    try {
      if (!external && !account) throw new Error('Selecciona una cuenta válida de LIHEN.');
      if (!(amount > 0) || amount > Number(purchase.balance_due || 0)) throw new Error('El pago supera el saldo pendiente.');
      if (!external && Number(account.current_balance) < amount) throw new Error('La cuenta seleccionada no tiene saldo suficiente.');
      const details = [
        { label: 'Origen', value: external ? 'Dinero personal / externo' : 'Cuenta LIHEN' },
        ...(account ? [{ label: 'Cuenta', value: account.name }] : []),
        moneyDetail('Valor', amount),
        ...(account ? [moneyDetail('Saldo actual', Number(account.current_balance)), moneyDetail('Saldo posterior estimado', Number(account.current_balance) - amount)] : [])
      ];
      const accepted = await confirmAction({
        title: 'Registrar pago',
        message: external
          ? 'El proveedor quedará pagado por este valor sin afectar las cuentas de LIHEN.'
          : 'El valor se descontará únicamente de la cuenta de LIHEN seleccionada.',
        confirmLabel: external ? 'Confirmar pago externo' : 'Pagar proveedor',
        tone: 'warning',
        details
      });
      if (!accepted) return;
      await registerSupplierPayment({
        purchaseId,
        accountId: account?.id || null,
        paymentSource: external ? 'external' : 'lihen',
        amount,
        paymentMethod: data.payment_method,
        paidAt: new Date(data.paid_at).toISOString(),
        referenceNumber: data.reference_number,
        notes: data.notes,
        operationKey: createOperationKey('pago_proveedor')
      });
      toast(external ? 'Pago externo registrado sin afectar caja LIHEN.' : 'Pago registrado y descontado de la cuenta seleccionada.');
      closeModal();
      await viewSupplierPurchases(supplierId);
    } catch (error) { toast(error.message, 'danger'); }
  });
}

export async function newHistoricalSupplierPurchase(supplierId) {
  return newSupplierPurchase(supplierId, { historical: true });
}
