const amount = value => Number(value || 0);

export function buildFinancialAlerts({ supplierPurchases = [], supplierPurchaseItems = [], supplierPayments = [], financialAccounts = [], today = new Date() }) {
  const alerts = [];
  const todayDate = new Date(today);
  todayDate.setHours(0, 0, 0, 0);
  const paymentsByPurchase = new Map();
  for (const payment of supplierPayments.filter(row => row.status === 'activo')) {
    paymentsByPurchase.set(payment.supplier_request_id, (paymentsByPurchase.get(payment.supplier_request_id) || 0) + amount(payment.amount));
  }
  const itemsByPurchase = new Map();
  for (const item of supplierPurchaseItems) {
    const rows = itemsByPurchase.get(item.supplier_request_id) || [];
    rows.push(item);
    itemsByPurchase.set(item.supplier_request_id, rows);
  }

  for (const purchase of supplierPurchases.filter(row => String(row.status || '') !== 'cancelada')) {
    const balance = amount(purchase.balance_due);
    const supplierName = purchase.supplier?.business_name || 'Proveedor';
    if (balance > 0 && purchase.due_date) {
      const due = new Date(`${purchase.due_date}T00:00:00`);
      const days = Math.ceil((due - todayDate) / 86400000);
      if (days < 0) alerts.push({ severity: 'critical', type: 'overdue_purchase', title: 'Compra vencida', message: `${supplierName}: saldo pendiente de ${balance} con ${Math.abs(days)} día(s) de vencimiento.`, purchaseId: purchase.id });
      else if (days <= 7) alerts.push({ severity: 'warning', type: 'purchase_due_soon', title: 'Compra próxima a vencer', message: `${supplierName}: vence en ${days} día(s) y tiene saldo pendiente de ${balance}.`, purchaseId: purchase.id });
    }
    if (purchase.reception_status === 'completa' && balance > 0) alerts.push({ severity: 'info', type: 'received_unpaid', title: 'Mercancía recibida pendiente de pago', message: `${supplierName}: la compra fue recibida y aún tiene saldo pendiente de ${balance}.`, purchaseId: purchase.id });
    const activePaid = paymentsByPurchase.get(purchase.id) || 0;
    if (Math.abs(activePaid - amount(purchase.amount_paid)) > 0.01) alerts.push({ severity: 'critical', type: 'payment_mismatch', title: 'Diferencia en pagos', message: `${supplierName}: el total de pagos activos no coincide con el valor pagado registrado.`, purchaseId: purchase.id });
    const invalidCost = (itemsByPurchase.get(purchase.id) || []).some(item => amount(item.received_quantity) > 0 && amount(item.quoted_unit_cost) <= 0);
    if (invalidCost) alerts.push({ severity: 'critical', type: 'received_without_cost', title: 'Producto recibido sin costo', message: `${supplierName}: existe mercancía recibida con costo cero o inválido.`, purchaseId: purchase.id });
  }

  for (const account of financialAccounts.filter(row => row.active && row.initial_balance_configured)) {
    const balance = amount(account.current_balance);
    if (balance < 0) alerts.push({ severity: 'critical', type: 'negative_balance', title: 'Saldo negativo', message: `${account.name} presenta un saldo negativo de ${Math.abs(balance)}.`, accountId: account.id });
    else if (balance === 0) alerts.push({ severity: 'warning', type: 'empty_account', title: 'Cuenta sin saldo', message: `${account.name} no tiene dinero disponible.`, accountId: account.id });
  }

  const rank = { critical: 0, warning: 1, info: 2 };
  return alerts.sort((a, b) => rank[a.severity] - rank[b.severity]);
}
