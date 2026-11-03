# SPDX-License-Identifier: GPL-3.0-only
# A machine with two registered Codex accounts: the primary one, signed in by
# CODEX_ACCESS_TOKEN, and a work one with a home of its own, which is the active
# account. Each home's app-server answers for its own login, and only the
# primary one is handed the token.

import base64
import json
import stat
import time

LOG = None
ENV = {"CODEX_ACCESS_TOKEN": "FAKE-access-token"}

MAIN = {"rateLimits": {"limitId": "codex", "planType": "pro", "primary": {"usedPercent": 60, "windowDurationMins": 300, "resetsAt": 4070912400}}}
WORK = {"rateLimits": {"limitId": "codex", "planType": "plus", "primary": {"usedPercent": 10, "windowDurationMins": 300, "resetsAt": 4070916000}, "secondary": {"usedPercent": 90, "windowDurationMins": 10080, "resetsAt": 4071513600}}}

# Answers with the limits of the home it runs in, and logs which home that is and
# whether it was handed the token.
APP_SERVER = '''#!/usr/bin/python3
import json, os, sys
LOG, BY_HOME = %r, json.loads(%r)
home = os.environ["CODEX_HOME"]
open(LOG, "a").write(json.dumps({"home": home, "token": os.environ.get("CODEX_ACCESS_TOKEN")}) + "\\n")
for raw in sys.stdin:
  message = json.loads(raw)
  if "id" not in message:
    continue
  result = {} if message["method"] == "initialize" else BY_HOME[os.path.basename(home)]
  sys.stdout.write(json.dumps({"id": message["id"], "result": result}) + "\\n")
  sys.stdout.flush()
'''


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()
  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


def setup(home, bin):
  global LOG
  LOG = home / "codex-app-server.log"
  stub = bin / "codex"
  stub.write_text(APP_SERVER % (str(LOG), json.dumps({".codex": MAIN, "codex-work": WORK})))
  stub.chmod(stub.stat().st_mode | stat.S_IXUSR)

  main, work = home / ".codex", home / "accounts" / "codex-work"
  work.mkdir(parents=True)
  claims = {"https://api.openai.com/auth": {"chatgpt_user_id": "user-FAKE-2"}}
  (work / "auth.json").write_text(json.dumps({
    "auth_mode": "chatgpt",
    "tokens": {"id_token": jwt(claims), "access_token": "FAKE-access", "refresh_token": "FAKE-refresh", "account_id": "acct-FAKE-2"},
  }))
  state = home / ".local" / "state" / "cachyos-agent" / "accounts"
  state.mkdir(parents=True)
  # The registry's plan for the primary is out of date: the app-server's wins.
  (state / "codex.json").write_text(json.dumps({
    "accounts": [
      {"id": "main", "label": "Main", "email": "main@FAKE.example", "plan": "Plus", "primary": True, "home": str(main)},
      {"id": "work", "label": "Work", "email": "work@FAKE.example", "plan": "", "primary": False, "home": str(work)},
    ],
    "active": "work",
    "switch": "auto",
    "threshold": 90,
  }))


def check(record, requests):
  assert requests == []
  main_limits = [{"label": "5h window", "percent": 0.6, "resetsAt": "2099-01-01T01:00:00+00:00"}]
  work_limits = [
    {"label": "5h window", "percent": 0.1, "resetsAt": "2099-01-01T02:00:00+00:00"},
    {"label": "Weekly (7-day)", "percent": 0.9, "resetsAt": "2099-01-08T00:00:00+00:00"},
  ]
  # The top level describes the active account, the work one.
  assert record["ready"] is True and record["tierLabel"] == "Plus" and record["limits"] == work_limits, (record["tierLabel"], record["limits"])
  assert record["accountSwitch"] == {"mode": "auto", "threshold": 90}, record.get("accountSwitch")
  assert record["limitsStale"] is False and abs(time.time() * 1000 - record["limitsFetchedAt"]) < 60_000

  accounts = {account["id"]: account for account in record["accounts"]}
  assert [account["id"] for account in record["accounts"]] == ["main", "work"]
  main, work = accounts["main"], accounts["work"]
  assert (main["label"], main["email"], main["plan"], main["active"], main["primary"]) == ("Main", "main@FAKE.example", "Pro 200", False, True), main
  assert (work["label"], work["email"], work["plan"], work["active"], work["primary"]) == ("Work", "work@FAKE.example", "Plus", True, False), work
  assert main["limits"] == main_limits and work["limits"] == work_limits
  for account in (main, work):
    assert account["stale"] is False and abs(time.time() * 1000 - account["fetchedAt"]) < 60_000, account
    assert account["usageStatusText"] == "" and account["authHelpText"] == "" and account["retryAdvised"] is False, account

  # One app-server per home, in the home it answers for; the token went to the primary alone.
  starts = [json.loads(line) for line in LOG.read_text().splitlines()]
  home = str(LOG.parent)
  assert starts == [
    {"home": home + "/.codex", "token": "FAKE-access-token"},
    {"home": home + "/accounts/codex-work", "token": None},
  ], starts
