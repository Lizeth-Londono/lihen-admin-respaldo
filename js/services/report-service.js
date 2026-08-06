export function buildReports({ orders = [], orderItems = [], quickSales = [], quickSaleItems = [], products = [], suppliers = [] }) {
  const completedOrders = orders.filter(order => order.status === 'entregado');
  const completedSales = quickSales.filter(sale => sale.status === 'completada');
  const orderRevenue = completedOrders.reduce((sum, order) => sum + Number(order.total || 0), 0);
  const quickRevenue = completedSales.reduce((sum, sale) => sum + Number(sale.total || 0), 0);
  const revenue = orderRevenue + quickRevenue;
  const paid = completedOrders.filter(order => order.payment_status === 'pagado').reduce((sum, order) => sum + Number(order.total || 0), 0);
  const byProduct = new Map();
  for (const item of [...orderItems, ...quickSaleItems]) {
    const key = item.product_name_snapshot || 'Producto';
    const row = byProduct.get(key) || { name: key, units: 0, revenue: 0 };
    row.units += Number(item.quantity || 0);
    row.revenue += Number(item.line_total || 0);
    byProduct.set(key, row);
  }
  const monthly = new Map();
  for (const order of completedOrders) {
    const date = new Date(order.created_at);
    const key = `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}`;
    monthly.set(key, (monthly.get(key) || 0) + Number(order.total || 0));
  }
  const transactionCount = completedOrders.length + completedSales.length;
  return {
    revenue,
    paid,
    completed: completedOrders.length,
    quickSales: completedSales.length,
    quickRevenue,
    average: transactionCount ? revenue / transactionCount : 0,
    topProducts: [...byProduct.values()].sort((a,b) => b.units - a.units).slice(0,8),
    monthly: [...monthly.entries()].slice(-8),
    visible: products.filter(product => product.visible_on_website).length,
    totalProducts: products.length,
    activeSuppliers: suppliers.filter(supplier => supplier.active).length
  };
}
