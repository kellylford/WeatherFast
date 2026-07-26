WeatherFast 3.0.1 is a complete rebuild of the Windows app — same free data (no
account or API key), with a much larger feature set, a proper installer, and
signed binaries. It replaces 3.0.0, which has been withdrawn.

## Install

- **Installer (recommended):** `WeatherFast-3.0.1-Setup.exe` — per-user install,
  Start Menu shortcut, no admin required, and automatic updates going forward.
- **Portable:** `WeatherFast-portable.zip` — extract the folder anywhere and run
  `WeatherFast.exe` from it. Nothing is installed. Keep the folder together; the
  application needs the `_internal` folder beside the executable.

Both downloads are code-signed.

### If you already have 3.0.0

Please **uninstall 3.0.0 first** (Settings → Apps, or the Start Menu uninstall
entry), then install 3.0.1. 3.0.0 had a packaging fault that could leave the
application running invisibly after you closed it, holding its own files open —
which made in-place updates fail with "DeleteFile failed; code 5. Access is
denied." That is fixed in 3.0.1, but a clean install is the reliable way across.

If an install ever does report that error, close WeatherFast (or end
`WeatherFast.exe` in Task Manager) and run the installer again.

## Highlights

- **Place search** for cities, ZIP/postal codes, addresses, and specific places
  (airports, universities, landmarks), always with a selectable results list.
- **Full weather:** current conditions, a plain-language "Today's Outlook",
  24-hour hourly, and a multi-day forecast, with day-by-day navigation.
- **Weather alerts:** shown in the city's own weather report, plus a full
  **alert browser** for the US and Canada — filter by severity and hazard type
  and drill into affected areas.
- **Expected Precipitation** next-hour nowcast, **Weather Around Me** (eight
  directions plus a directional explorer), **Historical** weather (single day,
  same-day-across-years, daily browse), **Marine**, **Astronomy (moon)**, and a
  configurable **My Data** section (marine, air quality, pollen, and more).
- **Browse cities** by US state or country with sorting and favorites.
- Configurable fields and units (wind in mph / km/h / m/s), defaulting to your
  Windows region on first run.
- **Automatic updates** and a built-in **User Guide** (Help, or F1).

## New in 3.0.1

**Weather alerts appear in the weather report.** In 3.0.0 the city list could
mark a city as having an alert, but opening that city's Full Weather showed no
sign of it — the alert was only reachable from the Weather menu. Alerts now sit
directly under the city heading, ahead of the forecast:

```
Report for Madison, Wisconsin
ALERTS
MODERATE: Heat Advisory - until Sun Jul 26 09:00 PM
CURRENT
...
```

Press **Enter** on an alert for its full text: description, safety
instructions, affected areas, valid period, and a link to the official NWS
page. A check that fails is never reported as "no alerts" — it says so plainly
and offers a line you can press Enter on to try again. Cities outside the US
omit the section, since the National Weather Service has no coverage there.

**The city list names the alert.** Instead of a bare `[ALERT]`, which read the
same for an extreme tornado warning and a minor frost advisory, the row now
names the most severe alert and how many others there are:

```
Madison, Wisconsin - 78°F, Cloudy (High: 80°F, Low: 60°F)  [EXTREME: Tornado Warning, +1 more]
```

The window title also leads with the severity, so a screen reader announces it
on entering the report.

**Alert text no longer breaks mid-sentence.** The National Weather Service
hard-wraps its bulletins at about 68 columns, and each of those physical lines
was becoming its own row — stranding fragments like "illnesses." alone on a
line. Alert text is now rejoined into whole paragraphs.

**Other fixes:**

- Enter now works on rows in the weather report.
- A city's alert marker is no longer lost when its weather refreshes.
- Fixed the packaging fault described under *If you already have 3.0.0*, which
  also prevented automatic updates from installing.

Full user guide: https://kellylford.github.io/WeatherFast/
