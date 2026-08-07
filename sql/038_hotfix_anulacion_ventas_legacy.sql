-- ============================================================
-- LIHEN ADMIN — HOTFIX 038
-- Anulación segura de ventas rápidas antiguas (legacy)
-- Fecha: 2026-08-07
--
-- Objetivos:
-- 1) Permitir anular ventas antiguas que nunca generaron movimiento financiero.
-- 2) Reutilizar/reconectar un movimiento financiero real si existe pero la venta perdió el vínculo.
-- 3) Evitar doble devolución de inventario y doble reversión financiera.
-- 4) Conservar trazabilidad: la venta permanece registrada como 'anulada'.
--
-- Requisito: migraciones de LIHEN ADMIN instaladas hasta la 033 o posteriores.
-- ============================================================

begin;

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
  v_financial_legacy boolean := false;
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if p_operation_key is null or length(trim(p_operation_key)) < 8 then
    raise exception 'Clave de operación inválida';
  end if;

  if p_reason is null or length(trim(p_reason)) < 8 then
    raise exception 'Escribe un motivo claro de al menos 8 caracteres';
  end if;

  select *
    into v_sale
    from public.quick_sales
   where id = p_sale_id
   for update;

  if not found then
    raise exception 'Venta no encontrada';
  end if;

  -- Idempotencia fuerte aun cuando el frontend genere una clave distinta
  -- en un segundo intento: una venta ya anulada jamás repone stock ni caja otra vez.
  if v_sale.status = 'anulada' then
    return jsonb_build_object(
      'sale_id', v_sale.id,
      'status', v_sale.status,
      'already_cancelled', true,
      'idempotent', true
    );
  end if;

  -- 1. Intentar recuperar el movimiento financiero enlazado explícitamente.
  if v_sale.financial_movement_id is not null then
    select *
      into v_original
      from public.financial_movements
     where id = v_sale.financial_movement_id
     for update;
  end if;

  -- 2. Compatibilidad: si se perdió el vínculo, buscar un movimiento real de la venta.
  if not found or v_original.id is null then
    select *
      into v_original
      from public.financial_movements
     where source_type = 'quick_sale'
       and source_id = v_sale.id
       and category = 'venta_rapida'
     order by occurred_at desc, created_at desc
     limit 1
     for update;
  end if;

  -- 3. Si existe un movimiento real, reparar el enlace de la venta antes de revertir.
  if v_original.id is not null then
    if v_sale.financial_account_id is null
       or v_sale.financial_movement_id is null
       or v_sale.financial_account_id <> v_original.account_id
       or v_sale.financial_movement_id <> v_original.id then
      update public.quick_sales
         set financial_account_id = v_original.account_id,
             financial_movement_id = v_original.id,
             updated_at = now()
       where id = v_sale.id
       returning * into v_sale;
    end if;
  else
    v_financial_legacy := true;
  end if;

  -- 4. Venta histórica sin movimiento financiero: se anula inventario/venta,
  -- pero NO se inventa ni se fuerza un movimiento de caja inexistente.
  if v_financial_legacy then
    v_result := public.cancel_quick_sale_atomic_idempotent(
      p_operation_key,
      p_sale_id,
      p_reason
    );

    return v_result || jsonb_build_object(
      'financial_legacy', true,
      'financial_reversal', null,
      'financial_note', 'Venta anulada sin reversión financiera porque no existía movimiento financiero original.'
    );
  end if;

  -- 5. Si el movimiento financiero original ya estaba reversado por una corrección previa,
  -- solo completar la anulación operativa; no crear otro egreso.
  if v_original.status = 'reversado' then
    v_result := public.cancel_quick_sale_atomic_idempotent(
      p_operation_key,
      p_sale_id,
      p_reason
    );

    return v_result || jsonb_build_object(
      'financial_legacy', false,
      'financial_already_reversed', true,
      'financial_reversal', null
    );
  end if;

  -- 6. Reintento con la misma clave: si la reversión ya existe, no repetirla.
  select *
    into v_reverse
    from public.financial_movements
   where operation_key = v_reverse_key;

  if found then
    return jsonb_build_object(
      'sale_id', p_sale_id,
      'financial_reversal', to_jsonb(v_reverse),
      'idempotent', true
    );
  end if;

  select *
    into v_account
    from public.financial_accounts
   where id = v_original.account_id
   for update;

  if not found then
    raise exception 'La venta tiene un movimiento financiero, pero la cuenta asociada ya no existe';
  end if;

  if v_account.current_balance < v_sale.total then
    raise exception 'Saldo insuficiente en la cuenta para anular esta venta';
  end if;

  -- Esta RPC base repone inventario, marca la venta como anulada y registra auditoría.
  -- Al ejecutarse dentro de esta misma función, todo queda dentro de una sola transacción.
  v_result := public.cancel_quick_sale_atomic_idempotent(
    p_operation_key,
    p_sale_id,
    p_reason
  );

  insert into public.financial_movements(
    account_id,
    movement_type,
    amount,
    balance_before,
    balance_after,
    category,
    description,
    source_type,
    source_id,
    operation_key,
    performed_by,
    created_by,
    occurred_at
  ) values (
    v_account.id,
    'egreso',
    v_sale.total,
    v_account.current_balance,
    v_account.current_balance - v_sale.total,
    'anulacion_venta',
    'Reintegro por anulación de ' || v_sale.sale_number,
    'quick_sale',
    v_sale.id,
    v_reverse_key,
    auth.uid(),
    auth.uid(),
    now()
  )
  returning * into v_reverse;

  update public.financial_accounts
     set current_balance = v_reverse.balance_after,
         updated_by = auth.uid(),
         updated_at = now()
   where id = v_account.id;

  update public.financial_movements
     set status = 'reversado'
   where id = v_original.id
     and status = 'activo';

  return v_result || jsonb_build_object(
    'financial_legacy', false,
    'financial_reversal', to_jsonb(v_reverse)
  );
end;
$$;

revoke all on function public.cancel_quick_sale_financial_atomic_idempotent(text,uuid,text) from public, anon;
grant execute on function public.cancel_quick_sale_financial_atomic_idempotent(text,uuid,text) to authenticated;

commit;

-- ============================================================
-- DIAGNÓSTICO POST-INSTALACIÓN (solo lectura)
-- Puedes ejecutar estas consultas después del bloque anterior.
-- ============================================================

-- Resumen general de ventas rápidas:
select
  count(*) as ventas_totales,
  count(*) filter (where status='completada') as ventas_activas,
  count(*) filter (where status='anulada') as ventas_anuladas,
  count(*) filter (where financial_movement_id is not null) as ventas_con_vinculo_financiero,
  count(*) filter (where financial_movement_id is null) as ventas_sin_vinculo_financiero
from public.quick_sales;

-- Ventas activas que no tienen vínculo financiero y son candidatas a ser legacy:
select
  qs.id,
  qs.sale_number,
  qs.created_at,
  qs.total,
  qs.payment_method,
  qs.financial_account_id,
  qs.financial_movement_id
from public.quick_sales qs
where qs.status='completada'
  and qs.financial_movement_id is null
order by qs.created_at desc;

-- Ventas sin items (posible inconsistencia de datos):
select
  qs.id,
  qs.sale_number,
  qs.status,
  qs.created_at
from public.quick_sales qs
left join public.quick_sale_items qsi on qsi.sale_id=qs.id
where qsi.id is null
order by qs.created_at desc;

-- Ventas con movimiento financiero real existente pero vínculo incompleto:
select
  qs.id,
  qs.sale_number,
  qs.financial_account_id,
  qs.financial_movement_id,
  fm.id as movimiento_detectado,
  fm.account_id as cuenta_detectada,
  fm.status as estado_movimiento
from public.quick_sales qs
join public.financial_movements fm
  on fm.source_type='quick_sale'
 and fm.source_id=qs.id
 and fm.category='venta_rapida'
where qs.financial_movement_id is null
   or qs.financial_account_id is null
   or qs.financial_movement_id <> fm.id
   or qs.financial_account_id <> fm.account_id
order by qs.created_at desc;
