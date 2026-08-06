import { supabase } from '../supabase.js';
import { unwrap } from './helpers.js';

export async function getSession() {
  const result = await supabase.auth.getSession();
  if (result.error) throw result.error;
  return result.data.session;
}

export async function getProfile(userId) {
  return unwrap(await supabase.from('profiles').select('*').eq('id', userId).single(), 'No fue posible cargar el perfil.');
}

export async function signInWithPassword(email, password) {
  const result = await supabase.auth.signInWithPassword({ email, password });
  if (result.error) throw result.error;
  return result.data;
}

export async function signOutSession() {
  const result = await supabase.auth.signOut();
  if (result.error) throw result.error;
}

export async function changePassword(password) {
  const result = await supabase.auth.updateUser({ password });
  if (result.error) throw result.error;
  return result.data;
}

export async function requestPasswordReset(email, redirectTo) {
  const result = await supabase.auth.resetPasswordForEmail(email, { redirectTo });
  if (result.error) throw result.error;
  return result.data;
}
