import { state, loadSession, signIn, signOut, updatePassword, sendPasswordReset, isAuthCallback } from './store.js';
import { $, $$ } from './utils.js';
import { shell, login, passwordSetup, toast, closeModal, modal } from './ui.js';
import { renderRoute, showOrder } from './views.js';
import { newCustomer, newSupplier, newProduct, newOrder, importCatalog, inventoryAdjustment } from './forms.js';
import { editCustomer, editSupplier, editProduct } from './editors.js';
import { importInventory, importBundledInventory, importSuppliers, importCustomers } from './imports.js';

const app=$('#app');
async function boot(){app.innerHTML='<div class="splash"><img src="assets/logo-lihen.jpg" alt="LIHEN"><span></span><p>Preparando LIHEN Admin…</p></div>';try{await loadSession();if(isAuthCallback()&&state.session){renderPasswordSetup();return;}state.session?await renderApp():renderLogin();}catch(e){console.error(e);renderLogin('No fue posible conectar con Supabase. Revisa la conexión.')};}
function renderLogin(error=''){app.innerHTML=login(error);$('#loginForm')?.addEventListener('submit',async e=>{e.preventDefault();const fd=new FormData(e.currentTarget),button=$('button[type="submit"]',e.currentTarget);button.disabled=true;button.textContent='Ingresando…';try{await signIn(fd.get('email'),fd.get('password'));await renderApp();}catch(err){renderLogin(err.message==='Invalid login credentials'?'Correo o contraseña incorrectos.':err.message)}});}
function renderPasswordSetup(error=''){app.innerHTML=passwordSetup(error);$('#passwordSetupForm').addEventListener('submit',async e=>{e.preventDefault();const fd=new FormData(e.currentTarget),password=fd.get('password'),confirm=fd.get('confirm_password'),button=$('button[type="submit"]',e.currentTarget);if(password!==confirm){renderPasswordSetup('Las contraseñas no coinciden.');return;}button.disabled=true;button.textContent='Guardando…';try{await updatePassword(password);history.replaceState({},document.title,location.pathname);await loadSession();toast('Contraseña creada correctamente');await renderApp();}catch(err){renderPasswordSetup(err.message)}})}
function showPasswordReset(){
  modal('Recuperar contraseña', `
    <form id="resetPasswordForm" class="form-grid">
      <label class="full">Correo de la cofundadora
        <input name="email" type="email" autocomplete="email" required>
      </label>
      <p class="full privacy">Recibirás un enlace seguro para crear una contraseña nueva.</p>
      <div class="form-actions full">
        <button type="button" class="button ghost" data-close-modal>Cancelar</button>
        <button class="button primary" type="submit">Enviar enlace</button>
      </div>
    </form>
  `);

  const form = $('#resetPasswordForm');
  if(!form){
    toast('No fue posible abrir la recuperación de contraseña.','danger');
    return;
  }

  form.addEventListener('submit', async e => {
    e.preventDefault();
    const button = $('button[type="submit"]', e.currentTarget);
    const email = new FormData(e.currentTarget).get('email');
    button.disabled = true;
    button.textContent = 'Enviando…';
    try{
      await sendPasswordReset(email);
      closeModal();
      toast('Revisa tu correo para continuar');
    }catch(err){
      button.disabled = false;
      button.textContent = 'Enviar enlace';
      toast(err.message || 'No fue posible enviar el enlace.','danger');
    }
  });
} 
async function renderApp(){app.innerHTML=shell('<div id="viewRoot"></div>');await refresh();bindGlobal();}
async function refresh(){const root=$('#viewRoot');if(!root)return;root.innerHTML=await renderRoute();bindContent();}
function bindGlobal(){
 $$('[data-route]').forEach(b=>b.addEventListener('click',()=>navigate(b.dataset.route)));
 $('#logoutBtn').addEventListener('click',async()=>{await signOut();renderLogin()});
 $('#menuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));
 bindContent();
}
function bindContent(){
 $$('[data-route]').forEach(b=>{if(!b.dataset.bound){b.dataset.bound='1';b.addEventListener('click',()=>navigate(b.dataset.route))}});
 $$('[data-action]').forEach(b=>{if(!b.dataset.bound){b.dataset.bound='1';b.addEventListener('click',()=>action(b.dataset.action,b.dataset))}});
 $$('[data-order-id]').forEach(b=>b.addEventListener('click',()=>{const o=state.orders.find(x=>x.id===b.dataset.orderId)||state.dashboard?.recentOrders.find(x=>x.id===b.dataset.orderId);if(o)showOrder(o)}));
 $$('[data-edit-customer]').forEach(b=>b.addEventListener('click',()=>editCustomer(b.dataset.editCustomer)));
 $$('[data-edit-supplier]').forEach(b=>b.addEventListener('click',()=>editSupplier(b.dataset.editSupplier)));
 $$('[data-edit-product]').forEach(b=>b.addEventListener('click',()=>editProduct(b.dataset.editProduct)));
 $('#orderStatus')?.addEventListener('change',e=>{$$('tbody tr').forEach(tr=>tr.hidden=e.target.value&&!tr.innerText.toLowerCase().includes(e.target.selectedOptions[0].text.toLowerCase()))});
 const bindTableSearch=(id)=>{$(id)?.addEventListener('input',e=>{const q=e.target.value.trim().toLowerCase();$$('tbody tr').forEach(tr=>tr.hidden=q&&!tr.innerText.toLowerCase().includes(q));});};
 bindTableSearch('#orderSearch');bindTableSearch('#productSearch');bindTableSearch('#customerSearch');
 $('#supplierSearch')?.addEventListener('input',e=>{const q=e.target.value.trim().toLowerCase();$$('.supplier-card').forEach(card=>card.hidden=q&&!card.innerText.toLowerCase().includes(q));});
 $('#productVisibility')?.addEventListener('change',e=>{$$('tbody tr').forEach(tr=>{const text=tr.innerText.toLowerCase();tr.hidden=e.target.value==='visible'&&!text.includes('publicado')||e.target.value==='hidden'&&!text.includes('oculto');});});
}
async function navigate(route){state.route=route;$('#sidebar')?.classList.remove('open');app.innerHTML=shell('<div id="viewRoot"></div>');await refresh();bindGlobal();}
function action(name,dataset={}){({
 'new-order':newOrder,'new-product':newProduct,'new-supplier':newSupplier,'new-customer':newCustomer,'import-catalog':importCatalog,
 'import-inventory':importInventory,'import-bundled-inventory':importBundledInventory,'import-suppliers':importSuppliers,'import-customers':importCustomers,
 'inventory-adjustment':inventoryAdjustment,
 'generate-receipt':()=>toast('Abre un pedido para generar su comprobante.','warning')
}[name]||(()=>{}))();}
document.addEventListener('click', e => {
  const forgotButton = e.target.closest('#forgotPasswordBtn');
  if(forgotButton){
    e.preventDefault();
    showPasswordReset();
  }
});
document.addEventListener('lihen:refresh',refresh);
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeModal()});
boot();
