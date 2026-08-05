-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 007 FINAL
-- Permisos de edición/importación + carga inicial completa del Excel
-- Ejecutar una sola vez en Supabase SQL Editor.
-- Seguro para repetir: actualiza por SKU y no duplica productos.
-- ============================================================
begin;

-- Permisos directos necesarios para los formularios y cargues masivos.
grant select, insert, update on public.products to authenticated;
grant select, insert, update on public.inventory to authenticated;
grant select, insert, update on public.customers to authenticated;
grant select, insert, update on public.customer_addresses to authenticated;
grant select, insert, update on public.suppliers to authenticated;
grant select, insert, update, delete on public.supplier_products to authenticated;
grant select, insert on public.inventory_movements to authenticated;

-- RLS: solamente cofundadoras activas pueden editar datos administrativos.
drop policy if exists "cofundadoras_editan_productos_v2" on public.products;
create policy "cofundadoras_editan_productos_v2" on public.products
for update to authenticated using (public.is_active_cofounder()) with check (public.is_active_cofounder());
drop policy if exists "cofundadoras_crean_productos_v2" on public.products;
create policy "cofundadoras_crean_productos_v2" on public.products
for insert to authenticated with check (public.is_active_cofounder());

drop policy if exists "cofundadoras_editan_inventario_v2" on public.inventory;
create policy "cofundadoras_editan_inventario_v2" on public.inventory
for update to authenticated using (public.is_active_cofounder()) with check (public.is_active_cofounder());
drop policy if exists "cofundadoras_crean_inventario_v2" on public.inventory;
create policy "cofundadoras_crean_inventario_v2" on public.inventory
for insert to authenticated with check (public.is_active_cofounder());

drop policy if exists "cofundadoras_editan_clientes_v2" on public.customers;
create policy "cofundadoras_editan_clientes_v2" on public.customers
for update to authenticated using (public.is_active_cofounder()) with check (public.is_active_cofounder());
drop policy if exists "cofundadoras_crean_clientes_v2" on public.customers;
create policy "cofundadoras_crean_clientes_v2" on public.customers
for insert to authenticated with check (public.is_active_cofounder());

drop policy if exists "cofundadoras_editan_proveedores_v2" on public.suppliers;
create policy "cofundadoras_editan_proveedores_v2" on public.suppliers
for update to authenticated using (public.is_active_cofounder()) with check (public.is_active_cofounder());
drop policy if exists "cofundadoras_crean_proveedores_v2" on public.suppliers;
create policy "cofundadoras_crean_proveedores_v2" on public.suppliers
for insert to authenticated with check (public.is_active_cofounder());

drop policy if exists "cofundadoras_gestionan_relaciones_proveedor_v2" on public.supplier_products;
create policy "cofundadoras_gestionan_relaciones_proveedor_v2" on public.supplier_products
for all to authenticated using (public.is_active_cofounder()) with check (public.is_active_cofounder());

-- Carga inicial tomada del archivo Inventario_LIHEN_Corregido_Final.xlsx.
create temporary table _lihen_seed_inventory (
 sku text, name text, business_line text, category text, brand text,
 current_cost numeric, sale_price numeric, minimum_stock integer,
 physical_stock integer, supplier_name text
) on commit drop;

insert into _lihen_seed_inventory values
('BC-001','Corrector Flawless Tono BEGE 2','Beauty Care','Maquillaje de marca','Ruby Rose',11800.0,15930.0,2,1,'Glow'),
('BC-002','Corrector ushas Tono 08','Beauty Care','Maquillaje de marca','Ushas',6900.0,9315.0,2,1,'Glow'),
('BC-003','Polvo de hadas','Beauty Care','Cuidado corporal','SAS',7900.0,14000.0,2,1,'Glow'),
('BC-004','Base matte Tono 06','Beauty Care','Maquillaje de marca','Ushas',16900.0,22815.0,2,1,'Glow'),
('BC-005','Base matte Tono Becca 00','Beauty Care','Maquillaje de marca','Alissha',14900.0,20115.0,2,1,'Glow'),
('BC-006','Delineador liquido negro','Beauty Care','Maquillaje de marca','Ushas',6900.0,11000.0,2,2,'Glow'),
('BC-007','Big Blender','Beauty Care','Maquillaje de marca','Bloomshell',6900.0,11000.0,2,1,'Glow'),
('BC-008','Poeder sponge','Beauty Care','Maquillaje de marca','New',4900.0,7000.0,2,2,'Glow'),
('BC-009','Pomos de corazon x3','Beauty Care','Maquillaje de marca','Beauty tool',4900.0,7000.0,2,1,'Glow'),
('BC-010','Cepillo desenrredante','Beauty Care','Cuidado capilar','Akarella cosmeticos',5400.0,8000.0,2,1,'Glow'),
('BC-011','Desmaquillador bifasico','Beauty Care','Skincare de marca','Vive beauty',30900.0,36000.0,2,1,'Glow'),
('BC-012','Bloom Jelly primer','Beauty Care','Skincare de marca','Bloomshell',25900.0,33000.0,2,1,'Glow'),
('BC-013','Bloom fix fijador','Beauty Care','Maquillaje de marca','Bloomshell',0,0,2,1,'Glow'),
('BC-014','Lip gloss show your joy 03','Beauty Care','Maquillaje de marca','SAS',6100.0,10000.0,2,1,'Glow'),
('BC-015','Lip gloss show your joy 09','Beauty Care','Maquillaje de marca','SAS',6100.0,10000.0,2,1,'Glow'),
('BC-016','Rubor liquido tono 01 cupido','Beauty Care','Maquillaje de marca','Bloomshell',15400.0,22000.0,2,1,'Glow'),
('BC-017','Pestaniña','Beauty Care','Maquillaje de marca','Star charming',12900.0,17500.0,2,1,'Glow'),
('BC-018','Iluminador liquido tono 05','Beauty Care','Maquillaje de marca','Ushas',6400.0,8700.0,2,1,'Glow'),
('BC-019','Fijador de cejas Bloom','Beauty Care','Maquillaje de marca','Bloomshell',11100.0,18000.0,2,1,'Glow'),
('BC-020','Iluminador en pomo tono 02','Beauty Care','Maquillaje de marca','Ushas',11900.0,16700.0,2,1,'Glow'),
('BC-021','Purpure glossy tomo 02','Beauty Care','Maquillaje de marca','Purpure',15400.0,19900.0,2,1,'Glow'),
('BC-022','Purpure glossy tono 01','Beauty Care','Maquillaje de marca','Purpure',15400.0,19900.0,2,1,'Glow'),
('BC-023','Gorro de satin','Beauty Care','Cuidado capilar','Glow',7900.0,12000.0,2,1,'Glow'),
('BC-024','Moña de satin','Beauty Care','Cuidado capilar','Glow',4700.0,6345.0,2,1,'Glow'),
('BC-025','Rubor en barra 03','Beauty Care','Maquillaje de marca','SAS',7400.0,12000.0,2,1,'Glow'),
('BC-026','Tinta tono 01','Beauty Care','Maquillaje de marca','Ushas',4900.0,6700.0,2,1,'Glow'),
('BC-027','Tinta tono 03','Beauty Care','Maquillaje de marca','Ushas',4900.0,6700.0,2,1,'Glow'),
('BC-028','Bloom tinta aqua','Beauty Care','Maquillaje de marca','Bloomshell',10900.0,15000.0,2,1,'Glow'),
('BC-029','Gel oil cocoa','Beauty Care','Cuidado corporal','Vaseline',60900.0,66000.0,1,1,'Glow'),
('BC-030','Brocha para cejas','Beauty Care','Maquillaje de marca','Glow',5400.0,6000.0,1,1,'Glow'),
('BC-031','Mantequilla corporal','Beauty Care','Cuidado corporal','Vive beauty',20400.0,26000.0,2,5,'Mundo para ellas'),
('BC-032','Exfoliante corporal','Beauty Care','Cuidado corporal','Vive beauty',20400.0,26000.0,2,1,'Mundo para ellas'),
('BC-033','Mini kit centella','Beauty Care','Skincare de marca','Centella',120400.0,149000.0,1,1,'Glow'),
('BC-034','Corrector 10ml IVORY 04','Beauty Care','Maquillaje de marca','Bloomshell',15800.0,25000.0,2,1,'Mundo para ellas'),
('BC-035','Corrector 10ml  LIGHT 00','Beauty Care','Maquillaje de marca','Bloomshell',15800.0,25000.0,2,1,'Mundo para ellas'),
('BC-036','Corrector 10ml  NATURAL 01','Beauty Care','Maquillaje de marca','Bloomshell',15800.0,25000.0,2,1,'Mundo para ellas'),
('BC-037','Lip line RED','Beauty Care','Maquillaje de marca',null,11400.0,14000.0,1,1,'Mundo para ellas'),
('BC-038','Lip liner LOVER','Beauty Care','Maquillaje de marca',null,11400.0,14000.0,1,1,'Mundo para ellas'),
('BC-039','Lip liner MAROON','Beauty Care','Maquillaje de marca',null,11400.0,14000.0,1,1,'Mundo para ellas'),
('BC-040','Rayitos de sol','Beauty Care','Cuidado corporal','Rayitos de sol',12200.0,16000.0,2,2,'Mundo para ellas'),
('BC-041','Color de verano','Beauty Care','Cuidado corporal','Lampiña',9800.0,14000.0,2,2,'Mundo para ellas'),
('BC-042','Kit cartuchera','Beauty Care','Cuidado corporal','Purpure',29900.0,39900.0,2,2,'Mundo para ellas'),
('BC-043','Lip duo tono SANGRIA','Beauty Care','Maquillaje de marca','Destiny',34400.0,45000.0,2,1,'Mundo para ellas'),
('BC-044','Lip gloss tono HONEY','Beauty Care','Maquillaje de marca','Destiny',23400.0,30000.0,2,1,'Mundo para ellas'),
('BC-045','Lip gloss tono FONDUE','Beauty Care','Maquillaje de marca','Destiny',23400.0,30000.0,2,1,'Mundo para ellas'),
('BC-046','Polvo compacto 03','Beauty Care','Maquillaje de marca','Ushas',9900.0,13365.0,2,1,'Glow'),
('BC-047','Gacho flor x2','Beauty Care','Cuidado capilar','Engol',5400.0,6000.0,2,4,'Glow'),
('BC-048','Gacho flor x4','Beauty Care','Cuidado capilar','Engol',4400.0,6000.0,2,1,'Glow'),
('BC-049','Gacho flor x3','Beauty Care','Cuidado capilar','Engol',4400.0,6000.0,2,1,'Glow'),
('BC-050','Papelitos de arroz','Beauty Care','Skincare de marca','Karite',1900.0,2500.0,2,1,'Mundo para ellas'),
('BC-051','Mascarilla coreana hidrogel','Beauty Care','Skincare de marca','Koec',10900.0,16000.0,2,4,'Mundo para ellas'),
('BC-052','Mascarillas en velo','Beauty Care','Skincare de marca','Bioaqua',1850.0,2500.0,2,5,'Mundo para ellas'),
('BC-053','Brillo llavero','Beauty Care','Maquillaje de marca','New',8700.0,12000.0,2,2,'Antoninas'),
('BC-054','Mini mantequilla mundo vilandia','Beauty Care','Cuidado corporal','Vidan dreams',12900.0,18000.0,2,2,'Antoninas'),
('BC-055','Crema shimmer vilandia','Beauty Care','Cuidado corporal','Vidan dreams',17400.0,26000.0,2,1,'Antoninas'),
('BC-056','Corazon virgen dorada','Beauty Care','Otros Beauty Care','Reina bella',7400.0,14000.0,1,1,'Reina bella'),
('BC-057','Choker de hojas','Beauty Care','Otros Beauty Care','Reina bella',8400.0,15000.0,2,2,'Reina bella'),
('BC-058','Candonga mediana','Beauty Care','Otros Beauty Care','Reina bella',5400.0,8000.0,2,2,'Reina bella'),
('BC-059','Candoga pequeña de hoja','Beauty Care','Otros Beauty Care','Reina bella',5400.0,8000.0,2,1,'Reina bella'),
('BC-060','Candonga mediana dorada','Beauty Care','Otros Beauty Care','Reina bella',5400.0,8000.0,2,1,'Reina bella'),
('BC-061','Manilla perlas rosa con blanco','Beauty Care','Otros Beauty Care','Reina bella',11900.0,15000.0,2,1,'Reina bella'),
('BC-062','Manilla sencilla','Beauty Care','Otros Beauty Care','Reina bella',8900.0,12500.0,2,2,'Reina bella'),
('BC-063','Manilla flor con diamante verde','Beauty Care','Otros Beauty Care','Reina bella',9900.0,14000.0,2,1,'Reina bella'),
('BC-064','Anillo corazon','Beauty Care','Otros Beauty Care','Reina bella',5400.0,8000.0,2,1,'Reina bella'),
('BC-065','Anillo flores','Beauty Care','Otros Beauty Care','Mundo para ellas',5400.0,8000.0,2,1,'Mundo para ellas'),
('BC-066','Ear cuff','Beauty Care','Otros Beauty Care','Reina bella',5900.0,8260.0,2,6,'Reina bella'),
('BC-067','Agua de rosas','Beauty Care',null,'Vive beauty',10400.0,12000.0,2,1,'Mundo para ellas'),
('BC-068','Lapiz de cejas','Beauty Care',null,'Bloomshell',6100.0,11000.0,2,2,'Glow'),
('BC-069','Delineador de ojo','Beauty Care',null,'Bloomshell',6400.0,12000.0,2,1,'Glow'),
('BC-070','Contorno Tono 03','Beauty Care',null,'Bloomshell',22900.0,28000.0,0,1,'Glow'),
('BC-071','Set de brochas','Beauty Care',null,'Bloomshell',23400.0,26500.0,0,1,'Glow'),
('BC-072','Voluminizador','Beauty Care',null,'Vogue',15400.0,21560.0,0,1,'Mundo para ellas'),
('BC-073','Mascarilla de labios','Beauty Care',null,'Sammy',24200.0,29900.0,0,1,'Mundo para ellas'),
('BC-074','Delineador de ojo','Beauty Care',null,'Vogue',19900.0,25000.0,0,0,'Mundo para ellas'),
('ST-001','Aretes dorados pequeños','Style','Aretes','Marca E',5000.0,9000.0,5,15,'Proveedor 5'),
('ST-002','Manilla ajustable','Style','Manillas','Marca F',6700.0,11725.0,4,6,'Proveedor 6'),
('ST-003','Blusa básica','Style','Ropa de marca','Marca G',30000.0,44900.0,2,3,'Proveedor 7'),
('ST-004','Moña satinada','Style','Moñas','Marca H',3400.0,6460.0,4,4,'Proveedor 8');

-- Actualiza productos existentes por SKU.
update public.products p
set name=s.name,
    business_line=s.business_line,
    category=s.category,
    brand=s.brand,
    current_cost=nullif(s.current_cost,0),
    sale_price=s.sale_price,
    minimum_stock=s.minimum_stock,
    updated_at=now(),
    updated_by=(select id from public.profiles where active=true and role='cofundadora' order by created_at limit 1)
from _lihen_seed_inventory s
where lower(trim(p.sku))=lower(trim(s.sku));

-- Crea los productos que aún no existen.
insert into public.products (
 sku,name,business_line,category,brand,current_cost,sale_price,minimum_stock,
 status,visible_on_website,description,created_by,updated_by
)
select s.sku,s.name,s.business_line,s.category,s.brand,nullif(s.current_cost,0),s.sale_price,s.minimum_stock,
       'activo',false,
       concat(s.name,'. Consulta disponibilidad por WhatsApp.'),
       owner.id,owner.id
from _lihen_seed_inventory s
cross join lateral (
 select id from public.profiles where active=true and role='cofundadora' order by created_at limit 1
) owner
where not exists (
 select 1 from public.products p where lower(trim(p.sku))=lower(trim(s.sku))
);

-- Actualiza inventario existente e inserta el faltante.
update public.inventory i
set physical_stock=s.physical_stock,
    updated_at=now(),
    updated_by=(select id from public.profiles where active=true and role='cofundadora' order by created_at limit 1)
from public.products p
join _lihen_seed_inventory s on lower(trim(p.sku))=lower(trim(s.sku))
where i.product_id=p.id;

insert into public.inventory (product_id,physical_stock,updated_by)
select p.id,s.physical_stock,owner.id
from _lihen_seed_inventory s
join public.products p on lower(trim(p.sku))=lower(trim(s.sku))
cross join lateral (
 select id from public.profiles where active=true and role='cofundadora' order by created_at limit 1
) owner
where not exists (select 1 from public.inventory i where i.product_id=p.id);

insert into public.import_batches (
 import_type,source_file,status,total_rows,created_rows,updated_rows,summary,created_by
)
select 'inventario','Inventario_LIHEN_Corregido_Final.xlsx','completado',
       count(*),0,count(*),
       jsonb_build_object('tipo','carga inicial SQL','unidades_fisicas',sum(physical_stock)),
       (select id from public.profiles where active=true and role='cofundadora' order by created_at limit 1)
from _lihen_seed_inventory;

commit;
