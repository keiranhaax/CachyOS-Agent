#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-only
"""Run one usage collector's main() against a fixture and check what it reports.

    usage-fixture.py <collector file> <fixture file>

A fixture is a Python file that describes a machine on which the agent is in
use, and what its service says. It may define:

  ENV      environment variables to set (a dict).
  ARGS     the collector's arguments (default: ["--force"]).
  setup(home, bin)
           write credential and session files under `home`, and any program
           the collector runs (codex's app-server) into `bin`, the only
           directory on PATH. It may also set variables in os.environ.
  ROUTES   [(text, reply)]: a request whose URL contains `text` is answered
           by the first matching reply, which is a JSON-able value (HTTP 200),
           a (status, value) pair, or a function of the request returning
           either. A request that matches none fails to connect, as one
           to a closed port does.
  check(record, requests)
           asserts on the record the collector printed and on the requests it
           made (a dict each: url, method, headers with lowercase names, body).

HOME and the XDG directories are the caller's sandbox: nothing here reads the
real ones. The collector runs for real, its own parsing, caches and record
included; only the network is replaced, at urllib.request.urlopen, which every
collector request goes through. Exit status 1 and a message on stderr when the
collector fails, writes to stderr (it does that on a bug), or the check does.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import urllib.error
import urllib.request
from email.message import Message
from pathlib import Path

sys.dont_write_bytecode = True


def load(path: str, name: str):
  loader = importlib.machinery.SourceFileLoader(name, path)
  module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
  loader.exec_module(module)
  return module


class Response:
  """What urlopen hands back: open_json uses it as a context manager and reads it."""

  def __init__(self, body: bytes) -> None:
    self.body = io.BytesIO(body)

  def __enter__(self):
    return self

  def __exit__(self, *exc):
    return False

  def read(self, size: int = -1) -> bytes:
    return self.body.read(size)


def serve(routes, requests):
  def urlopen(request, timeout=None, **_):
    if isinstance(request, str):
      request = urllib.request.Request(request)
    requests.append({
      "url": request.full_url,
      "method": request.get_method(),
      "headers": {name.lower(): value for name, value in request.header_items()},
      "body": request.data,
    })
    for text, reply in routes:
      if text not in request.full_url:
        continue
      answer = reply(request) if callable(reply) else reply
      status, value = answer if isinstance(answer, tuple) else (200, answer)
      body = value if isinstance(value, bytes) else json.dumps(value).encode()
      if status >= 400:
        raise urllib.error.HTTPError(request.full_url, status, "fixture", Message(), io.BytesIO(body))
      return Response(body)
    raise urllib.error.URLError("the fixture has no route for " + request.full_url)

  return urlopen


def run(collector: str, fixture_path: str) -> int:
  fixture = load(fixture_path, "fixture")
  home = Path(os.environ["HOME"])
  bin_dir = home.parent / "fixture-bin"
  bin_dir.mkdir(exist_ok=True)
  keep = {name: os.environ[name] for name in ("HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME") if name in os.environ}
  os.environ.clear()
  os.environ.update(keep, PATH=str(bin_dir), **getattr(fixture, "ENV", {}))
  if hasattr(fixture, "setup"):
    fixture.setup(home, bin_dir)

  requests: list[dict] = []
  urllib.request.urlopen = serve(getattr(fixture, "ROUTES", []), requests)
  module = load(collector, "collector")
  sys.argv = [collector, *getattr(fixture, "ARGS", ["--force"])]
  out, err = io.StringIO(), io.StringIO()
  with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
    status = module.main()
  if status or err.getvalue():
    print(f"exit {status}, stderr: {err.getvalue()[:400]}", file=sys.stderr)
    return 1
  record = json.loads(out.getvalue())
  try:
    fixture.check(record, requests)
  except AssertionError as error:
    print(f"{str(error) or 'a check failed'}\nrecord: {out.getvalue()[:800]}\nrequests: {[r['url'] for r in requests]}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  raise SystemExit(run(sys.argv[1], sys.argv[2]))
