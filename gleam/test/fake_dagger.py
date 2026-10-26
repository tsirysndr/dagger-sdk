#!/usr/bin/env python3
"""Local Dagger session protocol fixture. Never contacts a real engine."""
import base64
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

mode = os.environ.get('DAGGER_TEST_MODE', 'normal')
if mode == 'exit':
    sys.exit(7)
if mode == 'timeout':
    sys.stdin.read()
    sys.exit(0)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        assert self.path == '/query'
        assert self.headers['Authorization'] == 'Basic ' + base64.b64encode(b'test-token:').decode()
        assert self.headers['Content-Type'] == 'application/json'
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert body == {'query': 'query{container{stdout}}'}
        response = json.dumps({'data': {'container': {'stdout': 'hello from HTTP'}}}).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *_):
        pass

server = None
if mode == 'http':
    server = HTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
line = json.dumps({'port': server.server_port if server else 12345, 'session_token': 'test-token'})
print('startup diagnostic, not JSON', flush=True)
# Deliberately split the credentials across separate writes.
sys.stdout.write(line[:12])
sys.stdout.flush()
time.sleep(0.01)
print(line[12:], flush=True)
sys.stdin.read()
if server:
    server.server_close()
