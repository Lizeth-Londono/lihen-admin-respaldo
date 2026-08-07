-- ============================================================
-- LIHEN ADMIN PRO — MIGRACIÓN CONSOLIDADA DE AMPLIACIÓN
-- Compras a proveedores, caja y cuentas, importación segura,
-- seguridad, modelo de datos, idempotencia e integración financiera.
--
-- REQUISITO: el esquema base LIHEN (migraciones 001–013) debe existir.
-- EJECUCIÓN: copiar TODO este archivo en Supabase SQL Editor y ejecutar
-- una sola vez. Cada bloque conserva su propia transacción e idempotencia.
--
-- NO crea saldos iniciales, compras, pagos ni movimientos ficticios.
-- Al finalizar ejecutar:
--   select public.validate_lihen_schema_coherence();
-- ============================================================


-- ============================================================
-- INICIO BLOQUE: 022_importacion_inventario_transaccional_fase_18.sql
-- ============================================================
-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 022
-- Fase 18: importación de inventario segura, atómica e idempotente
-- Ejecutar después de las migraciones 006 y 007.
-- ============================================================
begin;

alter table public.import_batches
  add column if not exists operation_key text;

create unique index if not exists import_batches_operation_key_unique
  on public.import_batches(operation_key)
  where operation_key is not null and trim(operation_key) <> '';

create table if not exists public.import_batch_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.import_batches(id) on delete cascade,
  row_number integer,
  product_id uuid references public.products(id),
  sku text,
  action text not null check (action in ('crear','actualizar','sin_cambios','error')),
  status text not null default 'aplicado' check (status in ('aplicado','omitido','error')),
  changes jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists import_batch_rows_batch_idx on public.import_batch_rows(batch_id);
create index if not exists import_batch_rows_product_idx on public.import_batch_rows(product_id);

alter table public.import_batch_rows enable row level security;
drop policy if exists "cofundadoras_consultan_filas_importacion" on public.import_batch_rows;
create policy "cofundadoras_consultan_filas_importacion"
on public.import_batch_rows for select to authenticated
using (public.is_active_cofounder());

grant select on public.import_batch_rows to authenticated;

create or replace function public.import_inventory_batch_atomic(
  p_source_file text,
  p_operation_key text,
  p_total_rows integer,
  p_unchanged_rows integer,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_batch public.import_batches;
  v_existing public.import_batches;
  v_row jsonb;
  v_product public.products;
  v_inventory public.inventory;
  v_supplier public.suppliers;
  v_before_stock integer;
  v_after_stock integer;
  v_created integer := 0;
  v_updated integer := 0;
  v_pending_supplier integer := 0;
  v_stock_changes integer := 0;
  v_stock_units_after bigint := 0;
  v_action text;
  v_changes jsonb;
  v_product_id uuid;
  v_sku text;
  v_status text;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;
  if coalesce(trim(p_operation_key),'') = '' then
    raise exception 'La clave de operación es obligatoria';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Las filas de importación no son válidas';
  end if;

  select * into v_existing
  from public.import_batches
  where operation_key = p_operation_key
  limit 1;

  if found then
    if v_existing.status = 'completado' then
      return jsonb_build_object(
        'batch_id', v_existing.id,
        'idempotent', true,
        'summary', v_existing.summary
      );
    end if;
    raise exception 'Ya existe una importación con esta clave y estado %', v_existing.status;
  end if;

  insert into public.import_batches(
    import_type, source_file, operation_key, status, total_rows,
    skipped_rows, created_by, summary
  ) values (
    'inventario', p_source_file, p_operation_key, 'procesando', greatest(coalesce(p_total_rows,0),0),
    greatest(coalesce(p_unchanged_rows,0),0), v_user_id,
    jsonb_build_object('started_at', now())
  ) returning * into v_batch;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_action := v_row->>'action';
    v_product_id := nullif(v_row->>'product_id','')::uuid;
    v_sku := nullif(trim(v_row->>'sku'),'');
    v_changes := '{}'::jsonb;

    if v_action not in ('create','update') then
      raise exception 'Acción inválida en fila %', v_row->>'row_number';
    end if;

    if v_action = 'update' then
      select * into v_product from public.products where id = v_product_id for update;
      if not found then raise exception 'Producto no encontrado en fila %', v_row->>'row_number'; end if;

      update public.products set
        sku = case when v_row ? 'sku' and v_row->'sku' <> 'null'::jsonb then v_sku else sku end,
        business_line = case when v_row ? 'business_line' and v_row->'business_line' <> 'null'::jsonb then v_row->>'business_line' else business_line end,
        category = case when v_row ? 'category' then nullif(v_row->>'category','') else category end,
        subcategory = case when v_row ? 'subcategory' then nullif(v_row->>'subcategory','') else subcategory end,
        name = case when v_row ? 'name' and v_row->'name' <> 'null'::jsonb then v_row->>'name' else name end,
        brand = case when v_row ? 'brand' then nullif(v_row->>'brand','') else brand end,
        description = case when v_row ? 'description' then nullif(v_row->>'description','') else description end,
        current_cost = case when v_row ? 'current_cost' and v_row->'current_cost' <> 'null'::jsonb then (v_row->>'current_cost')::numeric else current_cost end,
        sale_price = case when v_row ? 'sale_price' and v_row->'sale_price' <> 'null'::jsonb then (v_row->>'sale_price')::numeric else sale_price end,
        minimum_stock = case when v_row ? 'minimum_stock' and v_row->'minimum_stock' <> 'null'::jsonb then (v_row->>'minimum_stock')::integer else minimum_stock end,
        visible_on_website = case when v_row ? 'visible_on_website' and v_row->'visible_on_website' <> 'null'::jsonb then (v_row->>'visible_on_website')::boolean else visible_on_website end,
        status = case when v_row ? 'status' and v_row->'status' <> 'null'::jsonb then (v_row->>'status')::public.product_status else status end,
        catalog_code = case when v_row ? 'catalog_code' then nullif(v_row->>'catalog_code','') else catalog_code end,
        updated_by = v_user_id,
        updated_at = now()
      where id = v_product.id
      returning * into v_product;
      v_updated := v_updated + 1;
    else
      if v_sku is null then raise exception 'SKU obligatorio en fila %', v_row->>'row_number'; end if;
      if nullif(trim(v_row->>'name'),'') is null then raise exception 'Nombre obligatorio en fila %', v_row->>'row_number'; end if;
      insert into public.products(
        sku,name,business_line,category,subcategory,brand,description,current_cost,sale_price,
        minimum_stock,visible_on_website,status,catalog_code,created_by,updated_by
      ) values (
        v_sku,v_row->>'name',coalesce(nullif(v_row->>'business_line',''),'Beauty Care'),
        nullif(v_row->>'category',''),nullif(v_row->>'subcategory',''),nullif(v_row->>'brand',''),
        coalesce(nullif(v_row->>'description',''),(v_row->>'name')||'. Consulta disponibilidad por WhatsApp.'),
        nullif(v_row->>'current_cost','')::numeric,coalesce(nullif(v_row->>'sale_price','')::numeric,0),
        coalesce(nullif(v_row->>'minimum_stock','')::integer,0),
        coalesce(nullif(v_row->>'visible_on_website','')::boolean,false),
        coalesce(nullif(v_row->>'status','')::public.product_status,'activo'::public.product_status),
        nullif(v_row->>'catalog_code',''),v_user_id,v_user_id
      ) returning * into v_product;
      v_created := v_created + 1;
    end if;

    if v_row ? 'physical_stock' and v_row->'physical_stock' <> 'null'::jsonb then
      v_after_stock := (v_row->>'physical_stock')::integer;
      if v_after_stock < 0 then raise exception 'Stock negativo en fila %', v_row->>'row_number'; end if;
      select * into v_inventory from public.inventory
      where product_id = v_product.id and variant_id is null for update;
      if found then
        v_before_stock := v_inventory.physical_stock;
        if v_after_stock < v_inventory.reserved_stock then
          raise exception 'El stock de % no puede ser menor al reservado', v_product.sku;
        end if;
        update public.inventory set physical_stock=v_after_stock,last_counted_at=now(),updated_by=v_user_id
        where id=v_inventory.id returning * into v_inventory;
      else
        v_before_stock := 0;
        insert into public.inventory(product_id,physical_stock,reserved_stock,pending_stock,average_cost,last_counted_at,updated_by)
        values(v_product.id,v_after_stock,0,0,coalesce(v_product.current_cost,0),now(),v_user_id)
        returning * into v_inventory;
      end if;
      if v_before_stock <> v_after_stock then
        insert into public.inventory_movements(
          inventory_id,movement_type,quantity,physical_before,physical_after,
          reserved_before,reserved_after,reason,performed_by
        ) values (
          v_inventory.id,
          case when v_after_stock>v_before_stock then 'ajuste_positivo'::public.inventory_movement_type else 'ajuste_negativo'::public.inventory_movement_type end,
          abs(v_after_stock-v_before_stock),v_before_stock,v_after_stock,
          v_inventory.reserved_stock,v_inventory.reserved_stock,
          'Importación de inventario: '||coalesce(p_source_file,'archivo'),v_user_id
        );
        v_stock_changes := v_stock_changes + 1;
      end if;
      v_stock_units_after := v_stock_units_after + v_after_stock;
    end if;

    if nullif(trim(v_row->>'supplier_name'),'') is not null then
      select * into v_supplier from public.suppliers
      where lower(trim(business_name))=lower(trim(v_row->>'supplier_name')) and active=true limit 1;
      if found then
        if exists (
          select 1 from public.supplier_products
          where supplier_id=v_supplier.id and product_id=v_product.id
        ) then
          update public.supplier_products
          set preferred=true,last_cost=coalesce(v_product.current_cost,last_cost)
          where supplier_id=v_supplier.id and product_id=v_product.id;
        else
          insert into public.supplier_products(supplier_id,product_id,last_cost,preferred)
          values(v_supplier.id,v_product.id,v_product.current_cost,true);
        end if;
      else
        v_pending_supplier := v_pending_supplier + 1;
      end if;
    end if;

    insert into public.import_batch_rows(batch_id,row_number,product_id,sku,action,status,changes)
    values(v_batch.id,nullif(v_row->>'row_number','')::integer,v_product.id,v_product.sku,
      case when v_action='create' then 'crear' else 'actualizar' end,'aplicado',v_changes);
  end loop;

  update public.import_batches set
    status='completado',created_rows=v_created,updated_rows=v_updated,
    skipped_rows=greatest(coalesce(p_unchanged_rows,0),0),error_rows=0,
    summary=jsonb_build_object(
      'created_rows',v_created,'updated_rows',v_updated,
      'unchanged_rows',greatest(coalesce(p_unchanged_rows,0),0),
      'stock_changes',v_stock_changes,'stock_units_after',v_stock_units_after,
      'pending_supplier_links',v_pending_supplier,'completed_at',now()
    )
  where id=v_batch.id returning * into v_batch;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(v_user_id,'importar_inventario_transaccional','import_batches',v_batch.id::text,
    v_batch.summary,jsonb_build_object('source_file',p_source_file,'operation_key',p_operation_key));

  return jsonb_build_object('batch_id',v_batch.id,'idempotent',false,'summary',v_batch.summary);
end;
$$;

revoke all on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb) from public;
grant execute on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb) to authenticated;

commit;

-- ============================================================
-- FIN BLOQUE: 022_importacion_inventario_transaccional_fase_18.sql
-- ============================================================

-- ============================================================
-- INICIO BLOQUE: 023_seguridad_supabase_fase_19.sql
-- ============================================================
-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 023
-- Fase 19: endurecimiento de seguridad, permisos, restricciones,
-- índices y RLS para las importaciones de inventario.
--
-- Ejecutar después de 022_importacion_inventario_transaccional_fase_18.sql.
-- Esta migración es defensiva e idempotente.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. RLS obligatorio
-- ------------------------------------------------------------
alter table public.import_batches enable row level security;
alter table public.import_batch_rows enable row level security;

-- Impide que el propietario de la tabla omita RLS accidentalmente desde
-- consultas normales. Las funciones SECURITY DEFINER siguen siendo el
-- único canal de escritura autorizado.
alter table public.import_batches force row level security;
alter table public.import_batch_rows force row level security;

-- ------------------------------------------------------------
-- 2. Políticas de lectura explícitas
-- ------------------------------------------------------------
drop policy if exists "cofundadoras_consultan_importaciones" on public.import_batches;
create policy "cofundadoras_consultan_importaciones"
on public.import_batches
for select
to authenticated
using (public.is_active_cofounder());

drop policy if exists "cofundadoras_consultan_filas_importacion" on public.import_batch_rows;
create policy "cofundadoras_consultan_filas_importacion"
on public.import_batch_rows
for select
to authenticated
using (public.is_active_cofounder());

-- Elimina políticas de escritura directa heredadas. La escritura debe pasar
-- exclusivamente por import_inventory_batch_atomic().
drop policy if exists "cofundadoras_crean_importaciones" on public.import_batches;
drop policy if exists "cofundadoras_insertan_filas_importacion" on public.import_batch_rows;
drop policy if exists "cofundadoras_actualizan_filas_importacion" on public.import_batch_rows;
drop policy if exists "cofundadoras_eliminan_filas_importacion" on public.import_batch_rows;

-- ------------------------------------------------------------
-- 3. Principio de mínimo privilegio
-- ------------------------------------------------------------
revoke all on public.import_batches from anon;
revoke all on public.import_batch_rows from anon;

revoke insert, update, delete, truncate, references, trigger
  on public.import_batches from authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.import_batch_rows from authenticated;

grant select on public.import_batches to authenticated;
grant select on public.import_batch_rows to authenticated;

-- La función atómica es el único punto de escritura público.
revoke all on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
  from public, anon;
grant execute on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
  to authenticated;

-- ------------------------------------------------------------
-- 4. Restricciones de integridad
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batches_counts_nonnegative'
      and conrelid = 'public.import_batches'::regclass
  ) then
    alter table public.import_batches
      add constraint import_batches_counts_nonnegative check (
        total_rows >= 0 and created_rows >= 0 and updated_rows >= 0
        and skipped_rows >= 0 and error_rows >= 0
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batches_status_allowed'
      and conrelid = 'public.import_batches'::regclass
  ) then
    alter table public.import_batches
      add constraint import_batches_status_allowed check (
        status in ('procesando','completado','fallido')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batches_operation_key_length'
      and conrelid = 'public.import_batches'::regclass
  ) then
    alter table public.import_batches
      add constraint import_batches_operation_key_length check (
        operation_key is null or char_length(operation_key) between 8 and 200
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batches_source_file_length'
      and conrelid = 'public.import_batches'::regclass
  ) then
    alter table public.import_batches
      add constraint import_batches_source_file_length check (
        source_file is null or char_length(source_file) <= 255
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batches_summary_object'
      and conrelid = 'public.import_batches'::regclass
  ) then
    alter table public.import_batches
      add constraint import_batches_summary_object check (
        jsonb_typeof(summary) = 'object'
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batch_rows_row_number_positive'
      and conrelid = 'public.import_batch_rows'::regclass
  ) then
    alter table public.import_batch_rows
      add constraint import_batch_rows_row_number_positive check (
        row_number is null or row_number > 0
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batch_rows_sku_length'
      and conrelid = 'public.import_batch_rows'::regclass
  ) then
    alter table public.import_batch_rows
      add constraint import_batch_rows_sku_length check (
        sku is null or char_length(trim(sku)) between 1 and 100
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batch_rows_changes_object'
      and conrelid = 'public.import_batch_rows'::regclass
  ) then
    alter table public.import_batch_rows
      add constraint import_batch_rows_changes_object check (
        jsonb_typeof(changes) = 'object'
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'import_batch_rows_error_consistency'
      and conrelid = 'public.import_batch_rows'::regclass
  ) then
    alter table public.import_batch_rows
      add constraint import_batch_rows_error_consistency check (
        (status = 'error' and nullif(trim(error_message), '') is not null)
        or (status <> 'error')
      ) not valid;
  end if;
end;
$$;

-- Las restricciones NOT VALID protegen filas nuevas sin bloquear la
-- migración por datos históricos. Se validan las que no dependen de legado
-- potencialmente inconsistente.
alter table public.import_batches validate constraint import_batches_counts_nonnegative;
alter table public.import_batches validate constraint import_batches_summary_object;
alter table public.import_batch_rows validate constraint import_batch_rows_row_number_positive;
alter table public.import_batch_rows validate constraint import_batch_rows_changes_object;

-- ------------------------------------------------------------
-- 5. Índices de consulta y unicidad
-- ------------------------------------------------------------
create unique index if not exists import_batch_rows_batch_row_unique
  on public.import_batch_rows(batch_id, row_number)
  where row_number is not null;

create index if not exists import_batches_created_at_idx
  on public.import_batches(created_at desc);

create index if not exists import_batches_created_by_created_at_idx
  on public.import_batches(created_by, created_at desc);

create index if not exists import_batches_status_created_at_idx
  on public.import_batches(status, created_at desc);

create index if not exists import_batch_rows_batch_status_idx
  on public.import_batch_rows(batch_id, status);

create index if not exists import_batch_rows_sku_normalized_idx
  on public.import_batch_rows(lower(trim(sku)))
  where sku is not null and trim(sku) <> '';

-- ------------------------------------------------------------
-- 6. Endurecimiento de la función RPC
-- ------------------------------------------------------------
-- search_path vacío evita secuestro de objetos por resolución de nombres.
alter function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
  set search_path = '';

-- Limita una ejecución accidentalmente larga sin afectar otras sesiones.
alter function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
  set statement_timeout = '120s';

-- ------------------------------------------------------------
-- 7. Validador previo reutilizable
-- ------------------------------------------------------------
create or replace function public.validate_inventory_import_request(
  p_source_file text,
  p_operation_key text,
  p_total_rows integer,
  p_unchanged_rows integer,
  p_rows jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actionable_count integer;
  v_row jsonb;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado' using errcode = '42501';
  end if;

  if coalesce(trim(p_operation_key), '') = ''
     or char_length(p_operation_key) < 8
     or char_length(p_operation_key) > 200 then
    raise exception 'La clave de operación debe tener entre 8 y 200 caracteres';
  end if;

  if p_source_file is not null and char_length(p_source_file) > 255 then
    raise exception 'El nombre del archivo supera 255 caracteres';
  end if;

  if coalesce(p_total_rows, -1) < 0 or coalesce(p_total_rows, 0) > 10000 then
    raise exception 'El total de filas debe estar entre 0 y 10000';
  end if;

  if coalesce(p_unchanged_rows, -1) < 0
     or p_unchanged_rows > p_total_rows then
    raise exception 'La cantidad de filas sin cambios no es válida';
  end if;

  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Las filas de importación deben ser un arreglo JSON';
  end if;

  v_actionable_count := jsonb_array_length(p_rows);
  if v_actionable_count + p_unchanged_rows > p_total_rows then
    raise exception 'El resumen de filas no coincide con el lote recibido';
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    if jsonb_typeof(v_row) <> 'object' then
      raise exception 'Cada fila debe ser un objeto JSON';
    end if;

    if coalesce(v_row->>'action', '') not in ('create','update') then
      raise exception 'Acción de importación no permitida';
    end if;

    if nullif(v_row->>'row_number', '') is null
       or (v_row->>'row_number')::integer <= 0 then
      raise exception 'Cada fila debe incluir un número de fila positivo';
    end if;

    if v_row->>'action' = 'update'
       and nullif(v_row->>'product_id', '') is null then
      raise exception 'Las actualizaciones deben incluir product_id';
    end if;

    if v_row->>'action' = 'create'
       and (nullif(trim(v_row->>'sku'), '') is null
            or nullif(trim(v_row->>'name'), '') is null) then
      raise exception 'Los productos nuevos requieren SKU y nombre';
    end if;
  end loop;
end;
$$;

revoke all on function public.validate_inventory_import_request(text,text,integer,integer,jsonb)
  from public, anon;
grant execute on function public.validate_inventory_import_request(text,text,integer,integer,jsonb)
  to authenticated;

-- ------------------------------------------------------------
-- 8. Comentarios operativos
-- ------------------------------------------------------------
comment on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
is 'Único canal autorizado para aplicar importaciones de inventario de forma atómica e idempotente.';

comment on function public.validate_inventory_import_request(text,text,integer,integer,jsonb)
is 'Valida identidad, tamaño y estructura de un lote antes de ejecutar la importación.';

comment on table public.import_batch_rows
is 'Trazabilidad por fila de cada importación; escritura exclusiva mediante RPC SECURITY DEFINER.';

commit;

-- ============================================================
-- FIN BLOQUE: 023_seguridad_supabase_fase_19.sql
-- ============================================================

-- ============================================================
-- INICIO BLOQUE: 024_modelo_datos_consolidado_fase_20.sql
-- ============================================================
-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 024
-- Fase 20: modelo de datos consolidado y extensible
--
-- Objetivo:
-- 1) adaptar el esquema existente sin duplicar supplier_requests;
-- 2) separar compra, recepción, pago, inventario y dinero;
-- 3) establecer relaciones, índices, restricciones y trazabilidad;
-- 4) preparar el esquema para las fases funcionales posteriores.
--
-- Ejecutar después de las migraciones base y de 023.
-- Migración defensiva e idempotente. No inserta saldos ni operaciones falsas.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Solicitudes existentes convertibles en compras de proveedor
-- ------------------------------------------------------------
alter table public.supplier_requests
  add column if not exists purchase_date date,
  add column if not exists invoice_number text,
  add column if not exists due_date date,
  add column if not exists receipt_status text not null default 'pendiente',
  add column if not exists payment_status text not null default 'pendiente',
  add column if not exists subtotal numeric(14,2) not null default 0,
  add column if not exists discount_amount numeric(14,2) not null default 0,
  add column if not exists tax_amount numeric(14,2) not null default 0,
  add column if not exists freight_amount numeric(14,2) not null default 0,
  add column if not exists total_amount numeric(14,2) not null default 0,
  add column if not exists amount_paid numeric(14,2) not null default 0,
  add column if not exists balance_due numeric(14,2) not null default 0,
  add column if not exists confirmed_at timestamptz,
  add column if not exists confirmed_by uuid references public.profiles(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references public.profiles(id),
  add column if not exists cancellation_reason text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.supplier_request_items
  add column if not exists line_subtotal numeric(14,2) not null default 0,
  add column if not exists quantity_cancelled integer not null default 0,
  add column if not exists updated_at timestamptz not null default now();

-- Restricciones nuevas como NOT VALID para tolerar datos históricos.
do $$
begin
  if not exists (select 1 from pg_constraint where conname='supplier_requests_amounts_nonnegative') then
    alter table public.supplier_requests add constraint supplier_requests_amounts_nonnegative check (
      subtotal >= 0 and discount_amount >= 0 and tax_amount >= 0 and freight_amount >= 0
      and total_amount >= 0 and amount_paid >= 0 and balance_due >= 0
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='supplier_requests_payment_status_allowed') then
    alter table public.supplier_requests add constraint supplier_requests_payment_status_allowed check (
      payment_status in ('pendiente','parcial','pagada','anulada')
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='supplier_requests_receipt_status_allowed') then
    alter table public.supplier_requests add constraint supplier_requests_receipt_status_allowed check (
      receipt_status in ('pendiente','parcial','completa','anulada')
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname='supplier_request_items_quantities_valid') then
    alter table public.supplier_request_items add constraint supplier_request_items_quantities_valid check (
      quantity_requested > 0 and quantity_received >= 0 and quantity_cancelled >= 0
      and quantity_received + quantity_cancelled <= quantity_requested
    ) not valid;
  end if;
end $$;

create index if not exists supplier_requests_supplier_purchase_date_idx
  on public.supplier_requests(supplier_id, purchase_date desc);
create index if not exists supplier_requests_payment_status_due_date_idx
  on public.supplier_requests(payment_status, due_date)
  where payment_status in ('pendiente','parcial');
create index if not exists supplier_requests_receipt_status_idx
  on public.supplier_requests(receipt_status);
create index if not exists supplier_request_items_request_product_idx
  on public.supplier_request_items(supplier_request_id, product_id);

-- ------------------------------------------------------------
-- 2. Recepciones: evento separado de la compra
-- ------------------------------------------------------------
create table if not exists public.supplier_purchase_receipts (
  id uuid primary key default gen_random_uuid(),
  supplier_request_id uuid not null references public.supplier_requests(id) on delete restrict,
  receipt_number text,
  received_at timestamptz not null default now(),
  notes text,
  operation_key text not null,
  status text not null default 'aplicada' check (status in ('aplicada','reversada')),
  created_by uuid not null references public.profiles(id),
  reversed_at timestamptz,
  reversed_by uuid references public.profiles(id),
  reversal_reason text,
  created_at timestamptz not null default now(),
  unique(operation_key)
);

create table if not exists public.supplier_purchase_receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.supplier_purchase_receipts(id) on delete cascade,
  supplier_request_item_id uuid not null references public.supplier_request_items(id) on delete restrict,
  inventory_id uuid not null references public.inventory(id) on delete restrict,
  quantity_received integer not null check (quantity_received > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  physical_before integer not null check (physical_before >= 0),
  physical_after integer not null check (physical_after >= 0),
  pending_before integer not null check (pending_before >= 0),
  pending_after integer not null check (pending_after >= 0),
  inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(receipt_id, supplier_request_item_id)
);

create index if not exists supplier_purchase_receipts_request_date_idx
  on public.supplier_purchase_receipts(supplier_request_id, received_at desc);
create index if not exists supplier_purchase_receipt_items_inventory_idx
  on public.supplier_purchase_receipt_items(inventory_id);

-- ------------------------------------------------------------
-- 3. Cuentas y movimientos financieros
-- ------------------------------------------------------------
create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_type text not null check (account_type in ('billetera_digital','efectivo','banco','otro')),
  currency_code text not null default 'COP' check (currency_code='COP'),
  initial_balance numeric(14,2) not null default 0 check (initial_balance >= 0),
  initial_balance_date date,
  current_balance numeric(14,2) not null default 0,
  initial_balance_configured boolean not null default false,
  active boolean not null default true,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.financial_movements (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  movement_type text not null check (movement_type in ('ingreso','egreso','ajuste_positivo','ajuste_negativo','transferencia_entrada','transferencia_salida','reversion')),
  category text not null,
  amount numeric(14,2) not null check (amount > 0),
  balance_before numeric(14,2) not null,
  balance_after numeric(14,2) not null,
  occurred_at timestamptz not null default now(),
  source_type text,
  source_id uuid,
  reference_number text,
  description text,
  operation_key text not null,
  transfer_group_id uuid,
  reversal_of_id uuid references public.financial_movements(id) on delete restrict,
  status text not null default 'activo' check (status in ('activo','reversado')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(operation_key)
);

create index if not exists financial_movements_account_date_idx
  on public.financial_movements(account_id, occurred_at desc);
create index if not exists financial_movements_source_idx
  on public.financial_movements(source_type, source_id);
create index if not exists financial_movements_transfer_group_idx
  on public.financial_movements(transfer_group_id)
  where transfer_group_id is not null;
create unique index if not exists financial_movements_one_active_source_unique
  on public.financial_movements(source_type, source_id, category)
  where source_id is not null and status='activo'
    and movement_type not in ('transferencia_entrada','transferencia_salida','reversion');

-- ------------------------------------------------------------
-- 4. Pagos a proveedores: evento financiero separado
-- ------------------------------------------------------------
create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_request_id uuid not null references public.supplier_requests(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  financial_movement_id uuid not null references public.financial_movements(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null,
  payment_date timestamptz not null default now(),
  reference_number text,
  notes text,
  operation_key text not null,
  status text not null default 'activo' check (status in ('activo','anulado')),
  created_by uuid not null references public.profiles(id),
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  cancellation_reason text,
  created_at timestamptz not null default now(),
  unique(operation_key),
  unique(financial_movement_id)
);

create index if not exists supplier_payments_request_date_idx
  on public.supplier_payments(supplier_request_id, payment_date desc);
create index if not exists supplier_payments_supplier_date_idx
  on public.supplier_payments(supplier_id, payment_date desc);
create index if not exists supplier_payments_account_date_idx
  on public.supplier_payments(financial_account_id, payment_date desc);

-- ------------------------------------------------------------
-- 5. Historial de costos de producto
-- ------------------------------------------------------------
create table if not exists public.product_cost_history (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  variant_id uuid,
  supplier_id uuid references public.suppliers(id) on delete set null,
  supplier_request_id uuid references public.supplier_requests(id) on delete set null,
  receipt_item_id uuid references public.supplier_purchase_receipt_items(id) on delete set null,
  previous_product_cost numeric(14,2),
  new_product_cost numeric(14,2) not null check (new_product_cost >= 0),
  previous_average_cost numeric(14,2),
  new_average_cost numeric(14,2) not null check (new_average_cost >= 0),
  purchased_unit_cost numeric(14,2) not null check (purchased_unit_cost >= 0),
  quantity_received integer not null check (quantity_received > 0),
  stock_before integer not null check (stock_before >= 0),
  stock_after integer not null check (stock_after >= 0),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(receipt_item_id)
);

create index if not exists product_cost_history_product_date_idx
  on public.product_cost_history(product_id, created_at desc);
create index if not exists product_cost_history_supplier_idx
  on public.product_cost_history(supplier_id, created_at desc)
  where supplier_id is not null;

-- ------------------------------------------------------------
-- 6. Historial de saldos iniciales
-- ------------------------------------------------------------
create table if not exists public.financial_initial_balance_history (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  change_type text not null check (change_type in ('configuracion','correccion')),
  previous_balance numeric(14,2),
  new_balance numeric(14,2) not null check (new_balance >= 0),
  previous_date date,
  new_date date not null,
  reason text not null check (char_length(trim(reason)) >= 8),
  changed_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists financial_initial_balance_history_account_idx
  on public.financial_initial_balance_history(account_id, created_at desc);

-- ------------------------------------------------------------
-- 7. RLS: lectura de cofundadoras; escritura solo por RPC/funciones
-- ------------------------------------------------------------
alter table public.supplier_purchase_receipts enable row level security;
alter table public.supplier_purchase_receipt_items enable row level security;
alter table public.financial_accounts enable row level security;
alter table public.financial_movements enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.product_cost_history enable row level security;
alter table public.financial_initial_balance_history enable row level security;

-- Políticas de lectura uniformes.
do $$
declare
  v_table text;
  v_policy text;
begin
  foreach v_table in array array[
    'supplier_purchase_receipts',
    'supplier_purchase_receipt_items',
    'financial_accounts',
    'financial_movements',
    'supplier_payments',
    'product_cost_history',
    'financial_initial_balance_history'
  ] loop
    v_policy := 'cofundadoras_consultan_' || v_table;
    execute format('drop policy if exists %I on public.%I', v_policy, v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_active_cofounder())',
      v_policy, v_table
    );
    execute format('revoke all on public.%I from anon', v_table);
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated', v_table);
    execute format('grant select on public.%I to authenticated', v_table);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 8. Vista técnica de relaciones principales
-- ------------------------------------------------------------
create or replace view public.v_supplier_purchase_account_status
with (security_invoker = true)
as
select
  sr.id as supplier_request_id,
  sr.supplier_id,
  sr.purchase_date,
  sr.status as purchase_status,
  sr.receipt_status,
  sr.payment_status,
  sr.total_amount,
  coalesce(sum(sp.amount) filter (where sp.status='activo'), 0)::numeric(14,2) as active_payments,
  greatest(sr.total_amount - coalesce(sum(sp.amount) filter (where sp.status='activo'), 0), 0)::numeric(14,2) as calculated_balance_due,
  max(sp.payment_date) filter (where sp.status='activo') as last_payment_at
from public.supplier_requests sr
left join public.supplier_payments sp on sp.supplier_request_id=sr.id
group by sr.id, sr.supplier_id, sr.purchase_date, sr.status, sr.receipt_status,
         sr.payment_status, sr.total_amount;

grant select on public.v_supplier_purchase_account_status to authenticated;

comment on table public.supplier_purchase_receipts is 'Recepciones físicas de mercancía, separadas de la compra y del pago.';
comment on table public.financial_accounts is 'Cuentas reales de LIHEN, como Nequi y efectivo físico.';
comment on table public.financial_movements is 'Libro de movimientos de dinero; no sustituye movimientos de inventario.';
comment on table public.supplier_payments is 'Pagos parciales o completos hechos a proveedores.';
comment on table public.product_cost_history is 'Historial inmutable de costos producido por recepciones de proveedor.';

commit;

-- ============================================================
-- FIN BLOQUE: 024_modelo_datos_consolidado_fase_20.sql
-- ============================================================

-- ============================================================
-- INICIO BLOQUE: 025_idempotencia_operaciones_fase_21.sql
-- ============================================================
-- ============================================================
-- LIHEN ADMIN — FASE 21
-- Idempotencia transversal para operaciones sensibles
-- ============================================================
-- Esta migración no reemplaza las restricciones únicas ya existentes.
-- Añade un registro central de ejecución y RPC idempotentes para los
-- flujos disponibles en el proyecto base.

begin;

create table if not exists public.operation_executions (
  id uuid primary key default gen_random_uuid(),
  operation_type text not null,
  operation_key text not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'procesando' check (status in ('procesando','completada','fallida')),
  request_fingerprint text,
  result jsonb,
  error_message text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(operation_type, operation_key)
);

create index if not exists operation_executions_actor_date_idx
  on public.operation_executions(actor_id, created_at desc);
create index if not exists operation_executions_status_date_idx
  on public.operation_executions(status, created_at desc);

alter table public.operation_executions enable row level security;
alter table public.operation_executions force row level security;

drop policy if exists "cofundadoras_consultan_operation_executions" on public.operation_executions;
create policy "cofundadoras_consultan_operation_executions"
on public.operation_executions for select to authenticated
using (public.is_active_cofounder());

revoke all on public.operation_executions from anon;
revoke insert, update, delete, truncate, references, trigger on public.operation_executions from authenticated;
grant select on public.operation_executions to authenticated;

create or replace function public.assert_operation_key(p_operation_key text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text := trim(coalesce(p_operation_key,''));
begin
  if char_length(v_key) < 12 or char_length(v_key) > 200 then
    raise exception 'La clave de operación debe tener entre 12 y 200 caracteres';
  end if;
  if v_key !~ '^[A-Za-z0-9:_-]+$' then
    raise exception 'La clave de operación contiene caracteres no permitidos';
  end if;
  return v_key;
end;
$$;

create or replace function public.begin_idempotent_operation(
  p_operation_type text,
  p_operation_key text,
  p_request_fingerprint text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_type text := trim(coalesce(p_operation_type,''));
  v_key text := public.assert_operation_key(p_operation_key);
  v_existing public.operation_executions;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if char_length(v_type) < 3 or char_length(v_type) > 80 then raise exception 'Tipo de operación inválido'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_type || ':' || v_key, 0));

  select * into v_existing
  from public.operation_executions
  where operation_type=v_type and operation_key=v_key
  for update;

  if found then
    if v_existing.actor_id <> v_user_id then
      raise exception 'La clave de operación ya pertenece a otro usuario';
    end if;
    if coalesce(v_existing.request_fingerprint,'') <> coalesce(p_request_fingerprint,'') then
      raise exception 'La clave de operación ya fue utilizada con datos diferentes';
    end if;
    return jsonb_build_object(
      'execution_id',v_existing.id,
      'existing',true,
      'status',v_existing.status,
      'result',v_existing.result
    );
  end if;

  insert into public.operation_executions(operation_type,operation_key,actor_id,request_fingerprint)
  values(v_type,v_key,v_user_id,p_request_fingerprint)
  returning * into v_existing;

  return jsonb_build_object('execution_id',v_existing.id,'existing',false,'status','procesando');
end;
$$;

create or replace function public.complete_idempotent_operation(
  p_execution_id uuid,
  p_result jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.operation_executions
  set status='completada', result=coalesce(p_result,'{}'::jsonb), error_message=null, completed_at=now()
  where id=p_execution_id and actor_id=auth.uid();
  if not found then raise exception 'Ejecución idempotente no encontrada'; end if;
end;
$$;

-- Pedido nuevo idempotente.
create or replace function public.create_order_atomic_idempotent(
  p_operation_key text,
  p_customer_id uuid,
  p_delivery_address_id uuid default null,
  p_payment_method text default 'sin_definir',
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_delivery_cost numeric default 0,
  p_discount_reason text default null,
  p_customer_notes text default null,
  p_internal_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_begin jsonb;
  v_execution_id uuid;
  v_order public.orders;
  v_fingerprint text;
begin
  v_fingerprint := md5(jsonb_build_object(
    'customer_id',p_customer_id,'delivery_address_id',p_delivery_address_id,
    'payment_method',p_payment_method,'discount_type',p_discount_type,
    'discount_value',p_discount_value,'delivery_cost',p_delivery_cost,
    'discount_reason',p_discount_reason,'customer_notes',p_customer_notes,
    'internal_notes',p_internal_notes,'items',p_items
  )::text);
  v_begin := public.begin_idempotent_operation('crear_pedido',p_operation_key,v_fingerprint);
  v_execution_id := (v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    select * into v_order from public.orders where id=(v_begin->'result'->>'order_id')::uuid;
    return v_order;
  end if;
  v_order := public.create_order_atomic(p_customer_id,p_delivery_address_id,p_payment_method,p_discount_type,p_discount_value,p_delivery_cost,p_discount_reason,p_customer_notes,p_internal_notes,p_items);
  perform public.complete_idempotent_operation(v_execution_id,jsonb_build_object('order_id',v_order.id));
  return v_order;
end;
$$;

-- Venta rápida idempotente.
create or replace function public.create_quick_sale_atomic_idempotent(
  p_operation_key text,
  p_customer_id uuid default null,
  p_payment_method text default 'efectivo',
  p_payment_reference text default null,
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_begin jsonb; v_execution_id uuid; v_result jsonb; v_fingerprint text; v_sale_id uuid;
begin
  v_fingerprint := md5(jsonb_build_object('customer_id',p_customer_id,'payment_method',p_payment_method,'payment_reference',p_payment_reference,'discount_type',p_discount_type,'discount_value',p_discount_value,'notes',p_notes,'items',p_items)::text);
  v_begin := public.begin_idempotent_operation('crear_venta_rapida',p_operation_key,v_fingerprint);
  v_execution_id := (v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    v_sale_id := (v_begin->'result'->>'sale_id')::uuid;
    return jsonb_build_object('sale',(select to_jsonb(s) from public.quick_sales s where s.id=v_sale_id),'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_sale_id),'idempotent',true);
  end if;
  v_result := public.create_quick_sale_atomic(p_customer_id,p_payment_method,p_payment_reference,p_discount_type,p_discount_value,p_notes,p_items);
  v_sale_id := (v_result->'sale'->>'id')::uuid;
  perform public.complete_idempotent_operation(v_execution_id,jsonb_build_object('sale_id',v_sale_id));
  return v_result || jsonb_build_object('idempotent',false);
end;
$$;

-- Anulación de venta rápida idempotente.
create or replace function public.cancel_quick_sale_atomic_idempotent(p_operation_key text,p_sale_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_begin jsonb; v_execution_id uuid; v_result jsonb; v_fingerprint text;
begin
  v_fingerprint:=md5(jsonb_build_object('sale_id',p_sale_id,'reason',p_reason)::text);
  v_begin:=public.begin_idempotent_operation('anular_venta_rapida',p_operation_key,v_fingerprint);
  v_execution_id:=(v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    return coalesce(v_begin->'result','{}'::jsonb)||jsonb_build_object('idempotent',true);
  end if;
  v_result:=public.cancel_quick_sale_atomic(p_sale_id,p_reason);
  perform public.complete_idempotent_operation(v_execution_id,v_result);
  return v_result||jsonb_build_object('idempotent',false);
end; $$;

-- Pago y entrega directa idempotente.
create or replace function public.close_order_direct_atomic_idempotent(
  p_operation_key text,p_order_id uuid,p_payment_method text,p_reason text,p_reference_number text default null,p_notes text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_begin jsonb; v_execution_id uuid; v_result jsonb; v_fingerprint text;
begin
  v_fingerprint:=md5(jsonb_build_object('order_id',p_order_id,'payment_method',p_payment_method,'reason',p_reason,'reference_number',p_reference_number,'notes',p_notes)::text);
  v_begin:=public.begin_idempotent_operation('cerrar_pedido_directo',p_operation_key,v_fingerprint);
  v_execution_id:=(v_begin->>'execution_id')::uuid;
  if (v_begin->>'existing')::boolean and v_begin->>'status'='completada' then
    return coalesce(v_begin->'result','{}'::jsonb)||jsonb_build_object('idempotent',true);
  end if;
  v_result:=public.close_order_direct_atomic(p_order_id,p_payment_method,p_reason,p_reference_number,p_notes);
  perform public.complete_idempotent_operation(v_execution_id,v_result);
  return v_result||jsonb_build_object('idempotent',false);
end; $$;

revoke all on function public.assert_operation_key(text) from public, anon, authenticated;
revoke all on function public.begin_idempotent_operation(text,text,text) from public, anon, authenticated;
revoke all on function public.complete_idempotent_operation(uuid,jsonb) from public, anon, authenticated;

revoke all on function public.create_order_atomic_idempotent(text,uuid,uuid,text,text,numeric,numeric,text,text,text,jsonb) from public, anon;
grant execute on function public.create_order_atomic_idempotent(text,uuid,uuid,text,text,numeric,numeric,text,text,text,jsonb) to authenticated;
revoke all on function public.create_quick_sale_atomic_idempotent(text,uuid,text,text,text,numeric,text,jsonb) from public, anon;
grant execute on function public.create_quick_sale_atomic_idempotent(text,uuid,text,text,text,numeric,text,jsonb) to authenticated;
revoke all on function public.cancel_quick_sale_atomic_idempotent(text,uuid,text) from public, anon;
grant execute on function public.cancel_quick_sale_atomic_idempotent(text,uuid,text) to authenticated;
revoke all on function public.close_order_direct_atomic_idempotent(text,uuid,text,text,text,text) from public, anon;
grant execute on function public.close_order_direct_atomic_idempotent(text,uuid,text,text,text,text) to authenticated;

comment on table public.operation_executions is 'Registro central de claves idempotentes para impedir que un reintento repita efectos de negocio.';

commit;

-- ============================================================
-- FIN BLOQUE: 025_idempotencia_operaciones_fase_21.sql
-- ============================================================

-- ============================================================
-- INICIO BLOQUE: 026_consolidacion_funcional_fases_2_15.sql
-- ============================================================
-- LIHEN ADMIN - Consolidación funcional real de fases 2 a 15
begin;

alter table if exists public.supplier_requests
  add column if not exists purchase_date date default current_date,
  add column if not exists invoice_number text,
  add column if not exists due_date date,
  add column if not exists reception_status text default 'pendiente',
  add column if not exists payment_status text default 'pendiente',
  add column if not exists subtotal numeric(14,2) default 0,
  add column if not exists discount_amount numeric(14,2) default 0,
  add column if not exists tax_amount numeric(14,2) default 0,
  add column if not exists freight_amount numeric(14,2) default 0,
  add column if not exists total_amount numeric(14,2) default 0,
  add column if not exists amount_paid numeric(14,2) default 0,
  add column if not exists balance_due numeric(14,2) default 0,
  add column if not exists operation_key text;

create unique index if not exists ux_supplier_requests_operation_key
  on public.supplier_requests(operation_key) where operation_key is not null;

create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_type text not null default 'otro' check (account_type in ('billetera_digital','efectivo','banco','otro')),
  currency_code text not null default 'COP' check (currency_code='COP'),
  initial_balance numeric(14,2) not null default 0 check (initial_balance >= 0),
  current_balance numeric(14,2) not null default 0,
  initial_balance_date date,
  initial_balance_configured boolean not null default false,
  active boolean not null default true,
  created_by uuid default auth.uid(),
  updated_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.financial_movements (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.financial_accounts(id) on delete restrict,
  movement_type text not null check (movement_type in ('saldo_inicial','ingreso','egreso','ajuste_positivo','ajuste_negativo','transferencia_entrada','transferencia_salida','reversion')),
  amount numeric(14,2) not null check (amount > 0),
  balance_before numeric(14,2) not null,
  balance_after numeric(14,2) not null,
  category text not null,
  description text,
  source_type text,
  source_id uuid,
  reference_number text,
  operation_key text not null unique,
  transfer_group_id uuid,
  reversal_of_id uuid references public.financial_movements(id) on delete restrict,
  status text not null default 'activo' check (status in ('activo','reversado')),
  occurred_at timestamptz not null default now(),
  performed_by uuid default auth.uid(),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_request_id uuid not null references public.supplier_requests(id) on delete restrict,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
  financial_movement_id uuid unique references public.financial_movements(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null,
  reference_number text,
  notes text,
  status text not null default 'activo' check (status in ('activo','anulado')),
  operation_key text not null unique,
  payment_date timestamptz not null default now(),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

insert into public.financial_accounts(code,name,account_type)
values ('nequi','Nequi','billetera_digital'),('efectivo','Efectivo físico','efectivo')
on conflict (code) do nothing;

create or replace function public.create_supplier_purchase_atomic(
  p_supplier_id uuid,
  p_purchase_date date,
  p_expected_date date,
  p_invoice_number text,
  p_due_date date,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_freight_amount numeric,
  p_notes text,
  p_items jsonb,
  p_operation_key text
) returns public.supplier_requests
language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid := auth.uid(); v_purchase public.supplier_requests; v_item jsonb;
  v_subtotal numeric(14,2) := 0; v_total numeric(14,2); v_qty int; v_cost numeric(14,2); v_product uuid;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if coalesce(length(trim(p_operation_key)),0) < 12 then raise exception 'Clave de operación inválida'; end if;
  select * into v_purchase from public.supplier_requests where operation_key=p_operation_key;
  if found then return v_purchase; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and active=true) then raise exception 'Proveedor no encontrado o inactivo'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'La compra debe incluir productos'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product=(v_item->>'product_id')::uuid; v_qty=(v_item->>'quantity_requested')::int; v_cost=(v_item->>'quoted_unit_cost')::numeric;
    if v_qty<=0 or v_cost<0 then raise exception 'Cantidad o costo inválido'; end if;
    if not exists(select 1 from public.products where id=v_product) then raise exception 'Producto no encontrado'; end if;
    v_subtotal := v_subtotal + v_qty*v_cost;
  end loop;
  v_total := greatest(0,v_subtotal-coalesce(p_discount_amount,0)+coalesce(p_tax_amount,0)+coalesce(p_freight_amount,0));
  insert into public.supplier_requests(supplier_id,status,purchase_date,expected_date,invoice_number,due_date,reception_status,payment_status,subtotal,discount_amount,tax_amount,freight_amount,total_amount,amount_paid,balance_due,notes,operation_key,created_by,updated_by)
  values(p_supplier_id,'borrador',coalesce(p_purchase_date,current_date),p_expected_date,nullif(trim(p_invoice_number),''),p_due_date,'pendiente','pendiente',v_subtotal,coalesce(p_discount_amount,0),coalesce(p_tax_amount,0),coalesce(p_freight_amount,0),v_total,0,v_total,p_notes,p_operation_key,v_user,v_user)
  returning * into v_purchase;
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into public.supplier_request_items(supplier_request_id,product_id,quantity_requested,quoted_unit_cost)
    values(v_purchase.id,(v_item->>'product_id')::uuid,(v_item->>'quantity_requested')::int,(v_item->>'quoted_unit_cost')::numeric);
  end loop;
  return v_purchase;
end $$;

create or replace function public.confirm_supplier_purchase_atomic(p_supplier_request_id uuid,p_operation_key text)
returns public.supplier_requests language plpgsql security definer set search_path=''
as $$ declare v public.supplier_requests; v_user uuid:=auth.uid(); begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  select * into v from public.supplier_requests where id=p_supplier_request_id for update;
  if not found then raise exception 'Compra no encontrada'; end if;
  if v.status<>'borrador' then return v; end if;
  update public.supplier_requests set status='confirmada',updated_by=v_user where id=v.id returning * into v;
  update public.inventory i set pending_stock=i.pending_stock+sri.quantity_requested,updated_by=v_user
  from public.supplier_request_items sri where sri.supplier_request_id=v.id and i.product_id=sri.product_id and i.variant_id is not distinct from sri.variant_id;
  return v;
end $$;

create or replace function public.configure_initial_balance_atomic(p_account_id uuid,p_amount numeric,p_effective_date date,p_reason text,p_operation_key text)
returns public.financial_accounts language plpgsql security definer set search_path=''
as $$ declare v public.financial_accounts; v_user uuid:=auth.uid(); begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 if p_amount<0 then raise exception 'Saldo inválido'; end if;
 select * into v from public.financial_accounts where id=p_account_id for update;
 if not found or not v.active then raise exception 'Cuenta no disponible'; end if;
 if v.initial_balance_configured then raise exception 'El saldo inicial ya fue configurado'; end if;
 update public.financial_accounts set initial_balance=p_amount,current_balance=p_amount,initial_balance_date=p_effective_date,initial_balance_configured=true,updated_by=v_user,updated_at=now() where id=v.id returning * into v;
 if p_amount>0 then insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,occurred_at) values(v.id,'saldo_inicial',p_amount,0,p_amount,'saldo_inicial',p_reason,p_operation_key,v_user,coalesce(p_effective_date,current_date)::timestamptz); end if;
 return v;
end $$;

create or replace function public.register_financial_movement_atomic(p_account_id uuid,p_movement_type text,p_amount numeric,p_category text,p_description text,p_occurred_at timestamptz,p_operation_key text)
returns public.financial_movements language plpgsql security definer set search_path=''
as $$ declare a public.financial_accounts; m public.financial_movements; delta numeric; begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 select * into m from public.financial_movements where operation_key=p_operation_key; if found then return m; end if;
 if p_amount<=0 then raise exception 'El valor debe ser mayor que cero'; end if;
 select * into a from public.financial_accounts where id=p_account_id for update;
 if not found or not a.active or not a.initial_balance_configured then raise exception 'Cuenta no disponible o sin saldo inicial'; end if;
 delta := case when p_movement_type in ('ingreso','ajuste_positivo') then p_amount when p_movement_type in ('egreso','ajuste_negativo') then -p_amount else null end;
 if delta is null then raise exception 'Tipo de movimiento no permitido'; end if;
 if a.current_balance+delta<0 then raise exception 'Saldo insuficiente'; end if;
 insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,occurred_at)
 values(a.id,p_movement_type,p_amount,a.current_balance,a.current_balance+delta,p_category,p_description,p_operation_key,auth.uid(),coalesce(p_occurred_at,now())) returning * into m;
 update public.financial_accounts set current_balance=m.balance_after,updated_by=auth.uid(),updated_at=now() where id=a.id;
 return m;
end $$;

create or replace function public.register_supplier_payment_atomic(p_supplier_request_id uuid,p_account_id uuid,p_amount numeric,p_payment_method text,p_paid_at timestamptz,p_reference_number text,p_notes text,p_operation_key text)
returns public.supplier_payments language plpgsql security definer set search_path=''
as $$ declare p public.supplier_requests; a public.financial_accounts; m public.financial_movements; result public.supplier_payments; new_paid numeric; begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 select * into result from public.supplier_payments where operation_key=p_operation_key; if found then return result; end if;
 select * into p from public.supplier_requests where id=p_supplier_request_id for update; if not found or p.status='cancelada' then raise exception 'Compra no disponible'; end if;
 if p_amount<=0 or p_amount>p.balance_due then raise exception 'Pago inválido o superior al saldo pendiente'; end if;
 select * into a from public.financial_accounts where id=p_account_id for update; if not found or a.current_balance<p_amount then raise exception 'Saldo insuficiente'; end if;
 insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,source_type,source_id,operation_key,performed_by,occurred_at)
 values(a.id,'egreso',p_amount,a.current_balance,a.current_balance-p_amount,'pago_proveedor','Pago a proveedor','supplier_request',p.id,p_operation_key||':mov',auth.uid(),coalesce(p_paid_at,now())) returning * into m;
 update public.financial_accounts set current_balance=m.balance_after,updated_at=now(),updated_by=auth.uid() where id=a.id;
 insert into public.supplier_payments(supplier_request_id,supplier_id,financial_account_id,financial_movement_id,amount,payment_method,reference_number,notes,operation_key,payment_date,created_by)
 values(p.id,p.supplier_id,a.id,m.id,p_amount,p_payment_method,p_reference_number,p_notes,p_operation_key,coalesce(p_paid_at,now()),auth.uid()) returning * into result;
 new_paid:=p.amount_paid+p_amount;
 update public.supplier_requests set amount_paid=new_paid,balance_due=greatest(0,total_amount-new_paid),payment_status=case when new_paid>=total_amount then 'pagada' else 'parcial' end,updated_by=auth.uid() where id=p.id;
 return result;
end $$;

alter table public.financial_accounts enable row level security;
alter table public.financial_movements enable row level security;
alter table public.supplier_payments enable row level security;

drop policy if exists financial_accounts_read on public.financial_accounts;
create policy financial_accounts_read on public.financial_accounts for select to authenticated using(public.is_active_cofounder());
drop policy if exists financial_movements_read on public.financial_movements;
create policy financial_movements_read on public.financial_movements for select to authenticated using(public.is_active_cofounder());
drop policy if exists supplier_payments_read on public.supplier_payments;
create policy supplier_payments_read on public.supplier_payments for select to authenticated using(public.is_active_cofounder());

revoke all on public.financial_accounts,public.financial_movements,public.supplier_payments from anon;
revoke insert,update,delete on public.financial_accounts,public.financial_movements,public.supplier_payments from authenticated;
grant select on public.financial_accounts,public.financial_movements,public.supplier_payments to authenticated;
grant execute on function public.create_supplier_purchase_atomic(uuid,date,date,text,date,numeric,numeric,numeric,text,jsonb,text) to authenticated;
grant execute on function public.confirm_supplier_purchase_atomic(uuid,text) to authenticated;
grant execute on function public.configure_initial_balance_atomic(uuid,numeric,date,text,text) to authenticated;
grant execute on function public.register_financial_movement_atomic(uuid,text,numeric,text,text,timestamptz,text) to authenticated;
grant execute on function public.register_supplier_payment_atomic(uuid,uuid,numeric,text,timestamptz,text,text,text) to authenticated;

commit;

-- ============================================================
-- FIN BLOQUE: 026_consolidacion_funcional_fases_2_15.sql
-- ============================================================

-- ============================================================
-- INICIO BLOQUE: 027_transferencias_reversiones_fase_24.sql
-- ============================================================
begin;

create or replace function public.transfer_financial_funds_atomic(
  p_source_account_id uuid,
  p_destination_account_id uuid,
  p_amount numeric,
  p_description text,
  p_occurred_at timestamptz,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_source public.financial_accounts;
  v_destination public.financial_accounts;
  v_group uuid := gen_random_uuid();
  v_out public.financial_movements;
  v_in public.financial_movements;
  v_existing public.financial_movements;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_source_account_id = p_destination_account_id then raise exception 'Las cuentas deben ser diferentes'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'El valor debe ser mayor que cero'; end if;
  if length(coalesce(p_operation_key,'')) < 12 then raise exception 'Clave de operación inválida'; end if;

  select * into v_existing from public.financial_movements where operation_key=p_operation_key||':salida';
  if found then
    select * into v_in from public.financial_movements where operation_key=p_operation_key||':entrada';
    return jsonb_build_object('outgoing',to_jsonb(v_existing),'incoming',to_jsonb(v_in),'recovered',true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(least(p_source_account_id::text,p_destination_account_id::text),0));
  perform pg_advisory_xact_lock(hashtextextended(greatest(p_source_account_id::text,p_destination_account_id::text),0));

  select * into v_source from public.financial_accounts where id=p_source_account_id for update;
  select * into v_destination from public.financial_accounts where id=p_destination_account_id for update;
  if not found then raise exception 'Cuenta destino no encontrada'; end if;
  if v_source.id is null then raise exception 'Cuenta origen no encontrada'; end if;
  if not v_source.active or not v_destination.active then raise exception 'Una de las cuentas está inactiva'; end if;
  if not v_source.initial_balance_configured or not v_destination.initial_balance_configured then raise exception 'Ambas cuentas deben tener saldo inicial configurado'; end if;
  if v_source.current_balance < p_amount then raise exception 'Saldo insuficiente en la cuenta origen'; end if;

  insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,created_by,occurred_at,transfer_group_id)
  values(v_source.id,'transferencia_salida',p_amount,v_source.current_balance,v_source.current_balance-p_amount,'transferencia',coalesce(nullif(trim(p_description),''),'Transferencia entre cuentas'),p_operation_key||':salida',auth.uid(),auth.uid(),coalesce(p_occurred_at,now()),v_group)
  returning * into v_out;

  insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,created_by,occurred_at,transfer_group_id)
  values(v_destination.id,'transferencia_entrada',p_amount,v_destination.current_balance,v_destination.current_balance+p_amount,'transferencia',coalesce(nullif(trim(p_description),''),'Transferencia entre cuentas'),p_operation_key||':entrada',auth.uid(),auth.uid(),coalesce(p_occurred_at,now()),v_group)
  returning * into v_in;

  update public.financial_accounts set current_balance=v_out.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_source.id;
  update public.financial_accounts set current_balance=v_in.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_destination.id;

  return jsonb_build_object('outgoing',to_jsonb(v_out),'incoming',to_jsonb(v_in),'recovered',false);
end $$;

create or replace function public.reverse_financial_movement_atomic(
  p_movement_id uuid,
  p_reason text,
  p_operation_key text
)
returns public.financial_movements
language plpgsql
security definer
set search_path=''
as $$
declare
  v_original public.financial_movements;
  v_account public.financial_accounts;
  v_reverse public.financial_movements;
  v_delta numeric;
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if length(trim(coalesce(p_reason,''))) < 8 then raise exception 'Escribe un motivo claro para la reversión'; end if;
  select * into v_reverse from public.financial_movements where operation_key=p_operation_key;
  if found then return v_reverse; end if;

  select * into v_original from public.financial_movements where id=p_movement_id for update;
  if not found then raise exception 'Movimiento no encontrado'; end if;
  if v_original.status <> 'activo' then raise exception 'El movimiento ya fue reversado'; end if;
  if v_original.movement_type in ('saldo_inicial','transferencia_entrada','transferencia_salida','reversion') then raise exception 'Este movimiento no se puede reversar desde esta opción'; end if;

  select * into v_account from public.financial_accounts where id=v_original.account_id for update;
  v_delta := case when v_original.movement_type in ('ingreso','ajuste_positivo') then -v_original.amount else v_original.amount end;
  if v_account.current_balance + v_delta < 0 then raise exception 'Saldo insuficiente para reversar el movimiento'; end if;

  insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,operation_key,performed_by,created_by,occurred_at,reversal_of_id,source_type,source_id)
  values(v_account.id,'reversion',v_original.amount,v_account.current_balance,v_account.current_balance+v_delta,'reversion',trim(p_reason),p_operation_key,auth.uid(),auth.uid(),now(),v_original.id,v_original.source_type,v_original.source_id)
  returning * into v_reverse;

  update public.financial_accounts set current_balance=v_reverse.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_account.id;
  update public.financial_movements set status='reversado' where id=v_original.id;
  return v_reverse;
end $$;

-- Corrige la RPC de pagos para el modelo consolidado de la fase 20.
create or replace function public.register_supplier_payment_atomic(p_supplier_request_id uuid,p_account_id uuid,p_amount numeric,p_payment_method text,p_paid_at timestamptz,p_reference_number text,p_notes text,p_operation_key text)
returns public.supplier_payments language plpgsql security definer set search_path=''
as $$ declare p public.supplier_requests; a public.financial_accounts; m public.financial_movements; result public.supplier_payments; new_paid numeric; begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 select * into result from public.supplier_payments where operation_key=p_operation_key; if found then return result; end if;
 select * into p from public.supplier_requests where id=p_supplier_request_id for update; if not found or p.status in ('cancelada','anulada') then raise exception 'Compra no disponible'; end if;
 if p_amount<=0 or p_amount>coalesce(p.balance_due,p.total_amount) then raise exception 'Pago inválido o superior al saldo pendiente'; end if;
 select * into a from public.financial_accounts where id=p_account_id for update; if not found or not a.active or not a.initial_balance_configured or a.current_balance<p_amount then raise exception 'Cuenta no disponible o saldo insuficiente'; end if;
 insert into public.financial_movements(account_id,movement_type,amount,balance_before,balance_after,category,description,source_type,source_id,operation_key,performed_by,created_by,occurred_at)
 values(a.id,'egreso',p_amount,a.current_balance,a.current_balance-p_amount,'pago_proveedor','Pago a proveedor','supplier_request',p.id,p_operation_key||':mov',auth.uid(),auth.uid(),coalesce(p_paid_at,now())) returning * into m;
 update public.financial_accounts set current_balance=m.balance_after,updated_at=now(),updated_by=auth.uid() where id=a.id;
 insert into public.supplier_payments(supplier_request_id,supplier_id,financial_account_id,financial_movement_id,amount,payment_method,reference_number,notes,operation_key,payment_date,created_by)
 values(p.id,p.supplier_id,a.id,m.id,p_amount,p_payment_method,p_reference_number,p_notes,p_operation_key,coalesce(p_paid_at,now()),auth.uid()) returning * into result;
 new_paid:=coalesce(p.amount_paid,0)+p_amount;
 update public.supplier_requests set amount_paid=new_paid,balance_due=greatest(0,total_amount-new_paid),payment_status=case when new_paid>=total_amount then 'pagada' else 'parcial' end,updated_by=auth.uid() where id=p.id;
 return result;
end $$;

grant execute on function public.transfer_financial_funds_atomic(uuid,uuid,numeric,text,timestamptz,text) to authenticated;
grant execute on function public.reverse_financial_movement_atomic(uuid,text,text) to authenticated;
grant execute on function public.register_supplier_payment_atomic(uuid,uuid,numeric,text,timestamptz,text,text,text) to authenticated;
revoke all on function public.transfer_financial_funds_atomic(uuid,uuid,numeric,text,timestamptz,text) from anon;
revoke all on function public.reverse_financial_movement_atomic(uuid,text,text) from anon;

commit;

-- ============================================================
-- FIN BLOQUE: 027_transferencias_reversiones_fase_24.sql
-- ============================================================

-- ============================================================
-- INICIO BLOQUE: 028_integracion_ventas_pedidos_caja_fase_24.sql
-- ============================================================
begin;

alter table public.quick_sales
  add column if not exists financial_account_id uuid references public.financial_accounts(id) on delete restrict,
  add column if not exists financial_movement_id uuid references public.financial_movements(id) on delete restrict;

alter table public.payments
  add column if not exists financial_account_id uuid references public.financial_accounts(id) on delete restrict,
  add column if not exists financial_movement_id uuid references public.financial_movements(id) on delete restrict;

create unique index if not exists quick_sales_financial_movement_uidx
  on public.quick_sales(financial_movement_id) where financial_movement_id is not null;
create unique index if not exists payments_financial_movement_uidx
  on public.payments(financial_movement_id) where financial_movement_id is not null;
create index if not exists quick_sales_financial_account_idx on public.quick_sales(financial_account_id);
create index if not exists payments_financial_account_idx on public.payments(financial_account_id);

create or replace function public.create_quick_sale_financial_atomic_idempotent(
  p_operation_key text,
  p_customer_id uuid default null,
  p_payment_method text default 'efectivo',
  p_financial_account_id uuid default null,
  p_payment_reference text default null,
  p_discount_type text default 'ninguno',
  p_discount_value numeric default 0,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_existing public.quick_sales;
  v_result jsonb;
  v_sale public.quick_sales;
  v_account public.financial_accounts;
  v_movement public.financial_movements;
  v_movement_key text := p_operation_key || ':ingreso';
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_financial_account_id is null then raise exception 'Selecciona la cuenta que recibió el dinero'; end if;

  select * into v_existing from public.quick_sales where financial_movement_id in (
    select id from public.financial_movements where operation_key=v_movement_key
  );
  if found then
    return jsonb_build_object(
      'sale',to_jsonb(v_existing),
      'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_existing.id),
      'idempotent',true
    );
  end if;

  select * into v_account from public.financial_accounts where id=p_financial_account_id for update;
  if not found or not v_account.active or not v_account.initial_balance_configured then
    raise exception 'La cuenta seleccionada no está disponible o no tiene saldo inicial configurado';
  end if;

  v_result := public.create_quick_sale_atomic_idempotent(
    p_operation_key,p_customer_id,p_payment_method,p_payment_reference,
    p_discount_type,p_discount_value,p_notes,p_items
  );
  v_sale := jsonb_populate_record(null::public.quick_sales,v_result->'sale');

  if v_sale.financial_movement_id is null then
    insert into public.financial_movements(
      account_id,movement_type,amount,balance_before,balance_after,category,description,
      source_type,source_id,operation_key,performed_by,occurred_at
    ) values (
      v_account.id,'ingreso',v_sale.total,v_account.current_balance,v_account.current_balance+v_sale.total,
      'venta_rapida','Ingreso por venta rápida '||v_sale.sale_number,'quick_sale',v_sale.id,
      v_movement_key,auth.uid(),coalesce(v_sale.created_at,now())
    ) returning * into v_movement;

    update public.financial_accounts
      set current_balance=v_movement.balance_after,updated_by=auth.uid(),updated_at=now()
      where id=v_account.id;
    update public.quick_sales
      set financial_account_id=v_account.id,financial_movement_id=v_movement.id
      where id=v_sale.id returning * into v_sale;
  end if;

  return jsonb_build_object(
    'sale',to_jsonb(v_sale),
    'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from public.quick_sale_items i where i.sale_id=v_sale.id),
    'idempotent',coalesce((v_result->>'idempotent')::boolean,false)
  );
end;
$$;

create or replace function public.cancel_quick_sale_financial_atomic_idempotent(
  p_operation_key text,
  p_sale_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_sale public.quick_sales;
  v_account public.financial_accounts;
  v_original public.financial_movements;
  v_reverse public.financial_movements;
  v_result jsonb;
  v_reverse_key text := p_operation_key || ':reintegro';
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  select * into v_sale from public.quick_sales where id=p_sale_id for update;
  if not found then raise exception 'Venta no encontrada'; end if;
  if v_sale.financial_account_id is null or v_sale.financial_movement_id is null then
    raise exception 'La venta no tiene un movimiento financiero asociado';
  end if;

  select * into v_reverse from public.financial_movements where operation_key=v_reverse_key;
  if found then return jsonb_build_object('sale_id',p_sale_id,'financial_reversal',to_jsonb(v_reverse),'idempotent',true); end if;

  select * into v_account from public.financial_accounts where id=v_sale.financial_account_id for update;
  select * into v_original from public.financial_movements where id=v_sale.financial_movement_id for update;
  if v_account.current_balance < v_sale.total then raise exception 'Saldo insuficiente en la cuenta para anular esta venta'; end if;

  v_result := public.cancel_quick_sale_atomic_idempotent(p_operation_key,p_sale_id,p_reason);

  insert into public.financial_movements(
    account_id,movement_type,amount,balance_before,balance_after,category,description,
    source_type,source_id,operation_key,performed_by,occurred_at
  ) values (
    v_account.id,'egreso',v_sale.total,v_account.current_balance,v_account.current_balance-v_sale.total,
    'anulacion_venta','Reintegro por anulación de '||v_sale.sale_number,'quick_sale',v_sale.id,
    v_reverse_key,auth.uid(),now()
  ) returning * into v_reverse;

  update public.financial_accounts set current_balance=v_reverse.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_account.id;
  update public.financial_movements set status='reversado' where id=v_original.id and status='activo';

  return v_result || jsonb_build_object('financial_reversal',to_jsonb(v_reverse));
end;
$$;

create or replace function public.close_order_direct_financial_atomic_idempotent(
  p_operation_key text,
  p_order_id uuid,
  p_payment_method text,
  p_financial_account_id uuid,
  p_reason text,
  p_reference_number text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order public.orders;
  v_account public.financial_accounts;
  v_payment public.payments;
  v_movement public.financial_movements;
  v_result jsonb;
  v_movement_key text := p_operation_key || ':ingreso';
begin
  if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
  if p_financial_account_id is null then raise exception 'Selecciona la cuenta que recibió el dinero'; end if;

  select * into v_movement from public.financial_movements where operation_key=v_movement_key;
  if found then
    select * into v_order from public.orders where id=p_order_id;
    return jsonb_build_object('order',to_jsonb(v_order),'financial_movement',to_jsonb(v_movement),'idempotent',true);
  end if;

  select * into v_account from public.financial_accounts where id=p_financial_account_id for update;
  if not found or not v_account.active or not v_account.initial_balance_configured then
    raise exception 'La cuenta seleccionada no está disponible o no tiene saldo inicial configurado';
  end if;

  v_result := public.close_order_direct_atomic_idempotent(
    p_operation_key,p_order_id,p_payment_method,p_reason,p_reference_number,p_notes
  );
  select * into v_order from public.orders where id=p_order_id for update;

  select * into v_payment
  from public.payments
  where order_id=p_order_id and status='pagado'::public.payment_status
  order by payment_date desc, created_at desc
  limit 1
  for update;
  if not found then raise exception 'No se encontró el pago creado para el pedido'; end if;

  if v_payment.financial_movement_id is null then
    insert into public.financial_movements(
      account_id,movement_type,amount,balance_before,balance_after,category,description,
      source_type,source_id,operation_key,performed_by,occurred_at
    ) values (
      v_account.id,'ingreso',v_payment.amount,v_account.current_balance,v_account.current_balance+v_payment.amount,
      'pago_pedido','Ingreso por pedido '||v_order.order_number,'order',v_order.id,
      v_movement_key,auth.uid(),coalesce(v_payment.payment_date,now())
    ) returning * into v_movement;

    update public.financial_accounts set current_balance=v_movement.balance_after,updated_by=auth.uid(),updated_at=now() where id=v_account.id;
    update public.payments set financial_account_id=v_account.id,financial_movement_id=v_movement.id where id=v_payment.id returning * into v_payment;
  end if;

  return v_result || jsonb_build_object('financial_movement',to_jsonb(v_movement),'payment',to_jsonb(v_payment));
end;
$$;

revoke all on function public.create_quick_sale_financial_atomic_idempotent(text,uuid,text,uuid,text,text,numeric,text,jsonb) from public,anon;
grant execute on function public.create_quick_sale_financial_atomic_idempotent(text,uuid,text,uuid,text,text,numeric,text,jsonb) to authenticated;
revoke all on function public.cancel_quick_sale_financial_atomic_idempotent(text,uuid,text) from public,anon;
grant execute on function public.cancel_quick_sale_financial_atomic_idempotent(text,uuid,text) to authenticated;
revoke all on function public.close_order_direct_financial_atomic_idempotent(text,uuid,text,uuid,text,text,text) from public,anon;
grant execute on function public.close_order_direct_financial_atomic_idempotent(text,uuid,text,uuid,text,text,text) to authenticated;

commit;

-- ============================================================
-- FIN BLOQUE: 028_integracion_ventas_pedidos_caja_fase_24.sql
-- ============================================================

-- ============================================================
-- INICIO BLOQUE: 029_coherencia_migraciones_fase_24.sql
-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 029
-- Fase 24: coherencia y compatibilidad entre migraciones 024–028
--
-- Objetivo:
-- 1) normalizar nombres de columnas que evolucionaron entre fases;
-- 2) conservar compatibilidad con instalaciones parciales anteriores;
-- 3) completar columnas requeridas por las RPC financieras;
-- 4) exponer un diagnóstico ejecutable antes de probar producción.
--
-- Ejecutar después de 028. Es defensiva e idempotente.
-- No crea compras, pagos, saldos ni movimientos ficticios.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Compras: reception_status es el nombre canónico del frontend.
--    receipt_status se conserva como alias de compatibilidad.
-- ------------------------------------------------------------
alter table if exists public.supplier_requests
  add column if not exists reception_status text default 'pendiente',
  add column if not exists receipt_status text default 'pendiente',
  add column if not exists operation_key text,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if to_regclass('public.supplier_requests') is not null then
    update public.supplier_requests
       set reception_status = coalesce(nullif(reception_status,''), nullif(receipt_status,''), 'pendiente'),
           receipt_status = coalesce(nullif(reception_status,''), nullif(receipt_status,''), 'pendiente');
  end if;
end $$;

create or replace function public.sync_supplier_request_reception_status()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if tg_op = 'INSERT' then
    new.reception_status := coalesce(nullif(new.reception_status,''), nullif(new.receipt_status,''), 'pendiente');
    new.receipt_status := new.reception_status;
  else
    if new.reception_status is distinct from old.reception_status then
      new.receipt_status := new.reception_status;
    elsif new.receipt_status is distinct from old.receipt_status then
      new.reception_status := new.receipt_status;
    else
      new.reception_status := coalesce(nullif(new.reception_status,''), 'pendiente');
      new.receipt_status := new.reception_status;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_sync_supplier_request_reception_status on public.supplier_requests;
create trigger trg_sync_supplier_request_reception_status
before insert or update of reception_status, receipt_status
on public.supplier_requests
for each row execute function public.sync_supplier_request_reception_status();

create unique index if not exists ux_supplier_requests_operation_key
  on public.supplier_requests(operation_key)
  where operation_key is not null;

-- ------------------------------------------------------------
-- 2. Cuentas financieras: normaliza moneda y tipos históricos.
-- ------------------------------------------------------------
alter table if exists public.financial_accounts
  add column if not exists currency_code text default 'COP',
  add column if not exists created_by uuid,
  add column if not exists updated_by uuid,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if to_regclass('public.financial_accounts') is not null then
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='financial_accounts' and column_name='currency'
    ) then
      execute $q$
        update public.financial_accounts
           set currency_code = coalesce(nullif(currency_code,''), nullif(currency,''), 'COP')
      $q$;
    else
      update public.financial_accounts set currency_code=coalesce(nullif(currency_code,''),'COP');
    end if;

    update public.financial_accounts
       set account_type = case lower(coalesce(account_type,''))
         when 'wallet' then 'billetera_digital'
         when 'cash' then 'efectivo'
         when 'bank' then 'banco'
         when 'billetera_digital' then 'billetera_digital'
         when 'efectivo' then 'efectivo'
         when 'banco' then 'banco'
         else 'otro'
       end;
  end if;
end $$;

do $$
declare c record;
begin
  if to_regclass('public.financial_accounts') is null then return; end if;
  for c in
    select conname
      from pg_constraint
     where conrelid='public.financial_accounts'::regclass
       and contype='c'
       and pg_get_constraintdef(oid) ilike '%account_type%'
  loop
    execute format('alter table public.financial_accounts drop constraint %I', c.conname);
  end loop;
  if not exists(select 1 from pg_constraint where conname='financial_accounts_account_type_allowed') then
    alter table public.financial_accounts
      add constraint financial_accounts_account_type_allowed
      check (account_type in ('billetera_digital','efectivo','banco','otro')) not valid;
  end if;
end $$;

-- ------------------------------------------------------------
-- 3. Libro financiero: completa columnas usadas por 026–028.
-- ------------------------------------------------------------
alter table if exists public.financial_movements
  add column if not exists reference_number text,
  add column if not exists transfer_group_id uuid,
  add column if not exists reversal_of_id uuid references public.financial_movements(id) on delete restrict,
  add column if not exists performed_by uuid,
  add column if not exists created_by uuid,
  add column if not exists source_type text,
  add column if not exists source_id uuid,
  add column if not exists description text,
  add column if not exists category text,
  add column if not exists occurred_at timestamptz not null default now();

do $$
begin
  if to_regclass('public.financial_movements') is not null then
    update public.financial_movements
       set performed_by=coalesce(performed_by,created_by),
           created_by=coalesce(created_by,performed_by);
  end if;
end $$;

do $$
declare c record;
begin
  if to_regclass('public.financial_movements') is null then return; end if;
  for c in
    select conname
      from pg_constraint
     where conrelid='public.financial_movements'::regclass
       and contype='c'
       and pg_get_constraintdef(oid) ilike '%movement_type%'
  loop
    execute format('alter table public.financial_movements drop constraint %I', c.conname);
  end loop;
  if not exists(select 1 from pg_constraint where conname='financial_movements_type_allowed') then
    alter table public.financial_movements
      add constraint financial_movements_type_allowed check (
        movement_type in (
          'saldo_inicial','ingreso','egreso','ajuste_positivo','ajuste_negativo',
          'transferencia_entrada','transferencia_salida','reversion'
        )
      ) not valid;
  end if;
end $$;

create index if not exists financial_movements_account_date_idx
  on public.financial_movements(account_id,occurred_at desc);
create index if not exists financial_movements_source_idx
  on public.financial_movements(source_type,source_id);
create index if not exists financial_movements_transfer_group_idx
  on public.financial_movements(transfer_group_id)
  where transfer_group_id is not null;

-- ------------------------------------------------------------
-- 4. Pagos a proveedores: nombres canónicos usados por JS/reportes.
-- ------------------------------------------------------------
alter table if exists public.supplier_payments
  add column if not exists financial_account_id uuid references public.financial_accounts(id) on delete restrict,
  add column if not exists payment_date timestamptz default now(),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid,
  add column if not exists cancellation_reason text;

do $$
begin
  if to_regclass('public.supplier_payments') is null then return; end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='supplier_payments' and column_name='account_id'
  ) then
    execute $q$
      update public.supplier_payments
         set financial_account_id=coalesce(financial_account_id,account_id)
    $q$;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='supplier_payments' and column_name='paid_at'
  ) then
    execute $q$
      update public.supplier_payments
         set payment_date=coalesce(payment_date,paid_at,created_at,now())
    $q$;
  else
    update public.supplier_payments
       set payment_date=coalesce(payment_date,created_at,now());
  end if;
end $$;

create index if not exists supplier_payments_request_date_idx
  on public.supplier_payments(supplier_request_id,payment_date desc);
create index if not exists supplier_payments_account_date_idx
  on public.supplier_payments(financial_account_id,payment_date desc);
create unique index if not exists supplier_payments_operation_key_uidx
  on public.supplier_payments(operation_key);
create unique index if not exists supplier_payments_financial_movement_uidx
  on public.supplier_payments(financial_movement_id)
  where financial_movement_id is not null;

-- ------------------------------------------------------------
-- 5. Vista de conciliación recompilada con nombres canónicos.
-- ------------------------------------------------------------
-- PostgreSQL no permite renombrar/reordenar columnas con CREATE OR REPLACE VIEW.
-- Se elimina la vista técnica y se recrea; no contiene datos almacenados.
drop view if exists public.v_supplier_purchase_account_status;

create view public.v_supplier_purchase_account_status as
select
  sr.id as supplier_request_id,
  sr.supplier_id,
  sr.status as purchase_status,
  sr.reception_status,
  sr.payment_status,
  sr.total_amount,
  sr.amount_paid as stored_amount_paid,
  sr.balance_due as stored_balance_due,
  coalesce(sum(sp.amount) filter (where sp.status='activo'),0)::numeric(14,2) as active_payments_total,
  greatest(0,coalesce(sr.total_amount,0)-coalesce(sum(sp.amount) filter (where sp.status='activo'),0))::numeric(14,2) as calculated_balance_due,
  max(sp.payment_date) filter (where sp.status='activo') as last_payment_at
from public.supplier_requests sr
left join public.supplier_payments sp on sp.supplier_request_id=sr.id
group by sr.id;

grant select on public.v_supplier_purchase_account_status to authenticated;

-- ------------------------------------------------------------
-- 6. Diagnóstico ejecutable del esquema instalado.
-- ------------------------------------------------------------
create or replace function public.validate_lihen_schema_coherence()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_missing_columns jsonb;
  v_missing_functions jsonb;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  select coalesce(jsonb_agg(format('%s.%s',required.table_name,required.column_name) order by required.table_name,required.column_name),'[]'::jsonb)
    into v_missing_columns
  from (values
    ('supplier_requests','reception_status'),
    ('supplier_requests','payment_status'),
    ('supplier_requests','total_amount'),
    ('supplier_requests','balance_due'),
    ('financial_accounts','current_balance'),
    ('financial_accounts','initial_balance_configured'),
    ('financial_movements','operation_key'),
    ('financial_movements','performed_by'),
    ('financial_movements','transfer_group_id'),
    ('financial_movements','reversal_of_id'),
    ('supplier_payments','financial_account_id'),
    ('supplier_payments','payment_date'),
    ('quick_sales','financial_account_id'),
    ('quick_sales','financial_movement_id'),
    ('payments','financial_account_id'),
    ('payments','financial_movement_id')
  ) as required(table_name,column_name)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema='public'
      and c.table_name=required.table_name
      and c.column_name=required.column_name
  );

  select coalesce(jsonb_agg(required.signature order by required.signature),'[]'::jsonb)
    into v_missing_functions
  from (values
    ('public.create_supplier_purchase_atomic'),
    ('public.confirm_supplier_purchase_atomic'),
    ('public.configure_initial_balance_atomic'),
    ('public.register_financial_movement_atomic'),
    ('public.register_supplier_payment_atomic'),
    ('public.transfer_financial_funds_atomic'),
    ('public.reverse_financial_movement_atomic'),
    ('public.import_inventory_batch_atomic'),
    ('public.create_quick_sale_financial_atomic_idempotent'),
    ('public.cancel_quick_sale_financial_atomic_idempotent'),
    ('public.close_order_direct_financial_atomic_idempotent')
  ) as required(signature)
  where to_regprocedure(required.signature || case
    when required.signature='public.create_supplier_purchase_atomic' then '(uuid,date,date,text,date,numeric,numeric,numeric,text,jsonb,text)'
    when required.signature='public.confirm_supplier_purchase_atomic' then '(uuid,text)'
    when required.signature='public.configure_initial_balance_atomic' then '(uuid,numeric,date,text,text)'
    when required.signature='public.register_financial_movement_atomic' then '(uuid,text,numeric,text,text,timestamptz,text)'
    when required.signature='public.register_supplier_payment_atomic' then '(uuid,uuid,numeric,text,timestamptz,text,text,text)'
    when required.signature='public.transfer_financial_funds_atomic' then '(uuid,uuid,numeric,text,timestamptz,text)'
    when required.signature='public.reverse_financial_movement_atomic' then '(uuid,text,text)'
    when required.signature='public.import_inventory_batch_atomic' then '(text,text,integer,integer,jsonb)'
    when required.signature='public.create_quick_sale_financial_atomic_idempotent' then '(text,uuid,text,uuid,text,text,numeric,text,jsonb)'
    when required.signature='public.cancel_quick_sale_financial_atomic_idempotent' then '(text,uuid,text)'
    when required.signature='public.close_order_direct_financial_atomic_idempotent' then '(text,uuid,text,uuid,text,text,text)'
    else '()' end) is null;

  return jsonb_build_object(
    'ok', jsonb_array_length(v_missing_columns)=0 and jsonb_array_length(v_missing_functions)=0,
    'missing_columns',v_missing_columns,
    'missing_functions',v_missing_functions,
    'checked_at',now()
  );
end $$;

revoke all on function public.validate_lihen_schema_coherence() from public,anon;
grant execute on function public.validate_lihen_schema_coherence() to authenticated;

commit;
-- FIN BLOQUE: 029_coherencia_migraciones_fase_24.sql
-- ============================================================

-- ============================================================
-- VERIFICACIÓN FINAL RECOMENDADA
-- Descomente y ejecute después de terminar la migración:
-- select public.validate_lihen_schema_coherence();
-- ============================================================


-- ============================================================
-- INICIO BLOQUE: 030_compras_historicas_sin_impacto.sql
-- ============================================================
-- LIHEN ADMIN - Compras históricas sin impacto en inventario ni caja
begin;

alter table if exists public.supplier_requests
  add column if not exists is_historical boolean not null default false,
  add column if not exists inventory_impact boolean not null default true,
  add column if not exists financial_impact boolean not null default true,
  add column if not exists historical_paid_amount numeric(14,2) not null default 0,
  add column if not exists historical_payment_method text,
  add column if not exists historical_payment_date date,
  add column if not exists historical_source_reference text,
  add column if not exists historical_registered_at timestamptz,
  add column if not exists historical_registered_by uuid;

create index if not exists idx_supplier_requests_historical
  on public.supplier_requests(is_historical, purchase_date desc);

create or replace function public.register_historical_supplier_purchase_atomic(
  p_supplier_id uuid,
  p_purchase_date date,
  p_invoice_number text,
  p_due_date date,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_freight_amount numeric,
  p_historical_paid_amount numeric,
  p_historical_payment_method text,
  p_historical_payment_date date,
  p_source_reference text,
  p_notes text,
  p_items jsonb,
  p_operation_key text
) returns public.supplier_requests
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_purchase public.supplier_requests;
  v_item jsonb;
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
  v_paid numeric(14,2);
  v_qty integer;
  v_cost numeric(14,2);
  v_product uuid;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;
  if coalesce(length(trim(p_operation_key)),0) < 12 then
    raise exception 'Clave de operación inválida';
  end if;

  select * into v_purchase
  from public.supplier_requests
  where operation_key = p_operation_key;
  if found then return v_purchase; end if;

  if not exists(select 1 from public.suppliers where id=p_supplier_id and active=true) then
    raise exception 'Proveedor no encontrado o inactivo';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'La compra histórica debe incluir productos asociados';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity_requested')::integer;
    v_cost := (v_item->>'quoted_unit_cost')::numeric;
    if v_qty <= 0 or v_cost < 0 then raise exception 'Cantidad o costo inválido'; end if;
    if not exists(select 1 from public.products where id=v_product) then
      raise exception 'Producto no encontrado';
    end if;
    v_subtotal := v_subtotal + (v_qty * v_cost);
  end loop;

  v_total := greatest(0, v_subtotal - coalesce(p_discount_amount,0) + coalesce(p_tax_amount,0) + coalesce(p_freight_amount,0));
  v_paid := least(v_total, greatest(0, coalesce(p_historical_paid_amount,0)));

  insert into public.supplier_requests(
    supplier_id,status,purchase_date,invoice_number,due_date,reception_status,payment_status,
    subtotal,discount_amount,tax_amount,freight_amount,total_amount,amount_paid,balance_due,notes,
    operation_key,created_by,updated_by,is_historical,inventory_impact,financial_impact,
    historical_paid_amount,historical_payment_method,historical_payment_date,historical_source_reference,
    historical_registered_at,historical_registered_by
  ) values (
    p_supplier_id,'confirmada',coalesce(p_purchase_date,current_date),nullif(trim(p_invoice_number),''),p_due_date,
    'completa',case when v_paid >= v_total then 'pagada' when v_paid > 0 then 'parcial' else 'pendiente' end,
    v_subtotal,coalesce(p_discount_amount,0),coalesce(p_tax_amount,0),coalesce(p_freight_amount,0),v_total,
    v_paid,greatest(0,v_total-v_paid),p_notes,p_operation_key,v_user,v_user,true,false,false,
    v_paid,nullif(trim(p_historical_payment_method),''),p_historical_payment_date,nullif(trim(p_source_reference),''),
    now(),v_user
  ) returning * into v_purchase;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity_requested')::integer;
    v_cost := (v_item->>'quoted_unit_cost')::numeric;

    insert into public.supplier_request_items(
      supplier_request_id,product_id,quantity_requested,quoted_unit_cost,quantity_received
    ) values (v_purchase.id,v_product,v_qty,v_cost,v_qty);

    update public.supplier_products
       set last_cost = case when v_cost > 0 then v_cost else last_cost end
     where supplier_id=p_supplier_id and product_id=v_product;
    if not found then
      insert into public.supplier_products(supplier_id,product_id,last_cost,preferred)
      values(p_supplier_id,v_product,v_cost,false);
    end if;
  end loop;

  -- Intencionalmente NO modifica inventory, financial_accounts ni financial_movements.
  return v_purchase;
end $$;

revoke all on function public.register_historical_supplier_purchase_atomic(uuid,date,text,date,numeric,numeric,numeric,numeric,text,date,text,text,jsonb,text) from public,anon;
grant execute on function public.register_historical_supplier_purchase_atomic(uuid,date,text,date,numeric,numeric,numeric,numeric,text,date,text,text,jsonb,text) to authenticated;

commit;

-- FIN BLOQUE: 030_compras_historicas_sin_impacto.sql


-- LIHEN ADMIN - Importación masiva de compras históricas y actuales
begin;

create table if not exists public.supplier_purchase_import_batches (
  id uuid primary key default gen_random_uuid(),
  operation_key text not null unique,
  file_name text not null,
  template_version text not null,
  total_rows integer not null default 0 check (total_rows >= 0),
  created_count integer not null default 0 check (created_count >= 0),
  updated_count integer not null default 0 check (updated_count >= 0),
  unchanged_count integer not null default 0 check (unchanged_count >= 0),
  error_count integer not null default 0 check (error_count >= 0),
  status text not null default 'procesando' check (status in ('procesando','completado','fallido')),
  result jsonb not null default '{}'::jsonb,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.supplier_purchase_import_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.supplier_purchase_import_batches(id) on delete cascade,
  purchase_id uuid references public.supplier_requests(id) on delete restrict,
  purchase_key text not null,
  action text not null check (action in ('create','update','unchanged')),
  purchase_type text not null check (purchase_type in ('historica','actual')),
  status text not null default 'aplicada' check (status in ('aplicada','sin_cambios','error')),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(batch_id,purchase_key)
);

create index if not exists idx_supplier_purchase_import_batches_created_at on public.supplier_purchase_import_batches(created_at desc);
create index if not exists idx_supplier_purchase_import_rows_batch on public.supplier_purchase_import_rows(batch_id);

alter table public.supplier_purchase_import_batches enable row level security;
alter table public.supplier_purchase_import_rows enable row level security;
alter table public.supplier_purchase_import_batches force row level security;
alter table public.supplier_purchase_import_rows force row level security;

drop policy if exists supplier_purchase_import_batches_select on public.supplier_purchase_import_batches;
create policy supplier_purchase_import_batches_select on public.supplier_purchase_import_batches for select to authenticated
using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.active=true));
drop policy if exists supplier_purchase_import_rows_select on public.supplier_purchase_import_rows;
create policy supplier_purchase_import_rows_select on public.supplier_purchase_import_rows for select to authenticated
using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.active=true));

revoke insert,update,delete on public.supplier_purchase_import_batches from authenticated,anon;
revoke insert,update,delete on public.supplier_purchase_import_rows from authenticated,anon;


create or replace function public.receive_supplier_purchase_v2_atomic(p_supplier_request_id uuid,p_items jsonb,p_notes text,p_operation_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_purchase public.supplier_requests; v_receipt public.supplier_purchase_receipts; v_item jsonb; v_detail public.supplier_request_items; v_inventory public.inventory; v_qty int; v_cost numeric; v_received_total int:=0; v_pending_total int;
begin
 if not public.is_active_cofounder() then raise exception 'Acceso no autorizado'; end if;
 select * into v_receipt from public.supplier_purchase_receipts where operation_key=p_operation_key; if found then return to_jsonb(v_receipt); end if;
 select * into v_purchase from public.supplier_requests where id=p_supplier_request_id for update; if not found then raise exception 'Compra no encontrada'; end if;
 if v_purchase.is_historical then raise exception 'Las compras históricas no generan recepciones actuales'; end if;
 if v_purchase.status='borrador' then raise exception 'Confirma la compra antes de recibir mercancía'; end if;
 insert into public.supplier_purchase_receipts(supplier_request_id,received_at,notes,operation_key,created_by) values(v_purchase.id,now(),p_notes,p_operation_key,v_user) returning * into v_receipt;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_qty:=coalesce((v_item->>'quantity')::int,0); v_cost:=coalesce((v_item->>'unit_cost')::numeric,0);
   if v_qty<=0 then continue; end if;
   select * into v_detail from public.supplier_request_items where supplier_request_id=v_purchase.id and product_id=(v_item->>'product_id')::uuid for update;
   if not found or v_detail.quantity_received+v_qty>v_detail.quantity_requested then raise exception 'Cantidad recibida inválida'; end if;
   select * into v_inventory from public.inventory where product_id=v_detail.product_id and variant_id is not distinct from v_detail.variant_id for update;
   if not found then raise exception 'Inventario no encontrado para el producto'; end if;
   insert into public.inventory_movements(inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by)
   values(v_inventory.id,'ajuste_positivo',v_qty,v_inventory.physical_stock,v_inventory.physical_stock+v_qty,v_inventory.reserved_stock,v_inventory.reserved_stock,'Entrada por compra a proveedor',v_user);
   update public.inventory set physical_stock=physical_stock+v_qty,pending_stock=greatest(0,pending_stock-v_qty),average_cost=case when physical_stock+v_qty>0 then ((physical_stock*coalesce(average_cost,0))+(v_qty*v_cost))/(physical_stock+v_qty) else v_cost end,updated_by=v_user where id=v_inventory.id returning * into v_inventory;
   update public.supplier_request_items set quantity_received=quantity_received+v_qty,final_unit_cost=v_cost where id=v_detail.id;
   insert into public.supplier_purchase_receipt_items(receipt_id,supplier_request_item_id,inventory_id,quantity_received,unit_cost,physical_before,physical_after,pending_before,pending_after)
   values(v_receipt.id,v_detail.id,v_inventory.id,v_qty,v_cost,v_inventory.physical_stock-v_qty,v_inventory.physical_stock,v_inventory.pending_stock+v_qty,v_inventory.pending_stock);
   v_received_total:=v_received_total+v_qty;
 end loop;
 select coalesce(sum(quantity_requested-quantity_received),0) into v_pending_total from public.supplier_request_items where supplier_request_id=v_purchase.id;
 update public.supplier_requests set reception_status=case when v_pending_total=0 then 'completa' else 'parcial' end,status=case when v_pending_total=0 then 'recibida' else status end,updated_by=v_user,updated_at=now() where id=v_purchase.id;
 return jsonb_build_object('receipt_id',v_receipt.id,'received_units',v_received_total,'pending_units',v_pending_total);
end $$;
revoke all on function public.receive_supplier_purchase_v2_atomic(uuid,jsonb,text,text) from public,anon;
grant execute on function public.receive_supplier_purchase_v2_atomic(uuid,jsonb,text,text) to authenticated;

create or replace function public.import_supplier_purchases_batch_atomic(p_payload jsonb,p_operation_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_user uuid := auth.uid(); v_batch uuid; v_purchase jsonb; v_purchase_id uuid; v_result jsonb;
  v_created int:=0; v_updated int:=0; v_unchanged int:=0; v_item jsonb; v_payment jsonb;
  v_existing public.supplier_requests%rowtype; v_type text; v_action text; v_status text;
begin
  if v_user is null or not exists(select 1 from public.profiles p where p.id=v_user and p.active=true) then raise exception 'No autorizado'; end if;
  if length(trim(coalesce(p_operation_key,''))) < 12 then raise exception 'Clave de operación inválida'; end if;
  perform pg_advisory_xact_lock(hashtextextended('supplier-purchase-import:'||p_operation_key,0));
  select id,result into v_batch,v_result from public.supplier_purchase_import_batches where operation_key=p_operation_key;
  if v_batch is not null then return v_result || jsonb_build_object('recovered',true); end if;
  if jsonb_typeof(p_payload->'purchases') <> 'array' then raise exception 'El lote de compras es inválido'; end if;
  insert into public.supplier_purchase_import_batches(operation_key,file_name,template_version,total_rows,created_by)
  values(p_operation_key,coalesce(nullif(trim(p_payload->>'file_name'),''),'archivo.xlsx'),coalesce(nullif(trim(p_payload->>'template_version'),''),'LIHEN-COMPRAS-PROVEEDORES-V1'),jsonb_array_length(p_payload->'purchases'),v_user)
  returning id into v_batch;

  for v_purchase in select value from jsonb_array_elements(p_payload->'purchases') loop
    v_type:=v_purchase->>'purchase_type'; v_action:=coalesce(v_purchase->>'action','create');
    if v_type not in ('historica','actual') then raise exception 'Tipo de compra inválido'; end if;
    if v_type='historica' and (coalesce((v_purchase->>'inventory_impact')::boolean,false) or coalesce((v_purchase->>'financial_impact')::boolean,false)) then raise exception 'Una compra histórica no puede afectar inventario ni caja'; end if;
    select * into v_existing from public.supplier_requests where id=nullif(v_purchase->>'purchase_id','')::uuid or operation_key=v_purchase->>'purchase_key' limit 1;
    if found then
      v_purchase_id:=v_existing.id;
      update public.supplier_requests set
        invoice_number=coalesce(nullif(v_purchase->>'invoice_number',''),invoice_number),
        due_date=coalesce(nullif(v_purchase->>'due_date','')::date,due_date),
        notes=coalesce(nullif(v_purchase->>'notes',''),notes),
        source_reference=coalesce(nullif(v_purchase->>'source_reference',''),source_reference),
        updated_by=v_user,updated_at=now()
      where id=v_purchase_id;
      v_updated:=v_updated+1;
    else
      if v_type='historica' then
        select to_jsonb(x) from public.register_historical_supplier_purchase_atomic(
          (v_purchase->>'supplier_id')::uuid,(v_purchase->>'purchase_date')::date,v_purchase->>'invoice_number',nullif(v_purchase->>'due_date','')::date,
          coalesce((v_purchase->>'discount_amount')::numeric,0),coalesce((v_purchase->>'tax_amount')::numeric,0),coalesce((v_purchase->>'freight_amount')::numeric,0),coalesce((v_purchase->>'amount_paid')::numeric,0),
          (select p->>'payment_method' from jsonb_array_elements(coalesce(v_purchase->'payments','[]'::jsonb)) p limit 1),
          (select nullif(p->>'payment_date','')::date from jsonb_array_elements(coalesce(v_purchase->'payments','[]'::jsonb)) p limit 1),
          v_purchase->>'source_reference',v_purchase->>'notes',
          (select jsonb_agg(jsonb_build_object('product_id',i->>'product_id','quantity_requested',i->>'quantity_requested','quoted_unit_cost',i->>'unit_cost')) from jsonb_array_elements(v_purchase->'items') i),
          v_purchase->>'purchase_key') x into v_result;
        v_purchase_id:=(v_result->>'id')::uuid;
      else
        select to_jsonb(x) from public.create_supplier_purchase_atomic(
          (v_purchase->>'supplier_id')::uuid,(v_purchase->>'purchase_date')::date,nullif(v_purchase->>'expected_date','')::date,v_purchase->>'invoice_number',nullif(v_purchase->>'due_date','')::date,
          coalesce((v_purchase->>'discount_amount')::numeric,0),coalesce((v_purchase->>'tax_amount')::numeric,0),coalesce((v_purchase->>'freight_amount')::numeric,0),v_purchase->>'notes',
          (select jsonb_agg(jsonb_build_object('product_id',i->>'product_id','quantity_requested',i->>'quantity_requested','quoted_unit_cost',i->>'unit_cost')) from jsonb_array_elements(v_purchase->'items') i),
          v_purchase->>'purchase_key') x into v_result;
        v_purchase_id:=(v_result->>'id')::uuid;
        v_status:=coalesce(v_purchase->>'status','borrador');
        if v_status <> 'borrador' then perform public.confirm_supplier_purchase_atomic(v_purchase_id,v_purchase->>'purchase_key'||':confirm'); end if;
        if coalesce((select sum((i->>'quantity_received')::int) from jsonb_array_elements(v_purchase->'items') i),0)>0 then
          perform public.receive_supplier_purchase_v2_atomic(v_purchase_id,
            (select jsonb_agg(jsonb_build_object('product_id',i->>'product_id','quantity',(i->>'quantity_received')::int,'unit_cost',(i->>'unit_cost')::numeric)) from jsonb_array_elements(v_purchase->'items') i where (i->>'quantity_received')::int>0),
            'Recepción importada desde '||coalesce(p_payload->>'file_name','Excel'),v_purchase->>'purchase_key'||':receive');
        end if;
        for v_payment in select value from jsonb_array_elements(coalesce(v_purchase->'payments','[]'::jsonb)) loop
          if coalesce((v_payment->>'affects_current_balance')::boolean,true) then
            perform public.register_supplier_payment_atomic(v_purchase_id,(v_payment->>'account_id')::uuid,(v_payment->>'amount')::numeric,coalesce(v_payment->>'payment_method','otro'),coalesce(nullif(v_payment->>'payment_date','')::timestamptz,now()),v_payment->>'reference_number',v_payment->>'notes',v_purchase->>'purchase_key'||':payment:'||md5(v_payment::text));
          end if;
        end loop;
      end if;
      v_created:=v_created+1;
    end if;
    insert into public.supplier_purchase_import_rows(batch_id,purchase_id,purchase_key,action,purchase_type,status,detail)
    values(v_batch,v_purchase_id,v_purchase->>'purchase_key',case when v_existing.id is null then 'create' else 'update' end,v_type,'aplicada',v_purchase);
  end loop;
  v_result:=jsonb_build_object('batch_id',v_batch,'created',v_created,'updated',v_updated,'unchanged',v_unchanged,'total',jsonb_array_length(p_payload->'purchases'));
  update public.supplier_purchase_import_batches set created_count=v_created,updated_count=v_updated,unchanged_count=v_unchanged,status='completado',result=v_result,completed_at=now() where id=v_batch;
  return v_result;
exception when others then
  raise;
end $$;

revoke all on function public.import_supplier_purchases_batch_atomic(jsonb,text) from public,anon;
grant execute on function public.import_supplier_purchases_batch_atomic(jsonb,text) to authenticated;
commit;
