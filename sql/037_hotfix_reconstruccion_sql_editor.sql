-- ============================================================
-- LIHEN ADMIN — MIGRACIÓN 037
-- HOTFIX: permitir la reconstrucción administrativa desde
-- Supabase SQL Editor (Role: postgres), sin abrir el RPC a anon.
--
-- USAR cuando 034 ya fue ejecutado con una versión anterior y
-- apply_operational_reconstruction(...) devuelve:
--   ERROR P0001: Acceso no autorizado
--
-- No modifica inventario ni Caja por sí sola. Solo reemplaza la
-- función. Después se vuelve al PASO C de 035.
-- ============================================================

begin;

create or replace function public.apply_operational_reconstruction(
  p_operation_key text,
  p_description text default 'Restauración de ventas y pedidos previos al corte operativo'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_sql_editor_admin boolean := (auth.uid() is null and session_user = 'postgres');
  v_run public.operational_reconstruction_runs;
  v_row record;
  v_inventory public.inventory;
  v_qs_count integer := 0;
  v_order_count integer := 0;
  v_physical bigint := 0;
  v_reserved bigint := 0;
  v_preview jsonb;
begin
  -- Desde la aplicación se exige una cofundadora activa. Desde Supabase SQL
  -- Editor se permite exclusivamente la sesión postgres y se atribuye la
  -- operación a la primera cofundadora activa para conservar las FK/auditoría.
  if v_sql_editor_admin then
    select id into v_user
    from public.profiles
    where active=true and role='cofundadora'
    order by created_at
    limit 1;

    if v_user is null then
      raise exception 'No existe una cofundadora activa para atribuir la reconstrucción';
    end if;
  elsif not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if coalesce(length(trim(p_operation_key)),0) < 12 then raise exception 'Clave de operación inválida'; end if;

  select * into v_run from public.operational_reconstruction_runs where operation_key=p_operation_key for update;
  if found then
    if v_run.status='aplicada' then
      return jsonb_build_object('run',to_jsonb(v_run),'idempotent',true);
    end if;
    raise exception 'Existe una reconstrucción con esta clave en estado %',v_run.status;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
    into v_preview
  from public.preview_operational_reconstruction() x;

  insert into public.operational_reconstruction_runs(operation_key,status,description,preview_snapshot,created_by)
  values(p_operation_key,'preparada',p_description,v_preview,v_user)
  returning * into v_run;

  -- Restaurar unidades físicas de ventas rápidas completadas.
  for v_row in
    select i.id inventory_id, sum(qsi.quantity)::integer qty,
           string_agg(distinct qs.sale_number, ', ' order by qs.sale_number) refs
    from public.quick_sales qs
    join public.quick_sale_items qsi on qsi.sale_id=qs.id
    join public.inventory i on i.product_id=qsi.product_id
      and ((i.variant_id is null and qsi.variant_id is null) or i.variant_id=qsi.variant_id)
    where qs.status='completada' and coalesce(qs.reconstruction_archived,false)=false
    group by i.id
  loop
    select * into v_inventory from public.inventory where id=v_row.inventory_id for update;
    insert into public.inventory_movements(
      inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
    ) values(
      v_inventory.id,'ajuste_positivo',v_row.qty,v_inventory.physical_stock,v_inventory.physical_stock+v_row.qty,
      v_inventory.reserved_stock,v_inventory.reserved_stock,
      'Reconstrucción operativa '||v_run.id::text||' · devolución de ventas rápidas: '||left(v_row.refs,400),v_user
    );
    update public.inventory set physical_stock=physical_stock+v_row.qty,updated_by=v_user where id=v_inventory.id;
    v_physical := v_physical + v_row.qty;
  end loop;

  -- Restaurar efecto neto de pedidos: ventas entregadas vuelven a físico y
  -- reservas aún abiertas se liberan. Se deriva de inventory_movements para
  -- soportar ediciones, recepciones y cierres directos antiguos.
  for v_row in
    select im.inventory_id,
      coalesce(sum(case when im.movement_type='salida_venta' then im.quantity else 0 end),0)::integer physical_restore,
      greatest(0,
        coalesce(sum(case when im.movement_type='reserva_pedido' then im.quantity else 0 end),0)
        - coalesce(sum(case when im.movement_type='liberacion_reserva' then im.quantity else 0 end),0)
        - coalesce(sum(case when im.movement_type='salida_venta' then im.quantity else 0 end),0)
      )::integer reservation_release,
      string_agg(distinct o.order_number, ', ' order by o.order_number) refs
    from public.inventory_movements im
    join public.orders o on o.id=im.order_id
    where im.order_id is not null
      and coalesce(o.reconstruction_archived,false)=false
      and o.status <> 'cancelado'::public.order_status
    group by im.inventory_id
  loop
    select * into v_inventory from public.inventory where id=v_row.inventory_id for update;

    if v_row.physical_restore > 0 then
      insert into public.inventory_movements(
        inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
      ) values(
        v_inventory.id,'ajuste_positivo',v_row.physical_restore,
        v_inventory.physical_stock,v_inventory.physical_stock+v_row.physical_restore,
        v_inventory.reserved_stock,v_inventory.reserved_stock,
        'Reconstrucción operativa '||v_run.id::text||' · devolución de pedidos: '||left(v_row.refs,400),v_user
      );
      update public.inventory set physical_stock=physical_stock+v_row.physical_restore,updated_by=v_user where id=v_inventory.id;
      v_physical := v_physical + v_row.physical_restore;
      select * into v_inventory from public.inventory where id=v_row.inventory_id for update;
    end if;

    if v_row.reservation_release > 0 then
      if v_inventory.reserved_stock < v_row.reservation_release then
        raise exception 'Inconsistencia: reserva actual % menor que reserva a liberar % en inventario %',v_inventory.reserved_stock,v_row.reservation_release,v_inventory.id;
      end if;
      insert into public.inventory_movements(
        inventory_id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after,reason,performed_by
      ) values(
        v_inventory.id,'liberacion_reserva',v_row.reservation_release,
        v_inventory.physical_stock,v_inventory.physical_stock,
        v_inventory.reserved_stock,v_inventory.reserved_stock-v_row.reservation_release,
        'Reconstrucción operativa '||v_run.id::text||' · liberación de reservas de pedidos: '||left(v_row.refs,400),v_user
      );
      update public.inventory set reserved_stock=reserved_stock-v_row.reservation_release,updated_by=v_user where id=v_inventory.id;
      v_reserved := v_reserved + v_row.reservation_release;
    end if;
  end loop;

  select count(*) into v_qs_count from public.quick_sales where coalesce(reconstruction_archived,false)=false;
  select count(*) into v_order_count from public.orders where coalesce(reconstruction_archived,false)=false;

  -- Conservar registros antiguos, pero archivarlos del flujo operativo.
  update public.quick_sales
     set reconstruction_archived=true,reconstruction_run_id=v_run.id
   where coalesce(reconstruction_archived,false)=false;

  update public.orders
     set reconstruction_archived=true,reconstruction_run_id=v_run.id
   where coalesce(reconstruction_archived,false)=false;

  -- NO tocar saldos. Solo excluir de reportes los movimientos financieros
  -- asociados a registros archivados para evitar doble contabilización visual.
  update public.financial_movements fm
     set reporting_excluded=true,
         reporting_exclusion_reason='Incluido en saldo de corte; transacción archivada por reconstrucción '||v_run.id::text
   where coalesce(fm.reporting_excluded,false)=false
     and (
       (fm.source_type='quick_sale' and exists(select 1 from public.quick_sales qs where qs.id=fm.source_id and qs.reconstruction_run_id=v_run.id))
       or
       (fm.source_type='order' and exists(select 1 from public.orders o where o.id=fm.source_id and o.reconstruction_run_id=v_run.id))
     );

  update public.operational_reconstruction_runs
     set status='aplicada',quick_sales_archived=v_qs_count,orders_archived=v_order_count,
         physical_units_restored=v_physical,reserved_units_released=v_reserved,
         financial_accounts_changed=false,applied_by=v_user,applied_at=now()
   where id=v_run.id
   returning * into v_run;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,new_data,details)
  values(v_user,'reconstruccion_operativa','operational_reconstruction_runs',v_run.id::text,to_jsonb(v_run),
    jsonb_build_object('financial_accounts_changed',false,'preview',v_preview));

  return jsonb_build_object('run',to_jsonb(v_run),'idempotent',false);
exception when others then
  -- La transacción completa hace rollback, por lo cual nunca quedan saldos o
  -- inventarios a medias.
  raise;
end;
$$;

revoke all on function public.apply_operational_reconstruction(text,text) from public,anon;
grant execute on function public.apply_operational_reconstruction(text,text) to authenticated;

commit;

-- Verificación: debe devolver una fila con la firma instalada.
select p.oid::regprocedure::text as funcion_instalada
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='apply_operational_reconstruction';
