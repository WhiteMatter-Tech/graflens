"""Local-only fixtures for GrafLens simulator checks. No live credentials or data."""
import json
import math
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DS = {"uid": "preview-prometheus", "type": "prometheus"}

def panel(id, title, kind="timeseries", expr="temperature", unit="fahrenheit", width=12):
    defaults = {"unit": unit, "color": {"mode": "palette-classic" if kind == "timeseries" else "thresholds"}}
    if kind == "gauge":
        defaults.update(min=0, max=100, thresholds={"mode": "absolute", "steps": [{"value": None, "color": "blue"}, {"value": 80, "color": "orange"}]})
    return {"id": id, "title": title, "type": kind, "gridPos": {"w": width, "h": 8},
            "fieldConfig": {"defaults": defaults}, "targets": [{"refId": "A", "expr": expr, "datasource": DS}],
            "options": {"reduceOptions": {"calcs": ["lastNotNull"]}}}

PANELS = [
    panel(1, "Temperature", "stat"),
    panel(2, "Humidity", "stat", "humidity", "percent"),
    panel(3, "Capacity", "gauge", "capacity", "percent"),
    {"id": 10, "title": "Environment", "type": "row", "panels": []},
    panel(4, "Temperature over time", expr="temperature_pair"),
    panel(5, "Humidity over time", expr="humidity", unit="percent"),
    panel(6, "Readings with a collection gap", expr="with_gap"),
    {"id": 7, "type": "table", "title": "Device details", "gridPos": {"w": 24, "h": 8}},
]

PANELS = [PANELS[4], *PANELS[:4], *PANELS[5:]]

class Handler(BaseHTTPRequestHandler):
    def send(self, value, status=200, content_type="application/json"):
        data = json.dumps(value).encode() if content_type == "application/json" else value.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        path = url.path
        if path == "/api/health": self.send({"database": "ok", "version": "12.0.0"})
        elif path == "/api/search": self.send([{"id": 1, "uid": "preview", "title": "Environment overview", "folderTitle": "Monitoring", "tags": ["environment", "preview"]}])
        elif path.startswith("/api/dashboards/uid/"):
            self.send({"dashboard": {"id": 1, "uid": "preview", "title": "Environment overview", "description": "A clear view of your environment. Illustrative simulator data.", "version": 7, "schemaVersion": 39, "panels": PANELS, "time": {"from": "now-6h", "to": "now"}, "annotations": {"list": []}}, "meta": {"folderTitle": "Monitoring", "folderUid": "monitoring"}})
        elif path == "/api/datasources": self.send([{"id":1,"uid":DS["uid"],"type":"prometheus","name":"Preview metrics","isDefault":True}])
        elif path.endswith("/alerts"): self.send({"data":{"alerts":[]},"status":"success"})
        elif path.endswith("/rules"): self.send({"data":{"groups":[{"name":"Environment", "rules":[{"name":"High temperature","state":"inactive","health":"ok"}]}]},"status":"success"})
        elif path == "/api/annotations":
            now=int(time.time()*1000)
            self.send([{"id":1,"panelId":4,"time":now-7200000,"text":"Window opened"}, {"id":2,"panelId":4,"time":now-3600000,"timeEnd":now-1800000,"text":"Calibration"}])
        elif path.startswith("/d-solo/"):
            q=parse_qs(url.query);dark=q.get("theme",["light"])[0]=="dark"
            self.send(f'''<html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body style="background:{'#1c1c1e' if dark else '#fff'};color:{'#eee' if dark else '#222'};font:16px -apple-system;padding:16px"><h3>Device details</h3><p>Fixture · {q.get('from',[''])[0]} · {q.get('theme',[''])[0]}</p><table style="width:100%;line-height:2.5;text-align:left"><tr><th>Device</th><th>Room</th><th>State</th></tr><tr><td>Sensor A</td><td>Office</td><td>Online</td></tr><tr><td>Sensor B</td><td>Studio</td><td>Online</td></tr></table></body></html>''',content_type="text/html")
        else: self.send({"message":"Not found"},404)

    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get("Content-Length",0))))
        if self.path != "/api/ds/query":
            self.send({"message":"Fixture server does not accept writes"},405);return
        start,end=int(body["from"]),int(body["to"])
        results={}
        for q in body["queries"]:
            expr=q["expr"]; ts=[start+(end-start)*i//72 for i in range(73)]
            frames=[]
            for sensor in range(2 if expr == "temperature_pair" else 1):
                vals=[]
                for i in range(73):
                    v=62-i*.19+math.sin(i*.3)*1.4+sensor*2
                    if expr == "humidity": v=40+i*.085+math.sin(i*.2)*1.4
                    if expr == "capacity": v=65+math.sin(i*.2)*5
                    if expr == "with_gap" and 25<=i<=35:v=None
                    vals.append(v)
                frames.append({"schema":{"fields":[{"name":"Time","type":"time"},{"name":"Sensor A" if sensor==0 else "Sensor B","type":"number","labels":{"sensor":str(sensor)}}]},"data":{"values":[ts,vals]}})
            results[q["refId"]]={"frames":frames}
        self.send({"results":results})

if __name__ == "__main__":
    print("GrafLens fixture server: http://127.0.0.1:18764",flush=True)
    ThreadingHTTPServer(("127.0.0.1",18764),Handler).serve_forever()
