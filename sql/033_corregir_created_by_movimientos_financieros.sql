-- LIHEN.CO - Corrección de created_by en movimientos financieros
-- Ejecutar UNA sola vez después de las migraciones 026-032.
-- No modifica saldos existentes ni crea movimientos falsos.
begin;

alter table if exists public.financial_movements
  alter column created_by set default auth.uid();

create or replace function public.set_financial_movement_created_by()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.created_by := coalesce(new.created_by, new.performed_by, auth.uid());

  if new.created_by is null then
    raise exception 'No fue posible identificar al usuario que registra el movimiento financiero';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_financial_movements_created_by
on public.financial_movements;

create trigger trg_financial_movements_created_by
before insert on public.financial_movements
for each row
execute function public.set_financial_movement_created_by();

create or replace function public.configure_initial_balance_atomic(
  p_account_id uuid,
  p_amount numeric,
  p_effective_date date,
  p_reason text,
  p_operation_key text
)
returns public.financial_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.financial_accounts;
  v_user uuid := auth.uid();
begin
  if not public.is_active_cofounder() then
    raise exception 'Acceso no autorizado';
  end if;

  if v_user is null then
    raise exception 'No fue posible identificar al usuario autenticado';
  end if;

  if p_amount < 0 then
    raise exception 'Saldo inválido';
  end if;

  select * into v
  from public.financial_accounts
  where id = p_account_id
  for update;

  if not found or not v.active then
    raise exception 'Cuenta no disponible';
  end if;

  if v.initial_balance_configured then
    raise exception 'El saldo inicial ya fue configurado';
  end if;

  update public.financial_accounts
  set initial_balance = p_amount,
      current_balance = p_amount,
      initial_balance_date = p_effective_date,
      initial_balance_configured = true,
      updated_by = v_user,
      updated_at = now()
  where id = v.id
  returning * into v;

  if p_amount > 0 then
    insert into public.financial_movements(
      account_id,
      movement_type,
      amount,
      balance_before,
      balance_after,
      category,
      description,
      operation_key,
      performed_by,
      created_by,
      occurred_at
    ) values (
      v.id,
      'saldo_inicial',
      p_amount,
      0,
      p_amount,
      'saldo_inicial',
      p_reason,
      p_operation_key,
      v_user,
      v_user,
      coalesce(p_effective_date, current_date)::timestamptz
    );
  end if;

  return v;
end;
$$;

revoke all on function public.configure_initial_balance_atomic(uuid,numeric,date,text,text) from public, anon;
grant execute on function public.configure_initial_balance_atomic(uuid,numeric,date,text,text) to authenticated;

commit;
