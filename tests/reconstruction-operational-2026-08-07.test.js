import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(new URL('../sql/034_reconstruccion_operativa_controlada.sql',import.meta.url),'utf8');
const restore=fs.readFileSync(new URL('../sql/035_restaurar_stock_transacciones_existentes.sql',import.meta.url),'utf8');
const hotfix=fs.readFileSync(new URL('../sql/037_hotfix_reconstruccion_sql_editor.sql',import.meta.url),'utf8');
const reportRepo=fs.readFileSync(new URL('../js/repositories/report-repository.js',import.meta.url),'utf8');
const reportService=fs.readFileSync(new URL('../js/services/report-service.js',import.meta.url),'utf8');
const sales=fs.readFileSync(new URL('../js/sales.js',import.meta.url),'utf8');
const orders=fs.readFileSync(new URL('../js/order-workflow.js',import.meta.url),'utf8');

test('reportes usa sale_id canónico y no quick_sale_id',()=>{
  assert.match(reportRepo,/quick_sale_items'\)\.select\('sale_id,/);
  assert.doesNotMatch(reportRepo,/quick_sale_id/);
  assert.match(reportService,/item\.sale_id/);
  assert.doesNotMatch(reportService,/item\.quick_sale_id/);
});

test('reconstrucción conserva caja y es idempotente',()=>{
  assert.match(migration,/apply_operational_reconstruction/);
  assert.match(migration,/operation_key text not null unique/);
  assert.match(migration,/financial_accounts_changed=false/);
  assert.doesNotMatch(migration,/update public\.financial_accounts[\s\S]{0,120}apply_operational_reconstruction/i);
  assert.match(restore,/preview_operational_reconstruction/);
  assert.match(restore,/PASO C/);
  assert.match(restore,/-- select public\.apply_operational_reconstruction/);
});

test('registros anteriores se archivan y no se borran',()=>{
  assert.match(migration,/reconstruction_archived=true/);
  assert.doesNotMatch(migration,/delete\s+from\s+public\.(quick_sales|orders)/i);
  assert.match(migration,/reporting_excluded=true/);
});

test('históricos de venta y pedido afectan inventario pero no caja',()=>{
  assert.match(migration,/create_historical_quick_sale_inventory_atomic_idempotent/);
  assert.match(migration,/create_historical_order_inventory_atomic_idempotent/);
  assert.match(migration,/inventory_impact=true,financial_impact=false/);
  assert.match(sales,/Venta histórica de reconstrucción/);
  assert.match(orders,/Pedido histórico ya vendido/);
});

test('cierre directo consume inventario mediante deliver_order_atomic',()=>{
  assert.match(migration,/v_order := public\.deliver_order_atomic\(p_order_id\)/);
});


test('reconstrucción puede ejecutarse de forma controlada desde SQL Editor postgres',()=>{
  assert.match(migration,/session_user = 'postgres'/);
  assert.match(migration,/where active=true and role='cofundadora'/);
  assert.match(hotfix,/session_user = 'postgres'/);
  assert.match(hotfix,/No modifica inventario ni Caja por sí sola/);
  assert.match(restore,/037_hotfix_reconstruccion_sql_editor\.sql/);
  assert.doesNotMatch(hotfix,/grant execute[^;]+to anon/i);
});
