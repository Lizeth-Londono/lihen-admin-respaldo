import { buildFinancialAlerts } from './financial-alert-service.js';
const amount = value => Number(value || 0);
const isTransfer = movement => ['transferencia_entrada', 'transferencia_salida'].includes(movement.movement_type);
const isActiveMovement = movement => movement.status === 'activo' && movement.reporting_excluded !== true;

function monthKey(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function activeItemRows({ completedOrders, completedSales, orderItems, quickSaleItems }) {
  const orderDates = new Map(completedOrders.map(row => [row.id, row.created_at]));
  const saleDates = new Map(completedSales.map(row => [row.id, row.created_at]));
  return [
    ...orderItems.filter(item => orderDates.has(item.order_id)).map(item => ({ ...item, sold_at: orderDates.get(item.order_id) })),
    ...quickSaleItems.filter(item => saleDates.has(item.sale_id)).map(item => ({ ...item, sold_at: saleDates.get(item.sale_id) }))
  ];
}


export function buildReports({
  orders = [], orderItems = [], quickSales = [], quickSaleItems = [], products = [], suppliers = [],
  supplierPurchases = [], supplierPurchaseItems = [], supplierPayments = [], financialAccounts = [], financialMovements = [], productCostHistory = []
}) {
  const completedOrders = orders.filter(order => order.status === 'entregado' && order.reconstruction_archived !== true);
  const completedSales = quickSales.filter(sale => sale.status === 'completada' && sale.reconstruction_archived !== true);
  const soldItems = activeItemRows({ completedOrders, completedSales, orderItems, quickSaleItems });
  const productMap = new Map(products.map(product => [product.id, product]));

  const orderRevenue = completedOrders.reduce((sum, order) => sum + amount(order.total), 0);
  const quickRevenue = completedSales.reduce((sum, sale) => sum + amount(sale.total), 0);
  const revenue = orderRevenue + quickRevenue;

  const activeMovements = financialMovements.filter(isActiveMovement);
  const operatingMovements = activeMovements.filter(movement => !isTransfer(movement));
  const collectedIncome = operatingMovements
    .filter(movement => ['ingreso', 'ajuste_positivo'].includes(movement.movement_type))
    .reduce((sum, movement) => sum + amount(movement.amount), 0);
  const paidOut = operatingMovements
    .filter(movement => ['egreso', 'ajuste_negativo'].includes(movement.movement_type))
    .reduce((sum, movement) => sum + amount(movement.amount), 0);

  const validPurchases = supplierPurchases.filter(purchase => !purchase.is_historical && String(purchase.status || '') !== 'cancelada');
  const purchasesTotal = validPurchases.reduce((sum, purchase) => sum + amount(purchase.total_amount), 0);
  const accountsPayable = validPurchases.reduce((sum, purchase) => sum + amount(purchase.balance_due), 0);
  const supplierPaid = supplierPayments.filter(payment => payment.status === 'activo').reduce((sum, payment) => sum + amount(payment.amount), 0);
  const availableMoney = financialAccounts.filter(account => account.active && account.initial_balance_configured).reduce((sum, account) => sum + amount(account.current_balance), 0);
  const nequiBalance = financialAccounts.filter(account => account.active && String(account.code).toLowerCase() === 'nequi').reduce((sum, account) => sum + amount(account.current_balance), 0);
  const cashBalance = financialAccounts.filter(account => account.active && (String(account.code).toLowerCase() === 'efectivo' || account.account_type === 'efectivo')).reduce((sum, account) => sum + amount(account.current_balance), 0);

  const costHistoryByProduct = new Map();
  for (const row of productCostHistory) {
    if (!costHistoryByProduct.has(row.product_id)) costHistoryByProduct.set(row.product_id, []);
    costHistoryByProduct.get(row.product_id).push(row);
  }
  const costAtSale = item => {
    const soldAt = new Date(item.sold_at || 0).getTime();
    const history = costHistoryByProduct.get(item.product_id) || [];
    let selected = null;
    for (const row of history) {
      const at = new Date(row.created_at || 0).getTime();
      if (Number.isFinite(at) && at <= soldAt) selected = row;
    }
    return amount(selected?.new_product_cost ?? selected?.purchased_unit_cost ?? productMap.get(item.product_id)?.current_cost);
  };
  const cogs = soldItems.reduce((sum, item) => sum + amount(item.quantity) * costAtSale(item), 0);
  const grossProfit = revenue - cogs;

  const byProduct = new Map();
  for (const item of soldItems) {
    const key = item.product_id || item.product_name_snapshot || 'Producto';
    const row = byProduct.get(key) || { name: item.product_name_snapshot || productMap.get(item.product_id)?.name || 'Producto', units: 0, revenue: 0 };
    row.units += amount(item.quantity);
    row.revenue += amount(item.line_total);
    byProduct.set(key, row);
  }

  const monthly = new Map();
  for (const record of [...completedOrders, ...completedSales]) {
    const key = monthKey(record.created_at);
    if (key) monthly.set(key, (monthly.get(key) || 0) + amount(record.total));
  }

  const transactionCount = completedOrders.length + completedSales.length;
  const receivedUnits = supplierPurchaseItems.reduce((sum, item) => sum + amount(item.quantity_received ?? item.received_quantity), 0);
  return {
    revenue,
    collectedIncome,
    purchasesTotal,
    supplierPaid,
    paidOut,
    netCashFlow: collectedIncome - paidOut,
    availableMoney,
    nequiBalance,
    cashBalance,
    accountsPayable,
    cogs,
    grossProfit,
    completed: completedOrders.length,
    quickSales: completedSales.length,
    quickRevenue,
    average: transactionCount ? revenue / transactionCount : 0,
    soldUnits: soldItems.reduce((sum, item) => sum + amount(item.quantity), 0),
    receivedUnits,
    topProducts: [...byProduct.values()].sort((a, b) => b.units - a.units).slice(0, 8),
    monthly: [...monthly.entries()].sort(([a], [b]) => a.localeCompare(b)).slice(-8),
    visible: products.filter(product => product.visible_on_website).length,
    totalProducts: products.length,
    activeSuppliers: suppliers.filter(supplier => supplier.active).length,
    supplierPurchases: validPurchases,
    financialAccounts,
    financialMovements: activeMovements,
    alerts: buildFinancialAlerts({ supplierPurchases: validPurchases, supplierPurchaseItems, supplierPayments, financialAccounts })
  };
}
