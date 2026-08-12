-- Rollback Fase 8 — no elimina datos históricos.
begin;

drop policy if exists inventory_movements_select_active_cofounder on public.inventory_movements;

alter table public.inventory_movements
  drop constraint if exists inventory_movements_quantity_positive,
  drop constraint if exists inventory_movements_snapshots_nonnegative,
  drop constraint if exists inventory_movements_reserved_not_above_physical,
  drop constraint if exists inventory_movements_direction_consistent;

-- Restaura el permiso anterior de la migración 007.
grant select, insert on public.inventory_movements to authenticated;
revoke all on public.inventory_movements from anon;

commit;
