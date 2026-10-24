"""Loopback-only integration fixture. Serves generated silence, never catalog music."""
import http.server
import io
import json
import struct
import time
import wave
from pathlib import Path

out = io.BytesIO()
with wave.open(out, 'wb') as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(22050)
    audio.writeframes(b'\0\0' * 22050 * 3)
WAV = out.getvalue()
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path == '/source.js':
            script = '''/**
 * @name Local integration fixture — not a music service
 * @version 1.0
 */
lx.on('request', async () => 'http://127.0.0.1:%d/audio.wav');
lx.send('inited', {sources: {kw: {type: 'music', actions: ['musicUrl'], qualitys: ['128k']}}});
''' % self.server.server_port
            content, mime = script.encode(), 'text/javascript'
        elif self.path.startswith('/audio.wav'):
            content, mime = WAV, 'audio/wav'
        elif self.path == '/slow':
            time.sleep(2)
            content, mime = b'{}', 'application/json'
        elif self.path in ['/silence-128.mp3', '/silence-320.mp3', '/silence-16.flac', '/silence-24.flac']:
            content, mime = (Path(__file__).parent / self.path[1:]).read_bytes(), 'application/octet-stream'
        else:
            content, mime = b'{"ok":true}', 'application/json'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        try: self.wfile.write(content)
        except (BrokenPipeError, ConnectionResetError): pass
    def do_POST(self):
        data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        content = json.dumps({'body': data.decode(), 'contentType': self.headers.get('Content-Type')}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
