from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
CSS = (ROOT / "css" / "app.css").read_text(encoding="utf-8")
VIEWPORTS = [(1920,1080),(1366,768),(1280,720),(1024,600),(768,1024)]

HTML = """<!doctype html><html><head><meta charset='utf-8'><style>{css}</style></head>
<body><div class='modal-backdrop'><article class='modal wide'><header><div><b>LIHEN ADMIN</b><h2>Nueva venta rápida</h2></div><button type='button'>×</button></header>
<div class='modal-body'><form class='quick-sale-form'>
<section><label>Cliente<input></label><label>Modo<select><option>Venta actual</option></select></label></section>
<section><h3>Agregar producto</h3><input placeholder='Buscar producto'><button type='button'>+ Agregar</button></section>
<section><h3>Productos vendidos</h3><div class='sale-items-list'>{items}</div></section>
<section><label>Método de pago<select><option>Efectivo</option></select></label><label>Observaciones<textarea rows='6'></textarea></label></section>
<div class='form-actions'><button type='button'>Cancelar</button><button id='save' type='submit'>Guardar venta</button></div>
</form></div></article></div></body></html>"""
ITEM = "<div class='sale-item-card'><div><b>Producto de prueba</b><small>SKU BC-001</small></div><label>Cantidad<input value='1'></label><label>Precio<input value='25000'></label><strong>$25.000</strong><button type='button'>×</button></div>"

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, executable_path='/usr/bin/chromium', args=['--no-sandbox'])
        try:
            for w,h in VIEWPORTS:
                page = browser.new_page(viewport={"width":w,"height":h})
                page.set_content(HTML.format(css=CSS, items=ITEM*15), wait_until='load')
                body = page.locator('.modal-body')
                m0 = body.evaluate("e => ({clientHeight:e.clientHeight,scrollHeight:e.scrollHeight,scrollTop:e.scrollTop,overflowY:getComputedStyle(e).overflowY,minHeight:getComputedStyle(e).minHeight})")
                assert m0['scrollHeight'] > m0['clientHeight'], (w,h,m0)
                assert m0['overflowY'] == 'auto', (w,h,m0)
                body.hover()
                page.mouse.wheel(0, 700)
                page.wait_for_timeout(80)
                down = body.evaluate('e => e.scrollTop')
                assert down > 0, (w,h,down)
                page.mouse.wheel(0, -350)
                page.wait_for_timeout(80)
                up = body.evaluate('e => e.scrollTop')
                assert up < down, (w,h,down,up)
                body.evaluate('e => e.scrollTop = e.scrollHeight')
                page.wait_for_timeout(50)
                end = body.evaluate('e => ({top:e.scrollTop,max:e.scrollHeight-e.clientHeight})')
                assert abs(end['top']-end['max']) <= 2, (w,h,end)
                assert page.locator('#save').is_visible(), (w,h)
                print(f"OK {w}x{h} client={m0['clientHeight']} scroll={m0['scrollHeight']} down={down} up={up} end={end['top']}")
                page.close()
        finally:
            browser.close()

if __name__ == '__main__':
    run()
