#!/usr/bin/env python3
"""A fake GitHub API, for the manifest scripts to be checked against.

It serves the files a release is made of as static files, and answers the
endpoints the manifest scripts call. The endpoints that can only be used once —
creating a branch, opening a pull request — answer 422 the second time, as
GitHub does, so a script that is run twice is caught rather than passed.

Usage: python3 tools/fake-github-api.py <port> <directory>
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

PORT = int(sys.argv[1])
ROOT = sys.argv[2]

# What the fork has already been asked for.
STATE = {"refs": set(), "pulls": [], "written": set()}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _static(self, path):
        """A file in the directory the server was given, if it is there."""
        relative = path.lstrip("/")
        target = os.path.normpath(os.path.join(ROOT, relative))

        if not target.startswith(os.path.abspath(ROOT)):
            return False

        if not os.path.isfile(target):
            return False

        with open(target, "rb") as handle:
            body = handle.read()

        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

        return True

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if self._static(path):
            return

        if "/git/ref/heads/master" in path:
            self._json(200, {"object": {"sha": "the-head-of-master"}})
            return

        if "/git/ref/heads/" in path:
            branch = path.split("/git/ref/heads/", 1)[1]
            branches = {ref.split("refs/heads/", 1)[-1] for ref in STATE["refs"]}

            if branch in branches:
                self._json(200, {"object": {"sha": "the-branch"}})
            else:
                self._json(404, {"message": "Not Found"})

            return

        if path.endswith("/pulls"):
            self._json(200, STATE["pulls"])
            return

        if "/contents/" in path:
            name = path.split("/contents/", 1)[1]

            if name in STATE["written"]:
                self._json(200, {"sha": "the-file"})
            else:
                self._json(404, {"message": "Not Found"})

            return

        self._json(404, {"message": "Not Found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(length) or b"{}")
        path = urlparse(self.path).path

        if path.endswith("/git/refs"):
            ref = payload.get("ref", "")

            if ref in STATE["refs"]:
                self._json(422, {"message": "Reference already exists"})
                return

            STATE["refs"].add(ref)
            self._json(201, {"ref": ref})

            return

        if path.endswith("/pulls"):
            branch = payload.get("head", "")

            for existing in STATE["pulls"]:
                if existing["head"]["ref"] == branch:
                    self._json(422, {"message": "A pull request already exists"})
                    return

            pull = {
                "html_url": f"http://127.0.0.1:{PORT}/pull/{len(STATE['pulls']) + 1}",
                "head": {"ref": branch},
            }
            STATE["pulls"].append(pull)
            self._json(201, pull)

            return

        self._json(404, {"message": "Not Found"})

    def do_PUT(self):
        length = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(length) or b"{}")
        path = urlparse(self.path).path

        if "/contents/" in path:
            name = path.split("/contents/", 1)[1]
            STATE["written"].add(name)
            self._json(200, {"content": {"sha": "the-file"}})

            return

        self._json(404, {"message": "Not Found"})


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
