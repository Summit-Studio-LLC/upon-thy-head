#!/usr/bin/env python3
"""Serves the speech model to the emulator for tests (tool/android_words.sh), as its real host would:
one file, with HTTP range requests, so an interrupted download can carry on.

  tool/model_server.py FILE [--port 4330] [--log requests.log] [--rate MB/s] [--drop-after BYTES] [--stall-after BYTES]

The emulator reaches it at http://10.0.2.2:PORT/<name> (debug builds allow plain HTTP to 10.0.2.2
only: android/app/src/debug/res/xml/network_security_config.xml). Bound to 127.0.0.1 only.
--drop-after closes the first response after that many bytes (a lost connection); --stall-after
stops sending after that many bytes until the server is stopped (a connection that hangs).
Every request is written to the log: time, method, path, Range, status, bytes sent.
"""
import argparse
import http.server
import os
import re
import threading
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--port', type=int, default=4330)
    ap.add_argument('--log', default=None)
    ap.add_argument('--drop-after', type=int, default=0)
    ap.add_argument('--stall-after', type=int, default=0)
    ap.add_argument('--rate', type=float, default=4.0, help='megabytes a second, so a test can catch it mid-way')
    a = ap.parse_args()
    size = os.path.getsize(a.file)
    name = os.path.basename(a.file)
    state = {'dropped': False}
    lock = threading.Lock()

    def log(line):
        if a.log:
            with lock, open(a.log, 'a') as f:
                f.write(f'{time.strftime("%H:%M:%S")} {line}\n')

    class H(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *args):
            pass

        def do_GET(self):
            rng = self.headers.get('Range', '')
            if self.path.lstrip('/') != name:
                self.send_response(404)
                self.send_header('Content-Length', '0')
                self.end_headers()
                log(f'GET {self.path} range={rng!r} 404 0')
                return
            start = 0
            m = re.match(r'bytes=(\d+)-$', rng)
            if m:
                start = int(m.group(1))
                if start >= size:
                    self.send_response(416)
                    self.send_header('Content-Range', f'bytes */{size}')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    log(f'GET {self.path} range={rng!r} 416 0')
                    return
                self.send_response(206)
                self.send_header('Content-Range', f'bytes {start}-{size - 1}/{size}')
            else:
                self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Length', str(size - start))
            self.send_header('Accept-Ranges', 'bytes')
            self.end_headers()
            sent = 0
            code = 206 if m else 200
            try:
                with open(a.file, 'rb') as f:
                    f.seek(start)
                    while True:
                        chunk = f.read(64 * 1024)
                        if not chunk:
                            break
                        if a.drop_after and not state['dropped'] and start + sent + len(chunk) > a.drop_after:
                            state['dropped'] = True
                            log(f'GET {self.path} range={rng!r} {code} {sent} DROPPED')
                            self.close_connection = True
                            self.connection.shutdown(2)
                            return
                        if a.stall_after and start + sent + len(chunk) > a.stall_after:
                            log(f'GET {self.path} range={rng!r} {code} {sent} STALLED')
                            while True:
                                time.sleep(1)
                        self.wfile.write(chunk)
                        sent += len(chunk)
                        time.sleep(len(chunk) / (a.rate * 1e6))
            except (BrokenPipeError, ConnectionResetError):
                log(f'GET {self.path} range={rng!r} {code} {sent} CLIENT-CLOSED')
                return
            log(f'GET {self.path} range={rng!r} {code} {sent}')

    srv = http.server.ThreadingHTTPServer(('127.0.0.1', a.port), H)
    srv.daemon_threads = True
    print(f'serving {name} ({size} bytes) on 127.0.0.1:{a.port}', flush=True)
    srv.serve_forever()


if __name__ == '__main__':
    main()
