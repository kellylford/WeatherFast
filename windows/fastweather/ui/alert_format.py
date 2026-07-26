"""Shared formatting for weather alerts (list rows, city rows, and full detail).

Everything a screen reader announces about an alert is built here so the city
list, the detailed view's ALERTS section, and the alert sheets stay consistent.
"""

from datetime import datetime

# Sentinel payload for the ALERTS section's "check again" row.
RETRY = "__retry__"


def fmt_time(iso):
    if not iso:
        return ""
    try:
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).strftime("%a %b %d %I:%M %p")
    except Exception:
        return iso


def summary_row(alert):
    """One-line list label: '[Severity] Event - headline'."""
    text = f"[{alert.severity}] {alert.event}"
    if alert.headline and alert.headline != alert.event:
        text += f" - {alert.headline}"
    return text


def highest(alerts):
    """The most critical alert in a list (iOS ListRowView.highestSeverityAlert)."""
    if not alerts:
        return None
    return min(alerts, key=lambda a: a.sort_key)


def city_row_badge(alerts):
    """Suffix appended to a My Cities row, naming the worst active alert.

    A bare '[ALERT]' can't distinguish an Extreme tornado warning from a Minor
    frost advisory, so the severity and event are spoken on the row itself.
    """
    top = highest(alerts)
    if top is None:
        return ""
    more = len(alerts) - 1
    extra = f", +{more} more" if more > 0 else ""
    return f"  [{top.severity.upper()}: {top.event}{extra}]"


def detail_row(alert):
    """One alert as a single arrow-stop in the detailed view's ALERTS section."""
    parts = [f"{alert.severity.upper()}: {alert.event}"]
    if alert.headline and alert.headline != alert.event:
        parts.append(alert.headline)
    until = fmt_time(alert.ends)
    if until:
        parts.append(f"until {until}")
    return " - ".join(parts)


def section_lines(state, alerts=None, error=""):
    """The ALERTS block for the detailed view, mirroring iOS WeatherAlertsSection.

    Returns ``(lines, row_actions)`` where ``row_actions`` maps an index within
    ``lines`` to what activating that line does: a WeatherAlert opens its sheet,
    and RETRY re-runs the check (the iOS section's Retry button). ``state`` is
    one of: 'loading', 'error', 'ok', or 'off' (non-US, where NWS has no
    coverage and the section is omitted entirely).
    """
    if state == "off":
        return [], {}

    lines = ["ALERTS"]
    row_alerts = {}

    if state == "loading":
        lines.append("Checking for alerts...")
    elif state == "error":
        # Safety invariant: a failed check is never reported as "no alerts".
        lines.append("Could not check for alerts.")
        if error:
            lines.append(f"Reason: {error}")
        lines.append("This does NOT mean there are no alerts.")
        row_alerts[len(lines)] = RETRY
        lines.append("Press Enter here to check again.")
    elif not alerts:
        lines.append("No active alerts.")
    else:
        # No count or "press Enter" preamble: the alert rows speak for
        # themselves and an extra arrow-stop just delays reaching them.
        for a in alerts:
            row_alerts[len(lines)] = a
            lines.append(detail_row(a))

    lines.append("")
    return lines, row_alerts


def unwrap(text):
    """Rejoin NWS text into logical paragraphs.

    NWS hard-wraps its products at ~68 columns, so a sentence arrives split
    across several physical lines ("...may cause heat\\nillness to occur."").
    Rendering those verbatim as list rows strands fragments like "illness" on a
    row of their own. Paragraphs break on blank lines and on the bullet markers
    NWS uses ('* WHAT...', '* IMPACTS...'); everything else is a continuation.
    """
    paragraphs = []
    current = []

    def flush():
        if current:
            paragraphs.append(" ".join(current))
            current.clear()

    for raw in (text or "").split("\n"):
        line = raw.strip()
        if not line or line in ("&&", "$$"):  # NWS product delimiters
            flush()
            continue
        if line.startswith("*"):
            flush()
        current.append(line)
    flush()
    return paragraphs


def detail_lines(alert):
    """Full accessible detail for a single alert, as a list of lines."""
    lines = [f"{alert.severity.upper()} - {alert.event}"]
    if alert.headline and alert.headline != alert.event:
        lines.append(alert.headline)
    lines.append("")
    if alert.area:
        lines.append(f"Affected Areas: {alert.area}")
    when = " - ".join(x for x in [fmt_time(alert.onset), fmt_time(alert.ends)] if x)
    if when:
        lines.append(f"Valid: {when}")
    lines.append("")
    if alert.description:
        lines.append("Details:")
        for para in unwrap(alert.description):
            lines.append(f"  {para}")
        lines.append("")
    if alert.instruction:
        lines.append("Safety Instructions:")
        for para in unwrap(alert.instruction):
            lines.append(f"  {para}")
        lines.append("")
    lines.append(f"Source: {alert.source}")
    if alert.details_url:
        lines.append(f"More info: {alert.details_url}")
    return lines
