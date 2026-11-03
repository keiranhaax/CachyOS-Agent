# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Fireworks key in the environment and credits noted in
# fireworks.json. The key cannot read the account balance (no billing role),
# so the record carries the estimate: credits minus rated costs since the
# funding date. The usage history spans two pages and two models.

import json
from datetime import date, datetime, time, timedelta, timezone
from urllib.parse import parse_qs, urlsplit

ENV = {"FIREWORKS_API_KEY": "fw-FAKE-KEY"}

TODAY = datetime.now().astimezone().date()
YESTERDAY = TODAY - timedelta(days=1)


def bucket_start(day: date) -> str:
  # A day bucket starts at local midnight, which the API reports in UTC.
  return datetime.combine(day, time.min).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def setup(home, bin):
  config = home / ".config" / "cachyos-agent"
  config.mkdir(parents=True, exist_ok=True)
  (config / "fireworks.json").write_text(json.dumps({"fundedAmount": "100", "fundedAt": "2026-07-01"}))


def usage_page(request):
  token = parse_qs(urlsplit(request.full_url).query).get("pageToken")
  if token == ["page-2"]:
    return {"serverlessCosts": [
      {  # No uncachedPromptTokens: the uncached part is the prompt minus the cached.
        "startTime": bucket_start(TODAY), "group": {"model_name": "accounts/fireworks/models/llama-v3p3-70b-instruct"},
        "promptTokens": "500", "cachedPromptTokens": "0", "completionTokens": "100",
      },
    ]}
  return {"nextPageToken": "page-2", "serverlessCosts": [
    {
      "startTime": bucket_start(TODAY), "group": {"model_name": "accounts/fireworks/models/llama-v3p3-70b-instruct"},
      "promptTokens": "1000", "cachedPromptTokens": "200", "uncachedPromptTokens": "800", "completionTokens": "300",
    },
    {
      "startTime": bucket_start(YESTERDAY), "group": {"model_name": "accounts/fireworks/models/deepseek-v3p1"},
      "promptTokens": "2000", "cachedPromptTokens": "0", "uncachedPromptTokens": "2000", "completionTokens": "50",
    },
  ]}


ROUTES = [
  ("/v1/accounts?", {"accounts": [{"name": "accounts/acme-co", "createTime": "2026-01-15T10:00:00Z"}]}),
  ("/billingUsage", usage_page),
  (":getBalance", (403, {"code": 7, "message": "PERMISSION_DENIED"})),
  ("/usageCosts:query", {"subtotal": {"currencyCode": "USD", "units": "12", "nanos": 340000000}}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Prepaid" and record.get("scope") == "account", "not an account's prepaid usage"
  assert record["hasPromptStats"] is False and record["hasLocalStats"] is True
  assert record.get("balance") == {"remaining": 87.66, "funded": 100.0, "spent": 12.34, "currency": "USD", "estimated": True}, record.get("balance")
  # Tokens: the uncached prompt, the completion, and the cached prompt, per model and day.
  assert record["todayTotalTokens"] == 1900 and record["todayTokensByModel"] == {"llama-v3.3-70b-instruct": 1900}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    "llama-v3.3-70b-instruct": {"inputTokens": 1300, "outputTokens": 400, "cacheReadInputTokens": 200, "cacheCreationInputTokens": 0},
    "deepseek-v3.1": {"inputTokens": 2000, "outputTokens": 50, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["recentDays"][-2:] == [{"date": YESTERDAY.isoformat(), "messageCount": 2050}, {"date": TODAY.isoformat(), "messageCount": 1900}], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == [YESTERDAY.isoformat(), TODAY.isoformat()]
  assert record["totalPrompts"] == 0 and record["limits"] == []
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
  assert abs(record["limitsFetchedAt"] / 1000 - datetime.now().timestamp()) < 120, record["limitsFetchedAt"]

  assert [urlsplit(r["url"]).path for r in requests] == [
    "/v1/accounts", "/v1/accounts/acme-co/billingUsage", "/v1/accounts/acme-co/billingUsage",
    "/v1/accounts/acme-co:getBalance", "/v1/accounts/acme-co/usageCosts:query",
  ], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer fw-FAKE-KEY" for r in requests), "the key was not sent on every request"
  query = parse_qs(urlsplit(requests[1]["url"]).query)
  assert query["usageType"] == ["SERVERLESS"] and query["groupBy"] == ["model_name"], query
  assert query["startTime"] == [bucket_start(TODAY - timedelta(days=29))] and query["endTime"] == [bucket_start(TODAY + timedelta(days=1))], query
  assert parse_qs(urlsplit(requests[2]["url"]).query)["pageToken"] == ["page-2"], "the second page was not asked for"
  # The cost is asked for the account from the funding date to now.
  cost = json.loads(requests[4]["body"])
  assert requests[4]["method"] == "POST" and cost["scope"] == "ACCOUNT" and cost["startTime"] == "2026-07-01T00:00:00Z", cost
