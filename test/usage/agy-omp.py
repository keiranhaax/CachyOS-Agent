# SPDX-License-Identifier: GPL-3.0-only
# A machine where Antigravity is signed in through omp, with two accounts
# whose access tokens have lapsed. omp renews one when asked for usage (the
# stub does, in its database) and names it in its report, so the limits come
# from `omp usage`, folded into Google's shape: used fractions, a window
# listed twice, limits that are no fraction, another provider's report. The
# plan is asked of Google with the renewed token alone. A disabled omp
# credential and a non-OAuth one must stay unused.

import hashlib
import json
import os
import sqlite3
from pathlib import Path

EMAIL = "omp.user@example.test"
RENEWED_ACCESS = "ya29.FAKE-OMP-RENEWED"
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
LAPSED = {"type": "oauth", "access": "ya29.FAKE-OMP-LAPSED", "refresh": "1//FAKE-OMP", "expires": 1577836800000, "email": EMAIL}
RENEWED = {"type": "oauth", "access": RENEWED_ACCESS, "refresh": "1//FAKE-OMP", "expires": 4102444800000, "email": EMAIL}
OTHER = {"type": "oauth", "access": "ya29.FAKE-OMP-OTHER", "refresh": "1//FAKE-OMP-OTHER", "expires": 1577836800000, "email": "other.user@example.test"}
# Tokens that would be sent if either credential were read.
UNUSED = {"type": "oauth", "access": "ya29.FAKE-OMP-UNUSED", "expires": 4102444800000, "email": "unused@example.test"}


def limit(label, window, fraction, resets="2099-04-07T00:00:00Z"):
  return {"label": label, "window": {"id": window, "resetsAt": resets}, "amount": {"usedFraction": fraction}}


REPORT = {"reports": [
  {"provider": "openai-codex", "limits": [limit("Codex", "5h", 0.9)]},
  {"provider": "google-antigravity", "metadata": {"email": EMAIL}, "limits": [
    limit("Gemini", "5h", 0.15, "2099-04-01T05:00:00Z"),
    limit("Gemini", "weekly", 0.55),
    # The same allowance listed again for another model family.
    limit("Claude", "weekly", 0.2),
    limit("Claude", "weekly", 0.2),
    # Limits with no fraction, or one that is no number, say nothing.
    limit("GPT", "5h", True),
    limit("Other", "5h", "lots"),
    {"label": "Quiet", "window": {"id": "5h"}, "amount": {}},
  ]},
]}

# omp renews the account it is asked about, and prints the report.
OMP = f"""#!/usr/bin/python3
import json, os, sqlite3, sys
if sys.argv[1:] != ["usage", "--json", "--provider", "google-antigravity"]:
  sys.exit(2)
conn = sqlite3.connect(os.path.join(os.environ["HOME"], ".omp", "agent", "agent.db"))
with conn:
  for (data,) in conn.execute("SELECT data FROM auth_credentials WHERE provider = 'google-antigravity'").fetchall():
    if json.loads(data).get("email") == {EMAIL!r}:
      conn.execute("UPDATE auth_credentials SET data = ? WHERE data = ?", ({json.dumps(RENEWED)!r}, data))
print({json.dumps(REPORT)!r})
"""

ROUTES = [
  (BASE + "loadCodeAssist", {"paidTier": {"id": "standard-tier", "name": "Antigravity Ultra"}}),
]


def setup(home, bin):
  tool = bin / "omp"
  tool.write_text(OMP)
  tool.chmod(0o755)
  database = home / ".omp" / "agent" / "agent.db"
  database.parent.mkdir(parents=True, exist_ok=True)
  database.unlink(missing_ok=True)
  conn = sqlite3.connect(database)
  with conn:
    conn.execute("CREATE TABLE auth_credentials (provider TEXT, credential_type TEXT, disabled_cause TEXT, data TEXT)")
    conn.executemany("INSERT INTO auth_credentials VALUES (?, ?, ?, ?)", [
      ("google-antigravity", "oauth", None, json.dumps(OTHER)),
      ("google-antigravity", "oauth", None, json.dumps(LAPSED)),
      ("google-antigravity", "oauth", "revoked", json.dumps(UNUSED)),
      ("google-antigravity", "api_key", None, json.dumps(UNUSED)),
      ("openai-codex", "oauth", None, json.dumps(UNUSED)),
    ])
  conn.close()


def check(record, requests):
  # Only the renewed token is sent, and only for the plan: the quota came from omp.
  assert [(r["url"], r["headers"]["authorization"]) for r in requests] == [(BASE + "loadCodeAssist", "Bearer " + RENEWED_ACCESS)], requests
  assert record["ready"] is True and record["tierLabel"] == "Ultra", (record["ready"], record["tierLabel"])
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.15, "resetsAt": "2099-04-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.55, "resetsAt": "2099-04-07T00:00:00+00:00"},
    {"label": "Claude/GPT Weekly", "title": "Claude/GPT Weekly", "percent": 0.2, "resetsAt": "2099-04-07T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False and record["retryAdvised"] is False

  # Kept for the account the report names, and for no other.
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  digest = hashlib.sha256(EMAIL.encode()).hexdigest()[:16]
  kept = json.loads((cache / f"agy-limits-{digest}.json").read_text())
  assert kept["limits"] == record["limits"] and kept["tierLabel"] == "Ultra", kept
  assert sorted(path.name for path in cache.glob("agy-limits-*.json")) == [f"agy-limits-{digest}.json"], sorted(path.name for path in cache.iterdir())
