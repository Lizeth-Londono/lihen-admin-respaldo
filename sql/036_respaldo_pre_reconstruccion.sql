-- ============================================================
-- LIHEN ADMIN — RESPALDO LÓGICO PREVIO A RECONSTRUCCIÓN
-- Ejecutar ANTES de 035. No modifica las tablas operativas.
-- ============================================================

begin;
create schema if not exists lihen_backup_20260807;

create table if not exists lihen_backup_20260807.products as table public.products with data;
create table if not exists lihen_backup_20260807.inventory as table public.inventory with data;
create table if not exists lihen_backup_20260807.inventory_movements as table public.inventory_movements with data;
create table if not exists lihen_backup_20260807.orders as table public.orders with data;
create table if not exists lihen_backup_20260807.order_items as table public.order_items with data;
create table if not exists lihen_backup_20260807.payments as table public.payments with data;
create table if not exists lihen_backup_20260807.quick_sales as table public.quick_sales with data;
create table if not exists lihen_backup_20260807.quick_sale_items as table public.quick_sale_items with data;
create table if not exists lihen_backup_20260807.financial_accounts as table public.financial_accounts with data;
create table if not exists lihen_backup_20260807.financial_movements as table public.financial_movements with data;
create table if not exists lihen_backup_20260807.supplier_requests as table public.supplier_requests with data;
create table if not exists lihen_backup_20260807.supplier_request_items as table public.supplier_request_items with data;
create table if not exists lihen_backup_20260807.supplier_payments as table public.supplier_payments with data;
create table if not exists lihen_backup_20260807.supplier_purchase_receipts as table public.supplier_purchase_receipts with data;
create table if not exists lihen_backup_20260807.supplier_purchase_receipt_items as table public.supplier_purchase_receipt_items with data;
create table if not exists lihen_backup_20260807.product_cost_history as table public.product_cost_history with data;
commit;

-- Verificación rápida del respaldo.
select 'products' tabla, count(*) filas from lihen_backup_20260807.products
union all select 'inventory',count(*) from lihen_backup_20260807.inventory
union all select 'orders',count(*) from lihen_backup_20260807.orders
union all select 'quick_sales',count(*) from lihen_backup_20260807.quick_sales
union all select 'financial_accounts',count(*) from lihen_backup_20260807.financial_accounts
union all select 'financial_movements',count(*) from lihen_backup_20260807.financial_movements
order by tabla;
