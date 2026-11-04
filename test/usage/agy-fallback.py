# SPDX-License-Identifier: GPL-3.0-only
# A machine with two Antigravity sign-ins: agy's own, which Google refuses
# (revoked), and pi's, which it accepts. The refused one is asked first (it
# lapses last) and gives way to pi's, whose answer is the one shown. pi's
# sign-in names no email and has no refresh token, so it is kept under the
# access token. The plan is named by its id alone.

import hashlib
import json
import os
from pathlib import Path

AGY, PI = "ya29.FAKE-AGY-REVOKED", "ya29.FAKE-PI-GOOD"
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"


def by_sign_in(refused, accepted):
  def answer(request):
    return refused if request.get_header("Authorization") == "Bearer " + AGY else accepted

  return answer


ROUTES = [
  (BASE + "loadCodeAssist", by_sign_in((401, {"error": {"code": 401, "status": "UNAUTHENTICATED"}}), {"paidTier": {"id": "standard-tier"}})),
  (BASE + "retrieveUserQuotaSummary", {"buckets": [
    # No fraction and no amount, only a reset: spent until then. A fraction below 0 is no more than all of it.
    {"window": "5h", "resetTime": "2099-01-01T05:00:00Z"},
    {"window": "weekly", "remainingFraction": -0.5, "resetTime": "2099-01-07T00:00:00Z"},
  ]}),
]


def setup(home, bin):
  agy = home / ".gemini" / "antigravity-cli"
  agy.mkdir(parents=True, exist_ok=True)
  (agy / "antigravity-oauth-token").write_text(json.dumps({"access_token": AGY, "refresh_token": "1//FAKE-AGY", "expiry": "2099-06-01T00:00:00Z"}))
  auth = home / ".pi" / "agent" / "auth.json"
  auth.parent.mkdir(parents=True, exist_ok=True)
  auth.write_text(json.dumps({"google-antigravity": {"type": "oauth", "access": PI, "expires": "2099-01-01T00:00:00Z"}}))


def check(record, requests):
  assert [(r["url"].rsplit(":", 1)[1], r["headers"]["authorization"]) for r in requests] == [
    ("loadCodeAssist", "Bearer " + AGY), ("loadCodeAssist", "Bearer " + PI), ("retrieveUserQuotaSummary", "Bearer " + PI),
  ], [(r["url"], r["headers"]["authorization"]) for r in requests]
  assert record["ready"] is True and record["tierLabel"] == "Standard", (record["ready"], record["tierLabel"])
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 1.0, "resetsAt": "2099-01-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 1.0, "resetsAt": "2099-01-07T00:00:00+00:00"},
  ], record["limits"]
  # One sign-in refused is no trouble while another answers.
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False and record["retryAdvised"] is False

  digest = hashlib.sha256(PI.encode()).hexdigest()[:16]
  kept = json.loads((Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"agy-limits-{digest}.json").read_text())
  assert kept["limits"] == record["limits"] and kept["tierLabel"] == "Standard", kept
