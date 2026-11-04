# SPDX-License-Identifier: GPL-3.0-only
# A machine with no key in the environment or the config file, whose omp agent
# directory has a .env (a comment, a quoted `export` line for a Zhipu key) and
# whose pi one has another key, which omp's outranks.

KEY = "sk-FAKE-ZHIPU-OMP"


def setup(home, bin):
  omp = home / ".omp" / "agent"
  omp.mkdir(parents=True)
  (omp / ".env").write_text(f"# Z.ai keys\nOTHER=1\nexport ZHIPUAI_API_KEY='{KEY}'\n")
  pi = home / ".pi" / "agent"
  pi.mkdir(parents=True)
  (pi / ".env").write_text("ZAI_API_KEY=sk-FAKE-ZAI-PI\n")


ROUTES = [("/api/monitor/usage/quota/limit", {
  "success": True,
  "data": {"level": "max", "limits": [{"type": "CREDIT_LIMIT", "unit": 3, "number": 5, "percentage": 20, "nextResetTime": 0}]},
})]


def check(record, requests):
  # A Zhipu key is the Zhipu platform's, so the China host is asked.
  assert [r["url"] for r in requests] == ["https://open.bigmodel.cn/api/monitor/usage/quota/limit"], requests
  assert requests[0]["headers"]["authorization"] == KEY, "omp's key was not sent, unquoted"
  assert record["ready"] is True and record["tierLabel"] == "Max", (record["ready"], record["tierLabel"])
  # A zero reset is no reset.
  assert record["limits"] == [{"label": "Session (5-hour)", "percent": 0.2, "resetsAt": ""}], record["limits"]
