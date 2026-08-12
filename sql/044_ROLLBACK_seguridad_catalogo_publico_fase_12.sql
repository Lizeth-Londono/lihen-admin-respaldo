-- ============================================================
-- LIHEN ADMIN — ROLLBACK 044
-- Rollback conservador de opciones de la vista.
-- IMPORTANTE: por seguridad NO vuelve a conceder acceso anon directo
-- a tablas administrativas, aunque una versión histórica lo hubiera tenido.
-- ============================================================

begin;

alter view public.catalog_public reset (security_barrier);

revoke all on public.catalog_public from public, anon, authenticated;
grant select on public.catalog_public to anon, authenticated;

commit;
