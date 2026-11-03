# SPDX-License-Identifier: GPL-3.0-only
# A machine that signed in to a different Devin account ten minutes ago and has
# not started the CLI since: the one status cache is from the account before,
# so the quota is unknown rather than the old account's.

import json
import os
import time
from pathlib import Path

NOW = int(time.time())


def setup(home, bin):
  credentials = home / ".local" / "share" / "devin" / "credentials.toml"
  credentials.parent.mkdir(parents=True)
  credentials.write_text('token = "FAKE-DEVIN-TOKEN"\n')
  os.utime(credentials, (NOW - 600, NOW - 600))
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "devin" / "cli"
  cache.mkdir(parents=True)
  # A UserStatus holding only the plan tier, field 10 = 16 ("Devin Pro"), fetched an hour ago.
  (cache / "user_status.4b1c.bin").write_text(json.dumps({"payload": "UBA=", "fetched_at_secs": NOW - 3600}))


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is False, (record["ready"], record["hasLocalStats"])
  assert record["tierLabel"] == "" and record["limits"] == [] and record["limitsFetchedAt"] == 0, record["tierLabel"]
  assert record["usageStatusText"] == "Devin limits unavailable", repr(record["usageStatusText"])
  assert record["authHelpText"] == "Devin hasn't recorded its quota since it was signed in. Start Devin to refresh it.", repr(record["authHelpText"])
