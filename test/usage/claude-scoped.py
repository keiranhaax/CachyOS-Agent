# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x whose usage endpoint answers with a session window that is
# not an object, a weekly one at "0%" whose reset is no time, and a `limits`
# list of every shape it can hold: scoped windows named by their model and kind,
# and the entries that name none.

import json
import time

TOKEN = "sk-ant-oat01-FAKE-ACCESS"


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": TOKEN, "expiresAt": int((time.time() + 3600) * 1000),
    "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
  }}))


def scoped(kind, model, percent, resets_at="2099-01-08T00:00:00Z"):
  return {"kind": kind, "scope": {"model": model}, "percent": percent, "resets_at": resets_at}


ROUTES = [("/api/oauth/usage", {
  "five_hour": "unlimited",
  "seven_day": {"utilization": "0%", "resets_at": "next Tuesday"},
  "limits": [
    "not an entry",
    {"kind": "weekly_all", "scope": None, "percent": 62.5, "resets_at": "2099-01-08T00:00:00Z"},
    {"kind": "weekly_surface", "scope": {"surface": "cowork"}, "percent": 5, "resets_at": "2099-01-08T00:00:00Z"},
    scoped("weekly_scoped", "Fable", 10),
    scoped("weekly_scoped", {"id": "claude-fable-5", "display_name": "Fable"}, 41.5),
    # The same model and window again is the same limit; another window of it is not.
    scoped("weekly_scoped", {"display_name": "Fable"}, 99),
    scoped("five_hour_scoped", {"display_name": "Fable"}, 20, "2099-01-01T05:00:00Z"),
    # A model with an id and no display name is named by its id; a day is a week; a reset can be epoch seconds.
    scoped("seven_day_scoped", {"id": "claude-sonnet-5"}, "7.5%", 4070908800),
    scoped("monthly_scoped", {"display_name": "Haiku"}, 130, "2099-02-01T00:00:00Z"),
    scoped("session_scoped", {"display_name": "Opus"}, 3, None),
    # A kind that names no window gives a title that is the model alone, and a reset that is no time gives none.
    scoped("mystery_scoped", {"display_name": "Mythos"}, 50, "soon"),
    scoped("weekly_scoped", {"display_name": "Negative"}, -5),
    scoped("weekly_scoped", {"display_name": "Missing"}, None),
    scoped("weekly_scoped", {"display_name": "", "id": ""}, 10),
  ],
})]

WEEK = "2099-01-08T00:00:00+00:00"
LIMITS = [
  {"label": "Weekly (7-day)", "percent": 0.0, "resetsAt": ""},
  {"label": "Fable Weekly", "title": "Fable Weekly", "percent": 0.415, "resetsAt": WEEK},
  {"label": "Fable Session", "title": "Fable Session", "percent": 0.2, "resetsAt": "2099-01-01T05:00:00+00:00"},
  {"label": "claude-sonnet-5 Weekly", "title": "claude-sonnet-5 Weekly", "percent": 0.075, "resetsAt": "2099-01-01T00:00:00+00:00"},
  {"label": "Haiku Monthly", "title": "Haiku Monthly", "percent": 1.0, "resetsAt": "2099-02-01T00:00:00+00:00"},
  {"label": "Opus Session", "title": "Opus Session", "percent": 0.03, "resetsAt": ""},
  {"label": "Mythos", "title": "Mythos", "percent": 0.5, "resetsAt": ""},
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Max 5x", (record["ready"], record["tierLabel"])
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert record["limits"] == LIMITS, record["limits"]
