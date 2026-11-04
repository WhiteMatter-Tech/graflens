"""Local-only authentication failure and redirect fixtures. No real credentials."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body, mime='application/json'):
        data = body.encode()
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith('/if/flow/login/'):
            self.reply(200, '<html>private-login-content</html>', 'text/html')
        elif self.headers.get('Authorization') == 'Bearer fixture-redirect':
            self.send_response(302)
            self.send_header('Location', '/if/flow/login/?code=private-code')
            self.send_header('Content-Length', '0')
            self.end_headers()
        elif self.headers.get('Authorization') == 'Bearer fixture-reject':
            self.reply(401, '{"message":"Invalid API key"}')
        else:
            self.reply(200, '{"database":"ok","version":"13.0.0"}')

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.reply(403, '<html>Proxy access denied</html>', 'text/html')

    def do_DELETE(self):
        self.reply(200, '<html>Proxy landing page</html>', 'text/html')

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18768), Handler).serve_forever()
