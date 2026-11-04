# SPDX-License-Identifier: GPL-3.0-only
# A machine with three Antigravity sign-ins: agy's, which Google refuses, pi's,
# whose last good answer is kept from an hour ago and whose quota Google now
# answers 503, and opencode's, which would answer. The refused sign-in gives
# way to pi's; the 503 is Google answering for every sign-in alike, so
# opencode's is never asked, and pi's own kept limits stand in, marked stale.
# A server error is not worth asking again sooner.

import base64
import hashlib
import json
import os
import time
from pathlib import Path

AGY, PI, OPENCODE = "ya29.FAKE-AGY-REVOKED", "ya29.FAKE-PI-DOWN", "ya29.FAKE-OPENCODE-SPARE"
EMAIL = "down.user@example.test"
FETCHED = int((time.time() - 3600) * 1000)
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"


def by_sign_in(agy, pi, opencode):
  def answer(request):
    return {"Bearer " + AGY: agy, "Bearer " + PI: pi, "Bearer " + OPENCODE: opencode}[request.get_header("Authorization")]

  return answer


PLAN = {"paidTier": {"id": "g1-pro-tier", "name": "Google AI Pro"}}
ROUTES = [
  (BASE + "loadCodeAssist", by_sign_in((401, {"error": {"code": 401}}), PLAN, PLAN)),
  (BASE + "retrieveUserQuotaSummary", by_sign_in(
    (401, {"error": {"code": 401}}), (503, {"error": {"code": 503, "status": "UNAVAILABLE"}}), {"buckets": [{"window": "5h", "remainingFraction": 0.9}]}
  )),
]


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


def setup(home, bin):
  # Expiries order the sign-ins: agy's lapses last, then pi's, then opencode's.
  agy = home / ".gemini" / "antigravity-cli"
  agy.mkdir(parents=True, exist_ok=True)
  (agy / "antigravity-oauth-token").write_text(json.dumps({"access_token": AGY, "expiry": "2099-09-01T00:00:00Z"}))
  pi = home / ".pi" / "agent"
  pi.mkdir(parents=True, exist_ok=True)
  (pi / "auth.json").write_text(json.dumps({"google-antigravity": {"type": "oauth", "access": PI, "expires": "2099-06-01T00:00:00Z", "email": EMAIL}}))
  config = home / ".config" / "opencode"
  config.mkdir(parents=True, exist_ok=True)
  (config / "antigravity-accounts.json").write_text(json.dumps({"version": 1, "accounts": []}))
  data = home / ".local" / "share" / "opencode"
  data.mkdir(parents=True, exist_ok=True)
  (data / "auth.json").write_text(json.dumps({"google": {"type": "oauth", "access": OPENCODE, "expires": "2099-03-01T00:00:00Z"}}))
  kept = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  kept.mkdir(parents=True, exist_ok=True)
  (kept / f"agy-limits-{hashlib.sha256(EMAIL.encode()).hexdigest()[:16]}.json").write_text(json.dumps({
    "fetchedAtMs": FETCHED, "tierLabel": "Pro", "limits": [
      {"label": "Session (5-hour)", "title": "Session", "percent": 0.3, "resetsAt": "2099-01-01T05:00:00+00:00"},
    ],
  }))


def check(record, requests):
  assert [(r["url"].rsplit(":", 1)[1], r["headers"]["authorization"]) for r in requests] == [
    ("loadCodeAssist", "Bearer " + AGY), ("loadCodeAssist", "Bearer " + PI), ("retrieveUserQuotaSummary", "Bearer " + PI),
  ], [(r["url"], r["headers"]["authorization"]) for r in requests]
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  assert record["authHelpText"] == "Google's quota service answered with status 503.", record["authHelpText"]
  # The kept limits are something to show, so there is no "unavailable" status.
  assert record["usageStatusText"] == "", record["usageStatusText"]
  assert record["limits"] == [{"label": "Session (5-hour)", "title": "Session", "percent": 0.3, "resetsAt": "2099-01-01T05:00:00+00:00"}], record["limits"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == FETCHED and record["retryAdvised"] is False
