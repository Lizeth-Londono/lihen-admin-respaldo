-- ============================================================
-- ROLLBACK CONTROLADO — MIGRACIÓN 046
-- ADVERTENCIA: solo ejecutar si NO existen pagos payment_source='external'.
-- Si existen, detener y diseñar reversión contable específica.
-- ============================================================

begin;

do $$
begin
  if exists (
    select 1 from public.supplier_payments where payment_source='external'
  ) then
    raise exception 'ROLLBACK BLOQUEADO: existen pagos externos. No pueden convertirse automáticamente en salidas de caja LIHEN.';
  end if;
end $$;

-- Elimina la RPC nueva. La firma histórica deberá restaurarse desde la
-- migración anterior que corresponda al ambiente real.
drop function if exists public.register_supplier_payment_v2_atomic(uuid,uuid,text,numeric,text,timestamptz,text,text,text);

alter table public.supplier_payments drop constraint if exists supplier_payments_source_consistency;
alter table public.supplier_payments drop constraint if exists supplier_payments_payment_source_allowed;
drop index if exists public.supplier_payments_source_date_idx;

-- No se restaura NOT NULL a ciegas: instalaciones legacy pueden tener
-- financial_movement_id nullable. El rollback conserva esos datos y elimina
-- únicamente la capacidad de registrar pagos externos nuevos.
alter table public.supplier_payments drop column if exists payment_source;

commit;
