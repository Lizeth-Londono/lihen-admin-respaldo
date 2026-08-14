begin;

drop trigger if exists trg_products_catalog_code_friendly_unique on public.products;
drop function if exists public.guard_unique_product_catalog_code();

commit;
