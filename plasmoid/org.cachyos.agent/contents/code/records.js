// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Omarchy shell/plugins/agents/Panel.qml and Main.qml (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
.pragma library

// What the widget draws, derived from the output of `cachyos-agent usage --json`:
// a JSON array of usage records in Omarchy's format (its docs/agent-usage-collectors.md).
// Everything here is a pure function of its arguments, with the clock passed in
// as `now` (milliseconds since the epoch), so test/cases/80-plasmoid.sh can run
// it under qml6 without a desktop. A collector may leave a field out or fill it
// badly, so every field is checked here and none is trusted.

// A limit this full is drawn in the warning colour, and a prepaid balance with
// this little of its funding left is low.
const HIGH = 0.9;
const LOW = 0.1;

const CURRENCY_SYMBOLS = { USD: "$", EUR: "€", GBP: "£" };

const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);

// A token or prompt count: a finite number above zero, else zero.
const count = value => {
    const number = Number(value);
    return Number.isFinite(number) && number > 0 ? number : 0;
};

const capitalize = value => {
    const text = String(value || "");
    return text.charAt(0).toUpperCase() + text.slice(1);
};

// An ISO 8601 time as Python's datetime.fromisoformat reads it, which is what
// the collectors checked before they passed the service's own string through:
// the date and time with or without their separators, a fraction, and an
// offset as Z, +HH, +HH:MM or +HHMM. A time with no offset is UTC, as in the
// collectors and the sibling `cachyos-agent usage` report; Date.parse would
// read it as local time and be hours out, and it cannot read the basic form
// at all. Milliseconds since the epoch, or NaN for anything else.
const ISO_TIME = /^(\d{4})-?(\d{2})-?(\d{2})[T ](\d{2}):?(\d{2})(?::?(\d{2})(?:[.,](\d{1,3})\d*)?)?(?:Z|([+-]\d{2})(?::?(\d{2}))?)?$/;

function parseTime(value) {
    const parts = ISO_TIME.exec(String(value || "").trim());
    if (parts === null)
        return NaN;
    const [, year, month, day, hour, minute, second, fraction, zoneHours, zoneMinutes] = parts;
    const zone = zoneHours === undefined ? "Z" : zoneHours + ":" + (zoneMinutes || "00");
    return Date.parse(year + "-" + month + "-" + day + "T" + hour + ":" + minute + ":" + (second || "00") + "." + (fraction || "0").padEnd(3, "0") + zone);
}

// "3d 4h", "2h 10m" or "12m"; never less than a minute.
function duration(ms) {
    const minutes = Math.max(1, Math.floor(ms / 60000));
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);
    if (days > 0)
        return days + "d " + (hours % 24) + "h";
    if (hours > 0)
        return hours + "h " + (minutes % 60) + "m";
    return minutes + "m";
}

// The line under a limit: when its window resets. resetMs is 0 for a window
// with no reset time. A window whose reset has passed has nothing to count
// down to, as in the `cachyos-agent usage` report.
function resetText(resetMs, now) {
    return resetMs > now ? "resets in " + duration(resetMs - now) : "";
}

// 1234 -> "1.2K". The threshold sits just under each unit so that 999950
// reads 1.0M and never 1000.0K.
function tokens(value) {
    for (const [unit, size] of [["B", 1e9], ["M", 1e6], ["K", 1e3]]) {
        if (value >= size * 0.99995)
            return (value / size).toFixed(1) + unit;
    }
    return String(Math.round(value));
}

function money(value, currency) {
    const code = String(currency || "USD").toUpperCase();
    return (CURRENCY_SYMBOLS[code] || code + " ") + value.toFixed(2);
}

// One limit window as the collector wrote it: percent is a fraction of 0..1,
// resetMs is 0 for a window with no reset time that can be read. Nothing here
// depends on the clock, because the widget reads the records every few minutes
// and its clock moves in between: limitState says how the window reads at a
// given moment. A window without a percent is dropped; one without a reset
// time is kept as it is.
function limitView(entry) {
    if (!isObject(entry))
        return null;
    const percent = Number(entry.percent);
    if (!(percent >= 0))
        return null;
    const resetMs = parseTime(entry.resetsAt);
    return {
        title: String(entry.title || entry.label || "Limit"),
        percent: Math.min(percent, 1),
        resetMs: Number.isNaN(resetMs) ? 0 : resetMs
    };
}

function limitViews(entries) {
    return Array.isArray(entries) ? entries.map(limitView).filter(view => view !== null) : [];
}

// How a window reads at `now`. One whose reset time has passed is untouched
// again, as the collectors keep it, not unknown, so it reads 0% with nothing to
// count down to: the number the collector wrote ended with its window, however
// long ago the records were read.
function limitState(limit, now) {
    const elapsed = limit.resetMs > 0 && limit.resetMs <= now;
    const fraction = elapsed ? 0 : limit.percent;
    return {
        fraction: fraction,
        percentText: Math.round(fraction * 100) + "%",
        resetText: resetText(limit.resetMs, now),
        high: fraction >= HIGH
    };
}

// A prepaid agent's credit ledger. fraction is how much of the funding is
// left, or -1 when the collector does not know the funding and there is
// nothing to measure it against.
function balanceView(balance) {
    if (!isObject(balance))
        return null;
    const remaining = Number(balance.remaining);
    if (!(remaining >= 0))
        return null;
    const funded = count(balance.funded);
    const spent = count(balance.spent);
    return {
        remainingText: money(remaining, balance.currency) + " left",
        detailText: funded > 0 ? money(spent, balance.currency) + " spent of " + money(funded, balance.currency) + (balance.estimated === true ? " (estimated)" : "") : "",
        fraction: funded > 0 ? Math.min(remaining / funded, 1) : -1,
        low: funded > 0 && remaining / funded <= LOW
    };
}

// The records are written by `cachyos-agent usage update`, from a timer the
// person may never have switched on, and the widget does not run it by itself.
// A record this old is not today's, and the sibling `cachyos-agent usage` report
// says so at the same age (RECORD_OLD_SECONDS).
const RECORD_OLD_MS = 3600 * 1000;

// "Updated 2d 3h ago" for a record at least an hour old. updatedMs is the
// record's updatedAt as parseTime reads it, so a record with none, one that
// does not parse, or one from the future says nothing. Like limitState this is
// read at the widget's clock, which moves between reads: a record that turns
// an hour old while the popup is open says so.
function ageText(updatedMs, now) {
    return updatedMs <= now - RECORD_OLD_MS ? "Updated " + duration(now - updatedMs) + " ago" : "";
}

// What is wrong with an agent's numbers, one line each: a status is always
// said; its help only with it, or when the limits shown are old, because a
// healthy agent may still carry its sign-in hint. These lines do not change
// with the clock; checkedText adds the one that does.
function notes(status, help, stale) {
    const lines = [];
    const statusText = String(status || "");
    const helpText = String(help || "");
    if (statusText !== "" || (stale && helpText !== "")) {
        if (statusText !== "")
            lines.push(statusText);
        if (helpText !== "")
            lines.push(helpText);
    }
    return lines;
}

// How old the limits shown are, at the widget's clock: "" unless they are
// stale. The limits are called old only when there are limits, since a record
// with none has no numbers to doubt and its status already says why. A fetch
// time that is missing or lies ahead of the clock says the age is unknown.
function checkedText(stale, fetchedMs, now) {
    if (!stale)
        return "";
    return fetchedMs > 0 && fetchedMs <= now ? "Limits last checked " + duration(now - fetchedMs) + " ago" : "Limits may be out of date";
}

// recentDays holds seven {date, messageCount} entries; messageCount is the
// day's tokens.
function weekTokens(days) {
    return Array.isArray(days) ? days.reduce((sum, day) => sum + (isObject(day) ? count(day.messageCount) : 0), 0) : 0;
}

// An agent with two or more registered accounts lists each one's own limits;
// the record's top-level limits describe the active account.
function accountView(account) {
    const limits = limitViews(account.limits);
    const stale = account.stale === true;
    return {
        name: String(account.label || account.id || "Account"),
        plan: capitalize(account.plan),
        active: account.active === true,
        limits: limits,
        notes: notes(account.usageStatusText, account.authHelpText, stale),
        stale: stale && limits.length > 0,
        fetchedMs: count(account.fetchedAt)
    };
}

function agentView(record) {
    const today = count(record.todayTotalTokens);
    const week = weekTokens(record.recentDays);
    const accounts = Array.isArray(record.accounts) ? record.accounts.filter(isObject).map(accountView) : [];
    const limits = limitViews(record.limits);
    const stale = record.limitsStale === true;
    return {
        name: String(record.name || record.id || "Unknown agent"),
        ready: record.ready === true,
        plan: capitalize(record.tierLabel),
        limits: limits,
        balance: balanceView(record.balance),
        tokensText: today > 0 || week > 0 ? "Tokens: " + tokens(today) + " today, " + tokens(week) + " this week" : "",
        // How old the record is says nothing about one account, so it stays
        // apart from the notes: with several accounts each lists its own
        // limits and notes, and the agent's notes, which describe the active
        // one, are not drawn again, but the age of the record is. The times are
        // kept as numbers for ageText and checkedText to read at the clock.
        updatedMs: parseTime(record.updatedAt),
        notes: notes(record.usageStatusText, record.authHelpText, stale),
        stale: stale && limits.length > 0,
        fetchedMs: count(record.limitsFetchedAt),
        multi: accounts.length > 1,
        accounts: accounts
    };
}

// The collectors print a record for every agent they know, empty and not
// ready for one this machine does not use. Only an agent in use gets a section,
// and ready is what says so: it is the rule `cachyos-agent usage` lists by, so
// the report and the widget never disagree about a record.
function isShown(view) {
    return view.ready;
}

// "<command> failed: <first line of stderr>", or the exit code when it said nothing.
function failure(command, exitCode, stderr) {
    const line = String(stderr || "").split("\n").find(text => text.trim() !== "");
    return command + " failed" + (line ? ": " + line.trim() : " (exit " + exitCode + ")");
}

// The widget's one entry point: the exit code, stdout and stderr of
// `cachyos-agent usage --json` in, {agents, error} out. agents is what to draw;
// error is "" or the one line that says why there is nothing to draw. Nothing
// in it depends on the clock: what does is read from it at `now` by limitState,
// ageText and checkedText.
function load(exitCode, stdout, stderr) {
    if (exitCode !== 0)
        return { agents: [], error: failure("cachyos-agent usage --json", exitCode, stderr) };
    let records = null;
    try {
        records = JSON.parse(stdout);
    } catch (e) {
        // Not JSON: reported below with every other wrong answer.
    }
    if (!Array.isArray(records))
        return { agents: [], error: "cachyos-agent usage --json did not print a JSON array" };
    return { agents: records.filter(isObject).map(agentView).filter(isShown), error: "" };
}

// The tooltip: each agent that has limits with its fullest window at `now`.
function summary(agents, now) {
    return agents
        .filter(agent => agent.limits.length > 0)
        .map(agent => agent.name + " " + Math.round(100 * Math.max(...agent.limits.map(limit => limitState(limit, now).fraction))) + "%")
        .join(", ");
}

// Whether the panel icon should ask for attention, as Omarchy's bar icon
// lights up: any limit window nearly full, or a prepaid balance down to its
// last tenth. An agent's own limits are the account sessions start on, which
// is the one that runs out. Read at `now`, so a window that has reset since the
// records were read stops asking.
function alarming(agents, now) {
    return agents.some(agent => agent.limits.some(limit => limitState(limit, now).high) || (agent.balance !== null && agent.balance.low));
}
