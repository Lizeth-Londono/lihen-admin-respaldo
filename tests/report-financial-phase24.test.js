import test from 'node:test';
import assert from 'node:assert/strict';
import { buildReports } from '../js/services/report-service.js';
import { buildFinancialAlerts } from '../js/services/financial-alert-service.js';

test('reportes separan ventas, flujo, compras y dinero disponible', () => {
  const report = buildReports({
    orders:[{id:'o1',status:'entregado',total:100,payment_status:'pagado',created_at:'2026-08-01'}],
    orderItems:[{order_id:'o1',product_id:'p1',quantity:2,line_total:100,product_name_snapshot:'Producto'}],
    products:[{id:'p1',current_cost:20,visible_on_website:true}],
    supplierPurchases:[{id:'c1',status:'confirmada',total_amount:60,balance_due:20}],
    supplierPayments:[{supplier_request_id:'c1',status:'activo',amount:40}],
    financialAccounts:[{code:'nequi',account_type:'billetera_digital',current_balance:70,active:true,initial_balance_configured:true},{code:'efectivo',account_type:'efectivo',current_balance:30,active:true,initial_balance_configured:true}],
    financialMovements:[{movement_type:'ingreso',amount:100,status:'activo'},{movement_type:'egreso',amount:40,status:'activo'},{movement_type:'transferencia_entrada',amount:10,status:'activo'}]
  });
  assert.equal(report.revenue,100);
  assert.equal(report.collectedIncome,100);
  assert.equal(report.paidOut,40);
  assert.equal(report.netCashFlow,60);
  assert.equal(report.availableMoney,100);
  assert.equal(report.purchasesTotal,60);
  assert.equal(report.accountsPayable,20);
  assert.equal(report.grossProfit,60);
});

test('alertas detectan vencimientos, diferencias y cuentas sin saldo', () => {
  const alerts=buildFinancialAlerts({
    today:new Date('2026-08-06T12:00:00'),
    supplierPurchases:[{id:'c1',status:'confirmada',due_date:'2026-08-05',balance_due:50,amount_paid:10,reception_status:'completa',supplier:{business_name:'Proveedor'}}],
    supplierPurchaseItems:[{supplier_request_id:'c1',received_quantity:1,quoted_unit_cost:0}],
    supplierPayments:[],
    financialAccounts:[{id:'a1',name:'Nequi',active:true,initial_balance_configured:true,current_balance:0}]
  });
  assert.ok(alerts.some(a=>a.type==='overdue_purchase'));
  assert.ok(alerts.some(a=>a.type==='payment_mismatch'));
  assert.ok(alerts.some(a=>a.type==='received_without_cost'));
  assert.ok(alerts.some(a=>a.type==='empty_account'));
});
