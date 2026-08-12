-- ============================================================
-- LIHEN ADMIN — ROLLBACK 043
-- Restaura import_inventory_batch_atomic() a la versión previa
-- de compatibilidad LIHEN-INVENTARIO-V1 (migración 032).
-- No elimina datos ni lotes históricos.
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
    'inventario', left(coalesce(p_source_file,'inventario.xlsx'),255), p_operation_key, 'procesando', greatest(coalesce(p_total_rows,0),0),
    greatest(coalesce(p_unchanged_rows,0),0), v_user_id,
    jsonb_build_object('template','LIHEN-INVENTARIO-V1','started_at',now())
  ) returning * into v_batch;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_action := v_row->>'action';
    v_product_id := nullif(v_row->>'product_id','')::uuid;
    v_sku := nullif(trim(v_row->>'sku'),'');
    v_changes := '{}'::jsonb;
    v_previous_cost := null;

    if v_action not in ('create','update') then
      raise exception 'Acción inválida en fila %', v_row->>'row_number';
    end if;

    if v_action = 'update' then
      select * into v_product from public.products where id = v_product_id for update;
      if not found then raise exception 'Producto no encontrado en fila %', v_row->>'row_number'; end if;
      v_previous_cost := v_product.current_cost;

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
      if nullif(trim(v_row->>'business_line'),'') is null then raise exception 'Línea de negocio obligatoria en fila %', v_row->>'row_number'; end if;
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
          'Importación LIHEN-INVENTARIO-V1: '||coalesce(p_source_file,'archivo'),v_user_id
        );
        v_stock_changes := v_stock_changes + 1;
      end if;
      v_stock_units_after := v_stock_units_after + v_after_stock;
    end if;

    if nullif(trim(v_row->>'supplier_name'),'') is not null then
      select * into v_supplier from public.suppliers
      where lower(trim(business_name))=lower(trim(v_row->>'supplier_name')) and active=true limit 1;
      if found then
        select exists(
          select 1 from public.supplier_products
          where product_id=v_product.id and preferred=true
        ) into v_has_preferred_supplier;

        if exists (
          select 1 from public.supplier_products
          where supplier_id=v_supplier.id and product_id=v_product.id
        ) then
          update public.supplier_products
          set last_cost=coalesce(v_product.current_cost,last_cost)
          where supplier_id=v_supplier.id and product_id=v_product.id;
        else
          insert into public.supplier_products(supplier_id,product_id,last_cost,preferred)
          values(v_supplier.id,v_product.id,v_product.current_cost,not v_has_preferred_supplier);
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
      'template','LIHEN-INVENTARIO-V1',
      'created_rows',v_created,'updated_rows',v_updated,
      'unchanged_rows',greatest(coalesce(p_unchanged_rows,0),0),
      'stock_changes',v_stock_changes,'cost_changes',v_cost_changes,
      'stock_units_after',v_stock_units_after,
      'pending_supplier_links',v_pending_supplier,'completed_at',now()
    )
  where id=v_batch.id returning * into v_batch;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(v_user_id,'importar_inventario_lihen_v1','import_batches',v_batch.id::text,
    v_batch.summary,jsonb_build_object('source_file',p_source_file,'operation_key',p_operation_key));

  return jsonb_build_object('batch_id',v_batch.id,'idempotent',false,'summary',v_batch.summary);
end;
$$;

revoke all on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb) from public, anon;
grant execute on function public.import_inventory_batch_atomic(text,text,integer,integer,jsonb) to authenticated;

commit;
