"""Illustrative number-panel layout fixture, including Grafana fallback rendering."""
from http.server import ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import fixture_server as fixture

METRICS = {21: ("Total Apps", 125, "#5085d6"), 22: ("Healthy", 92, "#6caf52"),
           23: ("Out of Sync", 28, "#df9b25"), 24: ("Degraded", 5, "#d85757")}
WEB_PANELS = [{"id": id, "type": "stat", "title": title, "gridPos": {"w": 24, "h": 8},
               "transformations": [{"id": "reduce"}]} for id, (title, _, _) in METRICS.items()]
fixture.PANELS = [*WEB_PANELS,
    fixture.panel(31, "Temperature", "stat"), fixture.panel(32, "Humidity", "stat", "humidity", "percent"),
    fixture.panel(33, "Long descriptive metric title", "stat"),
    fixture.panel(34, "Capacity", "gauge", "capacity", "percent"),
    {"id": 35, "type": "table", "title": "Device details", "gridPos": {"w": 24, "h": 8}},
    {"id": 36, "type": "logs", "title": "Recent logs", "gridPos": {"w": 24, "h": 8}},
    fixture.panel(4, "Temperature over time", expr="temperature_pair", width=24)]

class CompactHandler(fixture.Handler):
    def do_GET(self):
        url = urlparse(self.path)
        if url.path.startswith('/d-solo/'):
            query = parse_qs(url.query)
            id = int(query.get('panelId', ['0'])[0])
            if id == 36:
                dark = query.get('theme', ['light'])[0] == 'dark'
                lines = ''.join(f'<div>13:45:{i:02d} INFO worker-{i % 3} healthy</div>' for i in range(20))
                self.send(f'<html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="margin:12px;background:{"#202124" if dark else "white"};color:{"white" if dark else "#222"};font:13px monospace"><h3>Recent logs</h3>{lines}</body></html>', content_type='text/html')
                return
            if id in METRICS:
                title, value, color = METRICS[id]
                dark = query.get('theme', ['light'])[0] == 'dark'
                self.send(f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
                <style>*{{box-sizing:border-box}}html,body{{margin:0;height:100%;overflow:hidden;font-family:-apple-system}}
                body{{display:flex;flex-direction:column;background:{'#202124' if dark else 'white'};color:{'white' if dark else '#222'}}}
                header{{height:36px;display:flex;align-items:center;justify-content:space-between;padding:0 10px;flex-shrink:0;gap:8px}}
                .title{{font-size:16px;white-space:nowrap}}.brand{{font-size:11px;color:#777;white-space:nowrap}}
                main{{flex:1;min-height:0;background:{color};color:white;display:flex;align-items:center;justify-content:center}}
                .value{{font-weight:500;font-variant-numeric:tabular-nums}}
                </style></head><body><header><span class="title">{title}</span><span class="brand">Powered by ◉ Grafana</span></header>
                <main><span class="value">{value}</span></main><script>
                new ResizeObserver(entries => {{let r=entries[0].contentRect;document.querySelector('.value').style.fontSize=Math.min(r.height*.72,r.width*.4)+'px';}}).observe(document.querySelector('main'));
                </script></body></html>''', content_type='text/html')
                return
        super().do_GET()

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18766), CompactHandler).serve_forever()
