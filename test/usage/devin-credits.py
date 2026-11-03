# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to the Devin CLI on a monthly credit plan that has not
# run a session here: only the status cache the CLI wrote two hours ago (so it
# is reported stale) says anything. The plan has no name of its own, only tier
# numbers, and hides its weekly window.

import base64
import json
import os
import time
from pathlib import Path

NOW = int(time.time())
PLAN_END = 4_000_000_000  # 2096-10-02, still ahead
FETCHED = NOW - 2 * 3600


def varint(value):
  out = b""
  while True:
    byte, value = value & 0x7F, value >> 7
    out += bytes([byte | (0x80 if value else 0)])
    if not value:
      return out


def field(number, value):
  if isinstance(value, int):
    return varint(number << 3) + varint(value)
  data = value.encode() if isinstance(value, str) else value
  return varint(number << 3 | 2) + varint(len(data)) + data


def user_status():
  """A GetUserStatus answer as the CLI caches it. The plan's tier (1, Max)
  outranks the status tier (10, Pro); its credit grants are 12/13/14 and the
  credits used 6/5/7 in the PlanStatus (prompt, flow, flex), whose 3 holds the
  plan's end. A dated weekly reset (18) that the plan hides (37) is no window,
  and no daily reset (17) on a plan that is not billed by quota is none either."""
  plan = field(1, 18) + field(12, 500) + field(13, 1000) + field(14, 120) + field(37, 1)
  status = field(1, plan) + field(3, field(1, PLAN_END)) + field(5, 640) + field(6, 125) + field(7, 90) + field(18, 4_000_604_800)
  return field(10, 2) + field(13, status)


def setup(home, bin):
  credentials = home / ".local" / "share" / "devin" / "credentials.toml"
  credentials.parent.mkdir(parents=True)
  credentials.write_text('token = "FAKE-DEVIN-TOKEN"\n')
  os.utime(credentials, (NOW - 86400, NOW - 86400))
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "devin" / "cli"
  cache.mkdir(parents=True)
  (cache / "user_status.9f3e.bin").write_text(json.dumps({"payload": base64.b64encode(user_status()).decode(), "fetched_at_secs": FETCHED}))


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is False, (record["ready"], record["hasLocalStats"])
  assert record["usageStatusText"] == "" and record["authHelpText"] == "", (record["usageStatusText"], record["authHelpText"])
  assert record["tierLabel"] == "Max", record["tierLabel"]
  resets = "2096-10-02T07:06:40+00:00"
  assert record["limits"] == [
    {"label": "Prompt credits", "percent": 0.25, "resetsAt": resets},
    {"label": "Flow credits", "percent": 0.64, "resetsAt": resets},
    {"label": "Flex credits", "percent": 0.75, "resetsAt": resets},
  ], record["limits"]
  assert record["limitsFetchedAt"] == FETCHED * 1000 and record["limitsStale"] is True, (record["limitsFetchedAt"], record["limitsStale"])
  assert record["totalSessions"] == 0 and record["totalPrompts"] == 0 and record["modelUsage"] == {}, (record["totalSessions"], record["totalPrompts"], record["modelUsage"])
