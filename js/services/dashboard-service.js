export function buildDashboard({ orders = [], quickSales = [], inventory = [], products = [], customerCount = 0, movements = [] }) {
  const today = new Date().toISOString().slice(0, 10);
  const todaySales = quickSales.filter(sale => String(sale.created_at || '').slice(0,10) === today && sale.status !== 'anulada');
  return {
    activeOrders: orders.filter(order => !['entregado','cancelado'].includes(order.status)).length,
    readyOrders: orders.filter(order => order.status === 'pedido_completo').length,
    unitsAvailable: inventory.reduce((sum, row) => sum + (row.available_stock || 0), 0),
    lowStock: inventory.filter(row => (row.available_stock || 0) <= (row.product?.minimum_stock || 0)).length,
    pendingToReceive: inventory.reduce((sum, row) => sum + (row.pending_stock || 0), 0),
    visibleProducts: products.filter(product => product.visible_on_website).length,
    customers: customerCount,
    recentOrders: orders,
    movements,
    quickSalesToday: todaySales.length,
    quickSalesRevenue: todaySales.reduce((sum, row) => sum + Number(row.total || 0), 0),
    recentQuickSales: quickSales
  };
}
