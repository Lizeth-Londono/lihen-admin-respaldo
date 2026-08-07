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
