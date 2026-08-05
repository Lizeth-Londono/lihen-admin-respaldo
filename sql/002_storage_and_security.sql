-- LIHEN ADMIN · MIGRACIÓN 002
-- Storage privado y permisos complementarios
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('productos-publicos','productos-publicos',true,10485760,array['image/jpeg','image/png','image/webp']),
  ('comprobantes-privados','comprobantes-privados',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

alter table storage.objects enable row level security;

drop policy if exists "lectura_publica_productos" on storage.objects;
create policy "lectura_publica_productos"
on storage.objects for select
to public
using (bucket_id='productos-publicos');

drop policy if exists "cofundadoras_gestionan_productos" on storage.objects;
create policy "cofundadoras_gestionan_productos"
on storage.objects for all
to authenticated
using (bucket_id='productos-publicos' and public.is_active_cofounder())
with check (bucket_id='productos-publicos' and public.is_active_cofounder());

drop policy if exists "cofundadoras_gestionan_comprobantes" on storage.objects;
create policy "cofundadoras_gestionan_comprobantes"
on storage.objects for all
to authenticated
using (bucket_id='comprobantes-privados' and public.is_active_cofounder())
with check (bucket_id='comprobantes-privados' and public.is_active_cofounder());

commit;
