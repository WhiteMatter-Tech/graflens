"""Grafana-style viewport-sensitive embeds on a large dashboard (localhost only)."""
import json
import threading
from http.server import ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import fixture_server as fixture

fixture.PANELS = [{"id": i, "title": f"Tool usage {i}", "type": "bargauge", "gridPos": {"w": 24, "h": 10}} for i in range(1, 77)]
measurements = {}
page_counts = {}
lock = threading.Lock()

class StressHandler(fixture.Handler):
    def do_GET(self):
        url = urlparse(self.path)
        if url.path == '/page-counts':
            with lock:
                self.send(dict(page_counts))
            return
        if url.path == '/measurements':
            with lock:
                self.send(dict(measurements))
            return
        if url.path.startswith('/d-solo/'):
            panel = int(parse_qs(url.query).get('panelId', ['0'])[0])
            with lock:
                page_counts[str(panel)] = page_counts.get(str(panel), 0) + 1
            self.send(f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>html,body,#root{{margin:0;width:100%;height:100%;font:14px -apple-system;overflow:hidden}}*{{box-sizing:border-box}}
            #panel{{position:absolute;inset:0;background:white;padding:12px}}h3{{margin:0 0 12px;font-size:15px}}.row{{display:flex;align-items:center;gap:8px;margin:8px 0}}.label{{width:95px}}.bar{{height:16px;background:#59a247;border-radius:4px}}</style></head><body><div id="root"></div>
            <script>
            let id={panel};let reports=0;
            function render(){{
              const r=document.querySelector('#root').getBoundingClientRect();
              if(r.width>0 && r.height>0){{document.querySelector('#root').innerHTML='<div id="panel"><h3>Tool usage '+id+'</h3>'+['Bash','Read','Write','Search'].map((s,i)=>'<div class="row"><span class="label">'+s+'</span><span class="bar" style="width:'+(130-i*25)+'px"></span><span>'+(15500-i*4300)+'</span></div>').join('')+'</div>';}}
              if(reports++<4)fetch('/measurements',{{method:'POST',body:JSON.stringify({{id,width:r.width,height:r.height,innerWidth,innerHeight,visible:document.visibilityState,painted:!!document.querySelector('#panel')}})}});
            }}
            new ResizeObserver(render).observe(document.querySelector('#root'));
            requestAnimationFrame(render);
            </script></body></html>''', content_type='text/html')
            return
        super().do_GET()

    def do_POST(self):
        if self.path == '/measurements':
            data=json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
            with lock:
                measurements.setdefault(str(data['id']), []).append(data)
            self.send({"ok":True})
        else:
            super().do_POST()

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18767), StressHandler).serve_forever()
