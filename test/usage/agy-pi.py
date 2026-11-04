# SPDX-License-Identifier: GPL-3.0-only
# A machine where Antigravity is signed in only through pi (agy was never run
# here), on the free plan. Google's quota answer is the flat shape with
# snake_case keys, buckets named by their ids, and buckets that must not
# count: disabled, with an amount and no fraction, with a fraction that is no
# number, with no value and no usable reset. CLOUD_CODE_URL names a plain-http
# host, which never gets the token.

import hashlib
import json
import os
from pathlib import Path

ACCESS = "ya29.FAKE-PI-ACCESS"
EMAIL = "pi.user@example.test"
ENV = {"CLOUD_CODE_URL": "http://cloudcode.insecure.test"}
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
RESET = "2099-02-01T05:00:00Z"

# A bucket that cannot be read is skipped wherever it sits, so each of these
# follows the bucket it would otherwise replace. A time of 0, of true, and
# Go's zero time are no reset: a bucket with nothing else is not spent.
ROUTES = [
  (BASE + "loadCodeAssist", {
    "currentTier": {"id": "free-tier", "name": "Antigravity"},
    "cloudaicompanionProject": {"id": "  pi-project-9 "},
  }),
  (BASE + "retrieveUserQuotaSummary", {"buckets": [
    {"bucketId": "Gemini-5H-Pool", "remaining_fraction": 0.6, "reset_time": RESET},
    {"bucketId": "gemini-5h-spare", "disabled": True, "remainingFraction": 0.0, "resetTime": RESET},
    {"bucketId": "gemini-5h-credit", "remainingAmount": 40, "resetTime": RESET},
    {"bucketId": "gemini-5h-credit-too", "remaining_amount": 12, "reset_time": RESET},
    {"bucketId": "gemini-5h-text", "remainingFraction": "n/a", "resetTime": RESET},
    {"bucketId": "gemini-5h-nan", "remainingFraction": float("nan"), "resetTime": RESET},
    {"bucketId": "gemini-5h-flag", "remainingFraction": True, "resetTime": RESET},
    {"bucketId": "gemini-5h-off", "remainingAmount": False, "resetTime": RESET},
    {"bucketId": "gemini-5h-bare"},
    {"bucketId": "gemini-5h-zero", "resetTime": "0001-01-01T00:00:00Z"},
    {"bucketId": "gemini-5h-true", "resetTime": True},
    {"bucketId": "gemini-5h-epoch", "resetTime": "0"},
    # No fraction and an amount of zero: nothing is left. The reset is epoch seconds.
    {"bucketId": "Gemini-Weekly-Pool", "remaining_amount": "0", "reset_time": 4070908800},
  ]}),
]


def setup(home, bin):
  auth = home / ".pi" / "agent" / "auth.json"
  auth.parent.mkdir(parents=True, exist_ok=True)
  auth.write_text(json.dumps({
    "anthropic": {"type": "api_key", "key": "sk-FAKE-NOT-ANTIGRAVITY"},
    "google-antigravity": {"type": "oauth", "access": ACCESS, "refresh": "1//FAKE-PI-REFRESH", "expires": 4102444800000, "email": EMAIL},
  }))


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Free", (record["ready"], record["tierLabel"])
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.4, "resetsAt": "2099-02-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 1.0, "resetsAt": "2099-01-01T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "", (record["usageStatusText"], record["authHelpText"])
  assert record["limitsStale"] is False and record["retryAdvised"] is False and record["limitsFetchedAt"] > 0

  # Google's own host, never the one named over plain http, and the project's {id} as a trimmed string.
  assert [r["url"] for r in requests] == [BASE + "loadCodeAssist", BASE + "retrieveUserQuotaSummary"], requests
  assert [json.loads(r["body"]) for r in requests] == [{}, {"project": "pi-project-9"}], [r["body"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer " + ACCESS for r in requests), "pi's sign-in was not sent"

  # Kept under the email pi names, not the access token.
  digest = hashlib.sha256(EMAIL.encode()).hexdigest()[:16]
  kept = json.loads((Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"agy-limits-{digest}.json").read_text())
  assert kept["limits"] == record["limits"] and kept["tierLabel"] == "Free", kept

  assert record["hasLocalStats"] is False and record["modelUsage"] == {} and record["totalPrompts"] == 0, "local stats on a machine that has run no Antigravity"
