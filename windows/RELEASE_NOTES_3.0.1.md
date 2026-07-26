WeatherFast 3.0.1 brings weather alerts into the city's own weather report and
makes alert text far easier to read.

## Weather alerts in the full weather report

Previously, the city list could mark a city as having an alert, but opening
that city's Full Weather showed no sign of it — the alert was only reachable
from the Weather menu. Alerts now appear in the report itself, directly under
the city heading and ahead of the forecast:

```
Report for Madison, Wisconsin
ALERTS
MODERATE: Heat Advisory - Heat Advisory issued July 26 at 5:10AM CDT... - until Sun Jul 26 09:00 PM
CURRENT
...
```

- Press **Enter** on an alert to open its full text: description, safety
  instructions, affected areas, valid period, and a button to open the
  official NWS page.
- A check that fails is never reported as "no alerts". It says so plainly and
  offers a line you can press Enter on to try again.
- Cities outside the US omit the section entirely rather than showing an empty
  one, since the National Weather Service has no coverage there.
- Alerts are shown for today only — a warning in force now says nothing about
  another day's forecast.

## Clearer alert list entries

The city list previously appended a bare `[ALERT]`, which read identically for
an extreme tornado warning and a minor frost advisory. It now names the most
severe alert, and how many others there are:

```
Madison, Wisconsin - 78°F, Cloudy (High: 80°F, Low: 60°F)  [EXTREME: Tornado Warning, +1 more]
```

The window title also leads with the severity when a city has active alerts, so
a screen reader announces it on entering the report.

## Fixes

- **Alert text no longer breaks mid-sentence.** The National Weather Service
  hard-wraps its text at about 68 columns, and each of those physical lines was
  becoming its own row — stranding fragments like "illnesses." alone on a line.
  Alert text is now rejoined into whole paragraphs, one per row. This affects
  every place alerts are shown, including the Weather Alerts sheet and the
  alert browser.
- **Enter now works on the weather report.** Rows in the report list never
  received the Enter key, because the list was created without the style that
  lets a control claim it.
- A city row's alert marker is no longer lost when its weather refreshes.
