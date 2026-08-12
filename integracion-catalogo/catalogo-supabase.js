// Adaptador para el catálogo público de LIHEN.CO.
// Consulta exclusivamente la vista pública catalog_public.
const SUPABASE_URL='https://admhxolrhhipwcxbtyhl.supabase.co';
const SUPABASE_KEY='sb_publishable_lBc4zpIyG9PE58hXV0iYfA_8NUBKY4Z';

function money(value){return new Intl.NumberFormat('es-CO',{style:'currency',currency:'COP',maximumFractionDigits:0}).format(Number(value||0));}
function normalize(row){
  const variant=row.variants?.[0]||{};
  return {
    id:row.catalog_code||row.id,
    line:row.business_line||'',
    category:row.category||'',
    name:row.name||'',
    brand:row.brand||'',
    price:money(row.sale_price),
    availability:row.catalog_availability_text||'Consulta disponibilidad por WhatsApp',
    desc:row.description||'',
    images:(row.images||[]).map(x=>x.public_url||x.storage_path).filter(Boolean),
    size:variant.size||'Por confirmar',
    color:variant.color||variant.tone||'Por confirmar',
    tag:'Producto disponible',
    searchText:[row.name,row.brand,row.category,row.business_line].filter(Boolean).join(' ').toLowerCase()
  };
}
export async function loadPublicProducts(){
  const response=await fetch(`${SUPABASE_URL}/rest/v1/catalog_public?select=*`,{headers:{apikey:SUPABASE_KEY,Authorization:`Bearer ${SUPABASE_KEY}`}});
  if(!response.ok) throw new Error(`No se pudo cargar el catálogo (${response.status})`);
  return (await response.json()).map(normalize);
}
