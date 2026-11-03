# SPDX-License-Identifier: GPL-3.0-only
# A machine with a DeepSeek key in the environment and a funded account.

ENV = {"DEEPSEEK_API_KEY": "sk-FAKE-DEEPSEEK"}

ROUTES = [("/user/balance", {
  "is_available": True,
  "balance_infos": [
    {"currency": "CNY", "total_balance": "0.00", "granted_balance": "0.00", "topped_up_balance": "0.00"},
    {"currency": "USD", "total_balance": "7.25", "granted_balance": "1.00", "topped_up_balance": "6.25"},
  ],
})]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Prepaid", "not reported as a prepaid account"
  # The entry that holds credit is the balance, not the empty CNY one first in the list.
  assert record["balance"]["remaining"] == 7.25 and record["balance"]["currency"] == "USD", record["balance"]
  assert [r["url"] for r in requests] == ["https://api.deepseek.com/user/balance"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer sk-FAKE-DEEPSEEK", "the key was not sent"
  assert record["usageStatusText"] == "" and record["limitsStale"] is False
