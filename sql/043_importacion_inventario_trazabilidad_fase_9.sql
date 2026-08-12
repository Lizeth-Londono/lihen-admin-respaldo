-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 043
-- Fase 9: trazabilidad before/after + control de concurrencia
-- para la importación atómica de inventario.
-- Ejecutar después de 042_movimientos_inventario_fase_8.sql.
-- ============================================================

begin;

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
  v_before_product jsonb;
  v_after_product jsonb;
  v_expected jsonb;
  v_before_stock integer;
  v_after_stock integer;
  v_previous_cost numeric(14,2);
  v_created integer := 0;
  v_updated integer := 0;
  v_pending_supplier integer := 0;
  v_stock_changes integer := 0;
  v_cost_changes integer := 0;
  v_stock_units_after bigint := 0;
  v_action text;
  v_changes jsonb;
  v_product_id uuid;
  v_sku text;
  v_has_preferred_supplier boolean;
  v_field text;
  v_before_supplier_name text;
  v_after_supplier_name text;
  v_row_number integer;
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

  if coalesce(p_total_rows, 0) < 0 or coalesce(p_unchanged_rows, 0) < 0 then
    raise exception 'Los contadores de la importación no son válidos';
  end if;

  if jsonb_array_length(p_rows) + greatest(coalesce(p_unchanged_rows,0),0)
     <> greatest(coalesce(p_total_rows,0),0) then
    raise exception 'El total de filas no coincide con las filas accionables y sin cambios';
  end if;

  if exists (
    select 1
    from (
      select nullif(value->>'row_number','')::integer as row_number, count(*)
      from jsonb_array_elements(p_rows)
      group by 1
      having count(*) > 1
    ) duplicated
  ) then
    raise exception 'La importación contiene números de fila duplicados';
  end if;

  if exists (
    select 1
    from (
      select nullif(value->>'product_id','') as product_id, count(*)
      from jsonb_array_elements(p_rows)
      where nullif(value->>'product_id','') is not null
      group by 1
      having count(*) > 1
    ) duplicated
  ) then
    raise exception 'La importación intenta actualizar el mismo producto más de una vez';
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
    'inventario', left(coalesce(p_source_file,'inventario.xlsx'),255), p_operation_key,
    'procesando', greatest(coalesce(p_total_rows,0),0),
    greatest(coalesce(p_unchanged_rows,0),0), v_user_id,
    jsonb_build_object('template','LIHEN-INVENTARIO-V1','started_at',now())
  ) returning * into v_batch;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_action := v_row->>'action';
    v_row_number := nullif(v_row->>'row_number','')::integer;
    v_product_id := nullif(v_row->>'product_id','')::uuid;
    v_sku := nullif(trim(v_row->>'sku'),'');
    v_expected := coalesce(v_row->'expected', '{}'::jsonb);
    v_changes := '{}'::jsonb;
    v_previous_cost := null;
    v_before_supplier_name := null;
    v_after_supplier_name := null;

    if v_row_number is null or v_row_number <= 0 then
      raise exception 'Número de fila inválido en la importación';
    end if;

    if v_action not in ('create','update') then
      raise exception 'Acción inválida en fila %', v_row_number;
    end if;

    if jsonb_typeof(v_expected) <> 'object' then
      raise exception 'El estado esperado no es válido en fila %', v_row_number;
    end if;

    if v_action = 'update' then
      if v_product_id is null then
        raise exception 'ID de producto obligatorio para actualizar en fila %', v_row_number;
      end if;

      select * into v_product
      from public.products
      where id = v_product_id
      for update;

      if not found then
        raise exception 'Producto no encontrado en fila %', v_row_number;
      end if;

      v_before_product := to_jsonb(v_product);
      v_previous_cost := v_product.current_cost;

      -- Control optimista por campo: evita que una vista previa obsoleta
      -- sobrescriba silenciosamente cambios hechos por otra sesión.
      foreach v_field in array array[
        'sku','business_line','category','subcategory','name','brand','description',
        'current_cost','sale_price','minimum_stock','visible_on_website','status','catalog_code'
      ]
      loop
        if v_expected ? v_field
           and (v_before_product -> v_field) is distinct from (v_expected -> v_field) then
          raise exception 'Conflicto de concurrencia en fila %, campo %: el producto cambió después de la vista previa',
            v_row_number, v_field;
        end if;
      end loop;

      if v_expected ? 'supplier_name' then
        select s.business_name into v_before_supplier_name
        from public.supplier_products sp
        join public.suppliers s on s.id = sp.supplier_id
        where sp.product_id = v_product.id
        order by sp.preferred desc, s.business_name asc
        limit 1;

        if to_jsonb(v_before_supplier_name) is distinct from (v_expected -> 'supplier_name') then
          raise exception 'Conflicto de concurrencia en fila %, campo supplier_name: el proveedor cambió después de la vista previa',
            v_row_number;
        end if;
      end if;

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

      v_after_product := to_jsonb(v_product);

      foreach v_field in array array[
        'sku','business_line','category','subcategory','name','brand','description',
        'current_cost','sale_price','minimum_stock','visible_on_website','status','catalog_code'
      ]
      loop
        if (v_before_product -> v_field) is distinct from (v_after_product -> v_field) then
          v_changes := v_changes || jsonb_build_object(
            v_field,
            jsonb_build_object('before', v_before_product -> v_field, 'after', v_after_product -> v_field)
          );
        end if;
      end loop;

      v_updated := v_updated + 1;
    else
      if v_sku is null then
        raise exception 'SKU obligatorio en fila %', v_row_number;
      end if;
      if nullif(trim(v_row->>'name'),'') is null then
        raise exception 'Nombre obligatorio en fila %', v_row_number;
      end if;
      if nullif(trim(v_row->>'business_line'),'') is null then
        raise exception 'Línea de negocio obligatoria en fila %', v_row_number;
      end if;
      if exists (
        select 1 from public.products p where lower(trim(p.sku)) = lower(trim(v_sku))
      ) then
        raise exception 'El SKU % ya existe; vuelve a generar la vista previa', v_sku;
      end if;

      insert into public.products(
        sku,name,business_line,category,subcategory,brand,description,current_cost,sale_price,
        minimum_stock,visible_on_website,status,catalog_code,created_by,updated_by
      ) values (
        v_sku,v_row->>'name',v_row->>'business_line',
        nullif(v_row->>'category',''),nullif(v_row->>'subcategory',''),nullif(v_row->>'brand',''),
        coalesce(nullif(v_row->>'description',''),(v_row->>'name')||'. Consulta disponibilidad por WhatsApp.'),
        nullif(v_row->>'current_cost','')::numeric,coalesce(nullif(v_row->>'sale_price','')::numeric,0),
        coalesce(nullif(v_row->>'minimum_stock','')::integer,0),
        coalesce(nullif(v_row->>'visible_on_website','')::boolean,false),
        coalesce(nullif(v_row->>'status','')::public.product_status,'activo'::public.product_status),
        nullif(v_row->>'catalog_code',''),v_user_id,v_user_id
      ) returning * into v_product;

      v_after_product := to_jsonb(v_product);
      foreach v_field in array array[
        'sku','business_line','category','subcategory','name','brand','description',
        'current_cost','sale_price','minimum_stock','visible_on_website','status','catalog_code'
      ]
      loop
        if (v_after_product -> v_field) <> 'null'::jsonb then
          v_changes := v_changes || jsonb_build_object(
            v_field,
            jsonb_build_object('before', null, 'after', v_after_product -> v_field)
          );
        end if;
      end loop;
      v_created := v_created + 1;
    end if;

    if v_row ? 'current_cost' and v_row->'current_cost' <> 'null'::jsonb
       and v_product.current_cost is distinct from v_previous_cost then
      insert into public.product_cost_import_history(
        product_id, import_batch_id, source_file, previous_cost, new_cost, changed_by
      ) values (
        v_product.id, v_batch.id, p_source_file, v_previous_cost, coalesce(v_product.current_cost,0), v_user_id
      );
      v_cost_changes := v_cost_changes + 1;
    end if;

    if v_row ? 'physical_stock' and v_row->'physical_stock' <> 'null'::jsonb then
      v_after_stock := (v_row->>'physical_stock')::integer;
      if v_after_stock < 0 then
        raise exception 'Stock negativo en fila %', v_row_number;
      end if;

      select * into v_inventory
      from public.inventory
      where product_id = v_product.id and variant_id is null
      for update;

      if found then
        v_before_stock := v_inventory.physical_stock;

        if v_expected ? 'physical_stock'
           and to_jsonb(v_before_stock) is distinct from (v_expected -> 'physical_stock') then
          raise exception 'Conflicto de concurrencia en fila %, campo physical_stock: el stock cambió después de la vista previa',
            v_row_number;
        end if;

        if v_after_stock < v_inventory.reserved_stock then
          raise exception 'El stock de % no puede ser menor al reservado', v_product.sku;
        end if;

        update public.inventory
        set physical_stock = v_after_stock,
            last_counted_at = now(),
            updated_by = v_user_id
        where id = v_inventory.id
        returning * into v_inventory;
      else
        v_before_stock := 0;

        if v_action = 'update' and v_expected ? 'physical_stock'
           and to_jsonb(0) is distinct from (v_expected -> 'physical_stock') then
          raise exception 'Conflicto de concurrencia en fila %, campo physical_stock: el inventario cambió después de la vista previa',
            v_row_number;
        end if;

        insert into public.inventory(
          product_id,physical_stock,reserved_stock,pending_stock,average_cost,last_counted_at,updated_by
        ) values (
          v_product.id,v_after_stock,0,0,coalesce(v_product.current_cost,0),now(),v_user_id
        ) returning * into v_inventory;
      end if;

      if v_before_stock <> v_after_stock then
        v_changes := v_changes || jsonb_build_object(
          'physical_stock',
          jsonb_build_object('before', to_jsonb(v_before_stock), 'after', to_jsonb(v_after_stock))
        );

        insert into public.inventory_movements(
          inventory_id,movement_type,quantity,physical_before,physical_after,
          reserved_before,reserved_after,reason,performed_by
        ) values (
          v_inventory.id,
          case when v_after_stock > v_before_stock
            then 'ajuste_positivo'::public.inventory_movement_type
            else 'ajuste_negativo'::public.inventory_movement_type
          end,
          abs(v_after_stock-v_before_stock),v_before_stock,v_after_stock,
          v_inventory.reserved_stock,v_inventory.reserved_stock,
          'Importación LIHEN-INVENTARIO-V1: '||coalesce(p_source_file,'archivo'),v_user_id
        );
        v_stock_changes := v_stock_changes + 1;
      end if;
      v_stock_units_after := v_stock_units_after + v_after_stock;
    end if;

    if nullif(trim(v_row->>'supplier_name'),'') is not null then
      -- Si no se consultó el proveedor antes por control optimista, obtenerlo
      -- ahora para poder registrar el cambio real.
      if v_before_supplier_name is null and v_action = 'update' then
        select s.business_name into v_before_supplier_name
        from public.supplier_products sp
        join public.suppliers s on s.id = sp.supplier_id
        where sp.product_id = v_product.id
        order by sp.preferred desc, s.business_name asc
        limit 1;
      end if;

      select * into v_supplier
      from public.suppliers
      where lower(trim(business_name)) = lower(trim(v_row->>'supplier_name'))
        and active = true
      limit 1;

      if found then
        select exists(
          select 1 from public.supplier_products
          where product_id = v_product.id and preferred = true
        ) into v_has_preferred_supplier;

        if exists (
          select 1 from public.supplier_products
          where supplier_id = v_supplier.id and product_id = v_product.id
        ) then
          update public.supplier_products
          set last_cost = coalesce(v_product.current_cost,last_cost)
          where supplier_id = v_supplier.id and product_id = v_product.id;
        else
          insert into public.supplier_products(supplier_id,product_id,last_cost,preferred)
          values(v_supplier.id,v_product.id,v_product.current_cost,not v_has_preferred_supplier);
        end if;

        select s.business_name into v_after_supplier_name
        from public.supplier_products sp
        join public.suppliers s on s.id = sp.supplier_id
        where sp.product_id = v_product.id
        order by sp.preferred desc, s.business_name asc
        limit 1;

        if to_jsonb(v_before_supplier_name) is distinct from to_jsonb(v_after_supplier_name) then
          v_changes := v_changes || jsonb_build_object(
            'supplier_name',
            jsonb_build_object('before', to_jsonb(v_before_supplier_name), 'after', to_jsonb(v_after_supplier_name))
          );
        end if;
      else
        v_pending_supplier := v_pending_supplier + 1;
      end if;
    end if;

    insert into public.import_batch_rows(
      batch_id,row_number,product_id,sku,action,status,changes
    ) values (
      v_batch.id,v_row_number,v_product.id,v_product.sku,
      case when v_action='create' then 'crear' else 'actualizar' end,
      'aplicado',v_changes
    );
  end loop;

  update public.import_batches set
    status = 'completado',
    created_rows = v_created,
    updated_rows = v_updated,
    skipped_rows = greatest(coalesce(p_unchanged_rows,0),0),
    error_rows = 0,
    summary = jsonb_build_object(
      'template','LIHEN-INVENTARIO-V1',
      'created_rows',v_created,
      'updated_rows',v_updated,
      'unchanged_rows',greatest(coalesce(p_unchanged_rows,0),0),
      'stock_changes',v_stock_changes,
      'cost_changes',v_cost_changes,
      'stock_units_after',v_stock_units_after,
      'pending_supplier_links',v_pending_supplier,
      'completed_at',now()
    )
  where id = v_batch.id
  returning * into v_batch;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(
    v_user_id,
    'importar_inventario_lihen_v1',
    'import_batches',
    v_batch.id::text,
    v_batch.summary,
    jsonb_build_object('source_file',p_source_file,'operation_key',p_operation_key)
  );

  return jsonb_build_object(
    'batch_id',v_batch.id,
    'idempotent',false,
    'summary',v_batch.summary
  );
end;
$$;

revoke all on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
from public, anon;
grant execute on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
to authenticated;

comment on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb)
is 'Importación LIHEN-INVENTARIO-V1 atómica e idempotente. Fase 9 añade trazabilidad before/after y control optimista por campo para evitar sobrescrituras desde vistas previas obsoletas.';

commit;
