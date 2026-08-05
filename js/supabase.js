import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.57.4/+esm';
import { APP_CONFIG } from './config.js';

export const supabase = createClient(
  APP_CONFIG.supabaseUrl,
  APP_CONFIG.supabasePublishableKey,
  {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    global: { headers: { 'x-application-name': 'lihen-admin' } }
  }
);
