-- ============================================================
-- LIHEN ADMIN — FASE 8
-- Endurecimiento de inventory_movements y trazabilidad
-- Fecha: 2026-08-11
-- ============================================================

begin;

-- Los movimientos son bitácora operacional: la app cliente no debe poder
-- insertarlos/modificarlos directamente. Las RPC SECURITY DEFINER autorizadas
-- continúan registrándolos dentro de la misma transacción de negocio.
revoke insert, update, delete on public.inventory_movements from authenticated, anon;
grant select on public.inventory_movements to authenticated;
revoke all on public.inventory_movements from anon;

alter table public.inventory_movements enable row level security;

drop policy if exists inventory_movements_select_active_cofounder on public.inventory_movements;
create policy inventory_movements_select_active_cofounder
on public.inventory_movements
for select
to authenticated
using (public.is_active_cofounder());

-- Invariantes de auditoría. Se usan NOT VALID para no bloquear el despliegue
-- por registros históricos; nuevas escrituras sí deben cumplirlos.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.inventory_movements'::regclass
      and conname='inventory_movements_quantity_positive'
  ) then
    alter table public.inventory_movements
      add constraint inventory_movements_quantity_positive
      check (quantity > 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.inventory_movements'::regclass
      and conname='inventory_movements_snapshots_nonnegative'
  ) then
    alter table public.inventory_movements
      add constraint inventory_movements_snapshots_nonnegative
      check (
        physical_before >= 0 and physical_after >= 0
        and reserved_before >= 0 and reserved_after >= 0
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.inventory_movements'::regclass
      and conname='inventory_movements_reserved_not_above_physical'
  ) then
    alter table public.inventory_movements
      add constraint inventory_movements_reserved_not_above_physical
      check (
        reserved_before <= physical_before
        and reserved_after <= physical_after
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.inventory_movements'::regclass
      and conname='inventory_movements_direction_consistent'
  ) then
    alter table public.inventory_movements
      add constraint inventory_movements_direction_consistent
      check (
        case movement_type::text
          when 'reserva_pedido' then physical_after = physical_before and reserved_after >= reserved_before
          when 'liberacion_reserva' then physical_after = physical_before and reserved_after <= reserved_before
          when 'salida_venta' then physical_after <= physical_before and reserved_after <= reserved_before
          when 'entrada_compra' then physical_after >= physical_before and reserved_after = reserved_before
          when 'ajuste_positivo' then physical_after >= physical_before
          when 'ajuste_negativo' then physical_after <= physical_before
          else true
        end
      ) not valid;
  end if;
end $$;

comment on table public.inventory_movements is
'Bitácora append-only de cambios de inventario. Las escrituras deben realizarse mediante RPC transaccionales autorizadas.';

commit;

-- ============================================================
-- DIAGNÓSTICO PRE-VALIDACIÓN (solo lectura)
-- Ejecutar en producción antes de VALIDATE CONSTRAINT.
-- ============================================================
-- select id,movement_type,quantity,physical_before,physical_after,reserved_before,reserved_after
-- from public.inventory_movements
-- where quantity <= 0
--    or physical_before < 0 or physical_after < 0
--    or reserved_before < 0 or reserved_after < 0
--    or reserved_before > physical_before
--    or reserved_after > physical_after;
--
-- Si devuelve 0 filas, validar:
-- alter table public.inventory_movements validate constraint inventory_movements_quantity_positive;
-- alter table public.inventory_movements validate constraint inventory_movements_snapshots_nonnegative;
-- alter table public.inventory_movements validate constraint inventory_movements_reserved_not_above_physical;
-- alter table public.inventory_movements validate constraint inventory_movements_direction_consistent;
