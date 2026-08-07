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
