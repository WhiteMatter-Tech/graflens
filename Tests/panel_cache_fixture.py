"""Isolated, delayed fixtures and request counts for the panel lifecycle tests."""
import json
import threading
import time
from http.server import ThreadingHTTPServer
from fixture_server import Handler

counts = {"queries": 0, "pages": 0, "activeQueries": 0, "peakQueries": 0}
lock = threading.Lock()

class CacheHandler(Handler):
    def do_GET(self):
        if self.path == "/cache-counts":
            with lock:
                self.send(dict(counts))
        elif self.path.startswith("/render-"):
            key = self.path.split("?")[0].removeprefix("/render-")
            with lock:
                counts[key] = counts.get(key, 0) + 1
                attempt = counts[key]
            content = ""
            if key == "delayed":
                content = '<script>setTimeout(() => {document.body.innerHTML = "<pre><code>Panel ready</code></pre>"}, 1200)</script>'
            elif key == "layout":
                content = '<script>document.body.textContent = innerWidth + " x " + innerHeight</script>'
            elif key == "recover" and attempt > 1:
                content = 'Recovered panel'
            self.send('<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>' + content + '</body></html>', content_type="text/html")
        elif self.path.startswith("/cache-page"):
            with lock:
                counts["pages"] += 1
            time.sleep(0.3)
            self.send('<html><body><h1>Cached interactive panel</h1><input id="value" value="original"><div style="height:2000px">Scroll state</div></body></html>', content_type="text/html")
        elif self.path.startswith("/d-solo/"):
            with lock:
                counts["pages"] += 1
            super().do_GET()
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == "/api/ds/query":
            with lock:
                counts["queries"] += 1
                counts["activeQueries"] += 1
                counts["peakQueries"] = max(counts["peakQueries"], counts["activeQueries"])
            time.sleep(0.3)
        try:
            super().do_POST()
        except (BrokenPipeError, ConnectionResetError):
            pass  # Superseded and disposed sessions deliberately cancel requests.
        finally:
            if self.path == "/api/ds/query":
                with lock:
                    counts["activeQueries"] -= 1

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18765), CacheHandler).serve_forever()
