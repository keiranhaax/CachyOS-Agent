# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in with firectl (key and account in ~/.fireworks/auth.ini)
# whose key can read the live balance, with no usage this month.

import json
from urllib.parse import urlsplit


def setup(home, bin):
  (home / ".fireworks").mkdir(exist_ok=True)
  (home / ".fireworks" / "auth.ini").write_text("[default]\naccount_id = acme-co\napi_key = fw-FAKE-FIRECTL\n")
  config = home / ".config" / "cachyos-agent"
  config.mkdir(parents=True, exist_ok=True)
  (config / "fireworks.json").write_text(json.dumps({"fundedAmount": 50}))


ROUTES = [
  ("/billingUsage", {}),
  (":getBalance", {"balance": {"currencyCode": "USD", "units": "41", "nanos": 250000000}}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Prepaid"
  # The balance is the account's own, so it is not an estimate; what is gone is the funding less it.
  assert record.get("balance") == {"remaining": 41.25, "funded": 50.0, "spent": 8.75, "currency": "USD", "estimated": False}, record.get("balance")
  assert record["hasLocalStats"] is True and record["modelUsage"] == {} and record["activeDays"] == 0 and record["todayTotalTokens"] == 0
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
  # The account comes from the sign-in, so none is looked up, and no cost is asked for.
  assert [urlsplit(r["url"]).path for r in requests] == ["/v1/accounts/acme-co/billingUsage", "/v1/accounts/acme-co:getBalance"], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer fw-FAKE-FIRECTL" for r in requests), "the firectl key was not sent"
