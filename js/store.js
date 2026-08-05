import { supabase } from './supabase.js';

const PASSWORD_RECOVERY_KEY = 'lihen_password_recovery';
const INITIAL_AUTH_URL = window.location.href;

export const state = {
  session: null,
  profile: null,
  route: 'dashboard',
  loading: false,
  dashboard: null,
  products: [],
  inventory: [],
  orders: [],
  customers: [],
  suppliers: [],
  movements: [],
  reports: null
};

export function markPasswordRecovery() {
  window.sessionStorage.setItem(PASSWORD_RECOVERY_KEY, 'true');
}

export function clearPasswordRecovery() {
  window.sessionStorage.removeItem(PASSWORD_RECOVERY_KEY);
}

export function isPasswordRecoveryPending() {
  return window.sessionStorage.getItem(PASSWORD_RECOVERY_KEY) === 'true';
}

export async function loadSession() {
  const {
    data: { session },
    error
  } = await supabase.auth.getSession();

  if (error) throw error;

  state.session = session;

  if (session) {
    await loadProfile();
  } else {
    state.profile = null;
  }

  return session;
}

export async function loadProfile() {
  if (!state.session?.user?.id) {
    state.profile = null;
    return null;
  }

  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', state.session.user.id)
    .single();

  if (error) throw error;

  state.profile = data;
  return data;
}

export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password
  });

  if (error) throw error;

  state.session = data.session;
  await loadProfile();
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;

  state.session = null;
  state.profile = null;
}

export async function updatePassword(password) {
  const { data, error } = await supabase.auth.updateUser({
    password
  });

  if (error) throw error;
  return data;
}

export async function sendPasswordReset(email) {
  const redirectTo = new URL('./', window.location.href).href;

  const { data, error } = await supabase.auth.resetPasswordForEmail(
    email,
    { redirectTo }
  );

  if (error) throw error;
  return data;
}

function urlContainsAuthCallback(urlValue) {
  const url = new URL(urlValue);
  const hash = new URLSearchParams(url.hash.replace(/^#/, ''));
  const query = url.searchParams;

  return (
    ['invite', 'recovery'].includes(hash.get('type')) ||
    ['invite', 'recovery'].includes(query.get('type')) ||
    hash.has('access_token') ||
    query.has('code')
  );
}

export function isAuthCallback() {
  return (
    urlContainsAuthCallback(INITIAL_AUTH_URL) ||
    urlContainsAuthCallback(window.location.href)
  );
}

export async function loadDashboard(){
  const [orders, inventory, products, customers, movements] = await Promise.all([
    supabase.from('orders').select('id,order_number,status,total,created_at,customer:customers(full_name)').order('created_at',{ascending:false}).limit(8),
    supabase.from('inventory').select('physical_stock,reserved_stock,available_stock,pending_stock,product:products(id,name,minimum_stock)').limit(500),
    supabase.from('products').select('id,status,visible_on_website').limit(500),
    supabase.from('customers').select('id',{count:'exact',head:true}),
    supabase.from('inventory_movements').select('id,movement_type,quantity,reason,created_at,product_inventory:inventory(product:products(name)),user:profiles(full_name)').order('created_at',{ascending:false}).limit(8)
  ]);
  for(const r of [orders,inventory,products,customers,movements]) if(r.error) throw r.error;
  const inv=inventory.data||[], ord=orders.data||[];
  state.dashboard={
    activeOrders:ord.filter(o=>!['entregado','cancelado'].includes(o.status)).length,
    readyOrders:ord.filter(o=>o.status==='pedido_completo').length,
    unitsAvailable:inv.reduce((a,x)=>a+(x.available_stock||0),0),
    lowStock:inv.filter(x=>(x.available_stock||0)<=(x.product?.minimum_stock||0)).length,
    pendingToReceive:inv.reduce((a,x)=>a+(x.pending_stock||0),0),
    visibleProducts:(products.data||[]).filter(x=>x.visible_on_website).length,
    customers:customers.count||0,
    recentOrders:ord,
    movements:movements.data||[]
  }; return state.dashboard;
}
export async function loadProducts(search=''){
  let q=supabase.from('products').select('*,inventory(id,physical_stock,reserved_stock,available_stock,pending_stock,average_cost),supplier_products(preferred,supplier:suppliers(id,business_name,whatsapp))').order('name');
  if(search) q=q.ilike('name',`%${search}%`);
  const {data,error}=await q.limit(300); if(error) throw error; state.products=data||[]; return state.products;
}
export async function loadOrders(search=''){
  let q=supabase.from('orders').select('*,customer:customers(id,full_name,whatsapp),items:order_items(id,quantity,unit_price,line_total,product_name_snapshot,quantity_to_source,quantity_received)').order('created_at',{ascending:false});
  if(search) q=q.or(`order_number.ilike.%${search}%`);
  const {data,error}=await q.limit(200); if(error) throw error; state.orders=data||[]; return state.orders;
}
export async function loadCustomers(search=''){
  let q=supabase.from('customers').select('*,addresses:customer_addresses(*)').order('full_name'); if(search) q=q.or(`full_name.ilike.%${search}%,whatsapp.ilike.%${search}%`);
  const {data,error}=await q.limit(300); if(error) throw error; state.customers=data||[]; return state.customers;
}
export async function loadSuppliers(search=''){
  let q=supabase.from('suppliers').select('*,supplier_products(id,preferred,product:products(id,name))').order('business_name'); if(search) q=q.or(`business_name.ilike.%${search}%,whatsapp.ilike.%${search}%`);
  const {data,error}=await q.limit(300); if(error) throw error; state.suppliers=data||[]; return state.suppliers;
}
export async function loadMovements(){
  const {data,error}=await supabase.from('inventory_movements').select('*,inventory(product:products(name)),user:profiles(full_name),order:orders(order_number),supplier_request:supplier_requests(request_number)').order('created_at',{ascending:false}).limit(300);
  if(error) throw error; state.movements=data||[]; return state.movements;
}

export async function loadReports(){
  const [orders, items, products, suppliers] = await Promise.all([
    supabase.from('orders').select('id,status,total,discount_amount,delivery_cost,created_at,payment_status').order('created_at',{ascending:true}).limit(2000),
    supabase.from('order_items').select('quantity,line_total,product_name_snapshot,product_id').limit(5000),
    supabase.from('products').select('id,name,current_cost,sale_price,visible_on_website').limit(1000),
    supabase.from('suppliers').select('id,business_name,active').limit(500)
  ]);
  for(const r of [orders,items,products,suppliers]) if(r.error) throw r.error;
  const completed=(orders.data||[]).filter(o=>o.status==='entregado');
  const revenue=completed.reduce((a,o)=>a+Number(o.total||0),0);
  const paid=completed.filter(o=>o.payment_status==='pagado').reduce((a,o)=>a+Number(o.total||0),0);
  const byProduct=new Map();
  for(const i of items.data||[]){const key=i.product_name_snapshot||'Producto';const row=byProduct.get(key)||{name:key,units:0,revenue:0};row.units+=Number(i.quantity||0);row.revenue+=Number(i.line_total||0);byProduct.set(key,row);}
  const monthly=new Map();
  for(const o of completed){const d=new Date(o.created_at);const key=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;monthly.set(key,(monthly.get(key)||0)+Number(o.total||0));}
  state.reports={revenue,paid,completed:completed.length,average:completed.length?revenue/completed.length:0,topProducts:[...byProduct.values()].sort((a,b)=>b.units-a.units).slice(0,8),monthly:[...monthly.entries()].slice(-8),visible:(products.data||[]).filter(p=>p.visible_on_website).length,totalProducts:(products.data||[]).length,activeSuppliers:(suppliers.data||[]).filter(s=>s.active).length};
  return state.reports;
}
