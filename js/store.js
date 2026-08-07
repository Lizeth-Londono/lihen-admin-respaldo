import * as authRepository from './repositories/auth-repository.js';
import { fetchDashboardSources } from './repositories/dashboard-repository.js';
import { listProducts } from './repositories/product-repository.js';
import { listOrders } from './repositories/order-repository.js';
import { listQuickSales } from './repositories/quick-sale-repository.js';
import { listCustomers } from './repositories/customer-repository.js';
import { listSuppliers } from './repositories/supplier-repository.js';
import { listMovements } from './repositories/inventory-repository.js';
import { fetchReportSources } from './repositories/report-repository.js';
import { listSupplierPurchases } from './repositories/supplier-purchase-repository.js';
import { listFinancialAccounts, listFinancialMovements } from './repositories/financial-account-repository.js';
import { buildDashboard } from './services/dashboard-service.js';
import { buildReports } from './services/report-service.js';
import { publish } from './core/event-bus.js';

const internalState = {
  session: null,
  profile: null,
  route: 'dashboard',
  loading: false,
  dashboard: null,
  products: [],
  inventory: [],
  orders: [],
  quickSales: [],
  customers: [],
  suppliers: [],
  movements: [],
  reports: null,
  supplierPurchases: [],
  financialAccounts: [],
  financialMovements: []
};

export const state = internalState;

export function updateState(partial) {
  Object.assign(internalState, partial);
  publish('lihen:state-changed', partial);
  return internalState;
}

export async function loadSession() {
  const session = await authRepository.getSession();
  updateState({ session });
  if (session) await loadProfile();
  return session;
}

export async function loadProfile() {
  const profile = await authRepository.getProfile(state.session.user.id);
  updateState({ profile });
  return profile;
}

export async function signIn(email, password) {
  const data = await authRepository.signInWithPassword(email, password);
  updateState({ session: data.session });
  await loadProfile();
  return data;
}

export async function signOut() {
  await authRepository.signOutSession();
  updateState({ session: null, profile: null });
}

export const updatePassword = authRepository.changePassword;

export async function sendPasswordReset(email) {
  const redirectTo = new URL('./', window.location.href).href;
  return authRepository.requestPasswordReset(email, redirectTo);
}

export function isAuthCallback() {
  const hash = new URLSearchParams(window.location.hash.replace(/^#/,''));
  const query = new URLSearchParams(window.location.search);
  return ['invite','recovery'].includes(hash.get('type')) || ['invite','recovery'].includes(query.get('type')) || hash.has('access_token') || query.has('code');
}

export async function loadDashboard() {
  const dashboard = buildDashboard(await fetchDashboardSources());
  updateState({ dashboard });
  return dashboard;
}

export async function loadProducts(search = '') {
  const products = await listProducts(search);
  updateState({ products });
  return products;
}

export async function loadOrders(search = '') {
  const orders = await listOrders(search);
  updateState({ orders });
  return orders;
}

export async function loadQuickSales(search = '') {
  const quickSales = await listQuickSales(search);
  updateState({ quickSales });
  return quickSales;
}

export async function loadCustomers(search = '') {
  const customers = await listCustomers(search);
  updateState({ customers });
  return customers;
}

export async function loadSuppliers(search = '') {
  const suppliers = await listSuppliers(search);
  updateState({ suppliers });
  return suppliers;
}

export async function loadMovements() {
  const movements = await listMovements();
  updateState({ movements });
  return movements;
}

export async function loadReports() {
  const reports = buildReports(await fetchReportSources());
  updateState({ reports });
  return reports;
}

export async function loadSupplierPurchases(supplierId = null) { const supplierPurchases = await listSupplierPurchases(supplierId); updateState({ supplierPurchases }); return supplierPurchases; }
export async function loadFinancialAccounts() { const [financialAccounts, financialMovements] = await Promise.all([listFinancialAccounts(), listFinancialMovements()]); updateState({ financialAccounts, financialMovements }); return { financialAccounts, financialMovements }; }
