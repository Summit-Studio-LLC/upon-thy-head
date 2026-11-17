#!/usr/bin/env python3
"""Every request the app makes to the link service, written down: a small forwarding proxy for
tool/link_acceptance.sh. The app is built with LINK_SERVICE=http://127.0.0.1:<listen>; this passes
each request on to the local website and writes one JSON line per request (method, path, headers,
body in base64, and the answer's status) so the script can show that no key, and no stop token
outside its own header, ever left the phone.

    tool/link_proxy.py <listen port> <website port> <log file>
"""
import base64
import gzip
import http.client
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN, UPSTREAM, LOG = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
lock = threading.Lock()


class Forward(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _any(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        status, headers, answer = 502, [("Content-Type", "text/plain")], b"no website"
        try:
            c = http.client.HTTPConnection("127.0.0.1", UPSTREAM, timeout=30)
            fwd = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "connection")}
            fwd["Host"] = f"127.0.0.1:{UPSTREAM}"
            c.request(self.command, self.path, body=body if body else None, headers=fwd)
            r = c.getresponse()
            status, headers, answer = r.status, r.getheaders(), r.read()
            c.close()
        except OSError:
            pass  # the website is stopped: a non-JSON 502, which the app treats as no internet
        def plain(data, hs):  # the answer as the app reads it (the website compresses it)
            if any(k.lower() == "content-encoding" and "gzip" in v for k, v in hs):
                data = gzip.decompress(data)
            return data.decode(errors="replace")
        with lock, open(LOG, "a") as f:
            f.write(json.dumps({
                "method": self.command,
                "path": self.path,
                "headers": dict(self.headers.items()),
                "body": base64.b64encode(body).decode(),
                "status": status,
                # the service's answer to a create: the id and stop token, so the script can follow
                # each stop token through every later request
                **({"answer": plain(answer, headers)} if self.command == "POST" else {}),
            }) + "\n")
        self.send_response(status)
        for k, v in headers:
            if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(answer)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(answer)

    do_GET = do_POST = do_DELETE = do_PUT = do_HEAD = _any

    def log_message(self, *a):
        pass


ThreadingHTTPServer(("127.0.0.1", LISTEN), Forward).serve_forever()
