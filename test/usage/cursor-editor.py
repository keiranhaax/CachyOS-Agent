# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Cursor CLI sign-in has lapsed but whose Cursor editor is
# signed in: the editor's token, kept in state.vscdb, is the one that is sent.

import base64
import json
import os
import sqlite3
from pathlib import Path


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


CLI_TOKEN = jwt({"sub": "user_FAKE_CLI", "exp": 1577836800})  # lapsed in 2020
EDITOR_TOKEN = jwt({"sub": "user_FAKE_EDITOR", "exp": 4102444800})
BASE = "https://api2.cursor.sh/aiserver.v1.DashboardService/"


def setup(home, bin):
  config = Path(os.environ["XDG_CONFIG_HOME"])
  (config / "cursor").mkdir(parents=True, exist_ok=True)
  (config / "cursor" / "auth.json").write_text(json.dumps({"accessToken": CLI_TOKEN}))
  database = config / "Cursor" / "User" / "globalStorage" / "state.vscdb"
  database.parent.mkdir(parents=True, exist_ok=True)
  database.unlink(missing_ok=True)
  conn = sqlite3.connect(database)
  conn.execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
  conn.execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', ?)", (EDITOR_TOKEN,))
  conn.execute("INSERT INTO ItemTable VALUES ('cursorAuth/refreshToken', 'FAKE-EDITOR-REFRESH')")
  conn.commit()
  conn.close()


ROUTES = [
  ("GetCurrentPeriodUsage", {"billingCycleEnd": "1798761600000", "planUsage": {"totalPercentUsed": 10}}),
  ("GetPlanInfo", {"planInfo": {"planName": "Pro"}}),
  ("GetAggregatedUsageEvents", {}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  assert record["usageStatusText"] == "" and record["limitsStale"] is False
  assert record["limits"] == [{"label": "Included total", "title": "Monthly", "percent": 0.1, "resetsAt": "2027-01-01T00:00:00+00:00"}], record["limits"]
  assert len(requests) == 9, [r["url"] for r in requests]
  tokens = {r["headers"]["authorization"] for r in requests}
  assert tokens == {f"Bearer {EDITOR_TOKEN}"}, "the lapsed CLI token went out, or the editor's did not"
