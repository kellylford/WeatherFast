# WeatherFast User Guide

WeatherFast is a Windows desktop weather app. It shows current conditions, hourly and multi-day forecasts, weather alerts, and a range of specialized reports for any place you add. Weather comes from Open-Meteo, alerts from the US National Weather Service and Environment Canada, and place search from OpenStreetMap. No account, sign-up, or API key is needed.

## Contents

- Getting Started
- The Main Window
- Adding Places
- Browse Cities by State or Country
- Add My Location
- Full Weather View
- Configure Display and Units
- Per-City Weather Features
- Browse Weather Alerts
- Copy and Save Reports
- Updates
- Menus and Keyboard Reference
- Data and Privacy

## Getting Started

### Installing

There are two ways to run WeatherFast.

- **Installer** — run `WeatherFast-<version>-Setup.exe`. This performs a per-user install into your local application data folder and adds a Start Menu shortcut. It does not require administrator rights and installs only for your account. This is the recommended option, and the only one that receives automatic updates.
- **Portable** — download `WeatherFast-portable.zip` and extract it wherever you like, then run `WeatherFast.exe` from inside the extracted folder. Nothing is installed. Keep the folder intact: the `_internal` folder next to the executable is required, so move or copy the whole folder rather than the `.exe` on its own.

WeatherFast is code-signed. Even so, the first time you run it Windows SmartScreen may still show a warning, because SmartScreen also weighs how widely a given signature has been seen and a newer certificate has little history yet. If that happens, choose **More info** and then **Run anyway** to start the app. The warning should become less frequent over time.

### First launch

On its first run the app seeds a short list of default cities (including Madison, San Diego, Portland, London, Miami, and a few others) so you have something to look at immediately. You can remove any of these and add your own at any time.

Your data is stored under `%APPDATA%\WeatherFast` — this holds your saved city list (`city.json`), your display and unit settings (`config.json`), your browse favorites, and a small cache. If you previously used an older build named FastWeather, your saved cities and settings are copied over automatically the first time WeatherFast runs.

### Command-line options

WeatherFast accepts two optional command-line arguments:

| Option | Effect |
|--------|--------|
| `--reset` | Delete the saved city list before starting (the app then starts with defaults). |
| `-c <path>` or `--config <path>` | Use a specific city-list JSON file instead of the default. Useful for keeping separate lists. |

## The Main Window

The main window is titled **My Cities**. It has two areas: a place to add cities at the top and your city list below.

### Add New City area

- **Enter city** — a text field where you type a place to search for. Press Enter or the **Add City** button to search.
- **Browse Cities by State/Country** — opens the bulk city browser (see below).
- **Add My Location** — detects and adds your approximate location (see below).

### Your Cities list

The list shows every place you have added. Each row shows the place name followed by a short current summary — temperature, a sky description, a rain or snow marker when precipitation is falling, and today's high and low. For example: `Madison, Wisconsin, United States - 72°F, Partly Cloudy (High: 78°F, Low: 61°F)`.

For US places with an active weather warning, the row also ends with a marker naming the most serious alert in effect — for example `[EXTREME: Tornado Warning]`, or `[EXTREME: Tornado Warning, +1 more]` when there is more than one. This check runs only for US locations. Open the city's Full Weather to read the alert itself.

Below the list are buttons that act on the selected city:

| Button | Action |
|--------|--------|
| Move Up | Move the selected city one place earlier in the list. |
| Move Down | Move the selected city one place later in the list. |
| Remove | Remove the selected city (asks for confirmation). |
| Refresh | Re-fetch current weather for the selected city. |
| Full Weather | Open the detailed forecast for the selected city. |
| Configure | Open the display and units settings. |

Selecting a row and pressing Enter also opens Full Weather.

## Adding Places

Type into the **Enter city** field and press Enter (or click **Add City**). You can search by:

- City name, optionally with state or country (for example, `Portland Oregon`)
- ZIP or postal code
- A street address
- A specific place name such as an airport, university, or landmark

A **Search Results** window opens listing what was found (up to eight matches), even when there is only one result, so you can review and confirm before anything is added. Use the arrow keys to choose a result and press Enter (or **Add**) to add it; press Escape or **Cancel** to back out. If nothing matches, the app tells you and returns you to the search field.

### Specific place names

The **Settings** menu has a **Search: Use Specific Place Names (airports, landmarks)** option, on by default. When it is on, searches can return specific named places — an airport, a university, a park — with locality context added. When it is off, searches return city-level (locality-only) results instead. Turn it off if you prefer to always add the surrounding city rather than a specific point.

## Browse Cities by State or Country

Choose **Browse Cities by State/Country** (on the main window or the Cities menu) to add several places at once from a built-in list of cities.

The dialog has tabs:

- **U.S. States** — pick a state, then **Load Cities**.
- **International** — pick a country, then **Load Cities**.
- **Favorites** — your saved regions; pick one and **Load Favorite** to jump straight to it.

Once a region is loaded, its cities appear in a checklist. Check any number of them (or use **Select All** / **Deselect All**), then choose **Add Selected Cities** to add them to your list. Cities already in your list are skipped, and the app reports how many were added.

Use the **Sort** control to order the loaded cities by:

- Name A-Z or Z-A
- North to South or South to North
- East to West or West to East
- Temperature, warmest-to-coldest or coldest-to-warmest (this fetches current temperatures for the region first)

**Add Region to Favorites** saves the currently loaded state or country so you can reload it quickly from the Favorites tab later; the button toggles to remove it again. Favorites are saved whether you close the dialog with OK or Cancel.

## Add My Location

**Add My Location** (on the main window or the Cities menu) detects your approximate position and adds it as a place. It first asks you to confirm. If precise device location is available and permitted by Windows, that is used; otherwise the app falls back to an IP-based lookup (via ipapi.co) to estimate your city. The detected place is added to your list and selected. If your location cannot be determined, the app says so rather than adding anything.

## Full Weather View

Open **Full Weather** (button, Cities menu, or Enter on a selected city) to see the detailed forecast for a place. The view is a readable text report with these sections, depending on what you have enabled:

- **Alerts** — any active weather warnings for this place, shown first, immediately below the city heading. See below.
- **Current** — the conditions right now (temperature, and any other current fields you have turned on).
- **Today's Outlook** — plain-language highlights for the rest of today, such as when precipitation is most likely, high UV, or breezy conditions.
- **Hourly** — an hour-by-hour list starting from the current hour, covering the next 24 hours.
- **Daily** — a multi-day forecast, one line per day.

At the top of the view are navigation buttons:

| Button | Action |
|--------|--------|
| Back | Return to your city list. |
| Prev Day | Show the previous day's detail. |
| Today | Return to today. |
| Next Day | Show the next day's detail. |
| Configure | Open display and units settings. |

**Prev Day** and **Next Day** browse other days (up to about a week in either direction). When you move off today, the view shows that day's summary and its hour-by-hour detail. Press Escape or **Back** to return to the list.

### Alerts in the report

When a US place has active National Weather Service warnings, they appear at the top of the report, under the city name and ahead of the forecast, most serious first:

```
Report for Madison, Wisconsin
ALERTS
MODERATE: Heat Advisory - until Sun Jul 26 09:00 PM
CURRENT
...
```

Press Enter on an alert line to read the whole thing — description, safety instructions, affected areas, the period it covers, and a button that opens the official National Weather Service page.

The section always tells you which of three situations you are in, so a problem is never mistaken for good news:

- **Alerts are listed** — those are what is in effect now.
- **"No active alerts."** — the check succeeded and there is nothing in effect.
- **"Could not check for alerts."** — the check itself failed. This is *not* the same as no alerts, and the section says so. Press Enter on the line below it to try again.

Alerts are shown for today only. Moving to another day with **Prev Day** or **Next Day** hides them, because a warning in force now says nothing about another day's forecast.

Places outside the United States have no Alerts section at all, since the National Weather Service covers only US locations. For alerts elsewhere, see **Browse Weather Alerts**, which also covers Canada.

## Configure Display and Units

Open **Configure** (a button on the main window or Full Weather view, or **Configure Display & Units...** on the Settings menu) to control what WeatherFast shows and in which units. The dialog has tabs.

### Choosing fields

Three tabs — **Current**, **Hourly**, and **Daily** — each list the fields available in that section. Check a field to include it, uncheck it to hide it. Available fields include:

- **Current**: Today's Outlook, condition, temperature, feels-like, humidity, dew point, wind speed and direction, wind gusts, pressure, visibility, UV index, precipitation, cloud cover, snowfall, snow depth, rain, showers.
- **Hourly**: condition, temperature, feels-like, humidity, dew point, precipitation chance, precipitation amount, wind speed and direction, wind gusts, cloud cover, snowfall, rain, showers.
- **Daily**: condition, high and low temperature, feels-like high and low, sunrise, sunset, daylight and sunshine duration, UV maximum, precipitation total, precipitation chance, precipitation hours, maximum wind, dominant wind direction, snowfall, rain, and showers totals.

### Units

The **Units** tab sets the measurement units used throughout the app:

| Measure | Choices |
|---------|---------|
| Temperature | Fahrenheit (°F) or Celsius (°C) |
| Wind speed | Miles per hour, kilometers per hour, or meters per second |
| Precipitation | Inches or millimeters |
| Distance | Miles or kilometers |
| Pressure | Inches of mercury (inHg), hectopascals (hPa), or millimeters of mercury (mmHg) |

Use **OK** to apply and close, **Apply** to preview changes without closing, or **Cancel** to discard them. Your choices are saved and persist between sessions.

## Per-City Weather Features

The **Weather** menu holds specialized reports that apply to the city currently selected (or the city shown in Full Weather). Select a city first; if none is selected, the app prompts you to choose one.

### Weather Alerts

Shows active US National Weather Service alerts for the selected city in a separate window. Alerts are listed with the most serious first; select one and choose **View Details** (or press Enter) to read the full alert. When there are none, the dialog clearly says so, and if the check fails it says the check could not be completed — a failure is never reported as "no alerts."

The same alerts also appear at the top of the city's Full Weather report, which is usually the quicker route — see **Alerts in the report**. This window remains useful when you want the alerts on their own, without the forecast around them.

### Expected Precipitation

A short-range precipitation timeline for the next hour, in 15-minute steps, showing when and how intensely precipitation is expected. This is a text timeline (no map), drawn from Open-Meteo's 15-minute nowcast.

### Weather Around Me

Compares weather in the area around your selected city. It has two tabs:

- **Around Me** — current conditions in the eight compass directions plus the center, at a radius you choose (options range from roughly 50 to 350 miles). The first load reverse-geocodes place names and can take several seconds.
- **Directional Explorer** — lists cities along a chosen bearing. Pick a **Direction**, a **Mode** (Arc or Corridor), and a **Width** (Narrow, Standard, Medium, or Wide), then **Explore** to see cities in that direction with their current weather. Your radius, mode, and width choices are remembered.

### Historical Weather

Looks up past weather (Open-Meteo's archive covers 1940 through yesterday). Three tabs:

- **Single Day** — conditions for one chosen date.
- **Multi-Year** — the same calendar day across a number of past years (you set how many years back, up to 85), useful for comparing a date over time.
- **Daily Browse** — a run of consecutive days from a chosen start date (up to 31 days).

### My Data

A custom report you build from a large catalog of Open-Meteo parameters. Choose **Choose Parameters...** to pick fields, organized into category tabs including Temperature, Humidity and Moisture, Wind, Precipitation, Pressure, Clouds and Visibility, Solar and UV, Soil, Atmosphere, Marine and Ocean, Air Quality, and Pollen. Each parameter has a tooltip explaining what it is. The selected values are shown grouped by category, drawn from Open-Meteo's forecast, marine, and air-quality services. **Refresh** re-fetches them. Your selection is saved. Note that marine values only appear for coastal points.

### Marine Forecast

Current sea conditions — wave height, direction, and period; wind-wave and swell height; ocean current velocity and direction; and sea-surface temperature. Marine data exists only for coastal and ocean points; for an inland place the dialog says no marine data is available rather than showing an error.

### Astronomy (Moon)

Today's moon phase, illumination percentage, and moon age, plus the dates of the next new moon and next full moon.

## Browse Weather Alerts

**Browse Weather Alerts...** (on the Cities menu) opens a browser for all active alerts across a whole region, independent of your city list.

1. **Pick a region** — United States (National Weather Service) or Canada (Environment Canada). Each shows a count of currently active alerts.
2. **Read the digest** — active alerts are grouped so each row is one event type with the number of affected areas and, where known, when the soonest one expires.
3. **Filter** — narrow the digest by **Severity** (Extreme, Severe, Moderate, or All — each level shows only that level) and by **Hazard type** (the list shows only hazard families actually present, with counts).
4. **Drill in** — open a group to see its list of affected areas with **View Affected Areas**, then open an area with **View Details** to read the full alert. Enter also advances through these lists.

**Save Current Filters as Default** remembers your chosen severity and hazard filters so they are applied automatically next time you open the browser.

## Copy and Save Reports

When a detailed report is on screen in the Full Weather view, two commands on the **Cities** menu export it as plain text:

- **Copy Weather Report** — copies the displayed report to the clipboard.
- **Save Weather Report...** — saves it to a text file (the suggested filename is based on the city name).

Both require Full Weather to be open for a city; otherwise the app tells you there is nothing to copy or save.

## Updates

WeatherFast can update itself from its GitHub releases. On the **Help** menu:

- **Check for Updates...** checks immediately and reports whether a newer version is available.
- **Automatically Check for Updates** (a toggle, on by default) checks shortly after each launch.

When a newer version exists, the app tells you the new version number and offers to download and install it. If you agree, it downloads the installer, launches it, and closes so the per-user installer can finish. If a direct installer download is not available, it offers to open the releases page in your browser instead. Automatic checking and self-installation apply to the installed build.

## Menus and Keyboard Reference

### Menus

| Menu | Items |
|------|-------|
| Cities | Add City, Browse Cities by State/Country, Add My Location, Browse Weather Alerts, Full Weather, Refresh, Remove City, Move Up, Move Down, Copy Weather Report, Save Weather Report, Exit |
| Weather | Weather Alerts, Expected Precipitation, Weather Around Me, Historical Weather, My Data, Marine Forecast, Astronomy (Moon) — each acts on the selected city |
| Settings | Configure Display & Units, Search: Use Specific Place Names |
| Help | User Guide, Check for Updates, Automatically Check for Updates, About |

The menu bar is reachable with Alt, then the underlined letter of a menu.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| F5 or Ctrl+R | Refresh the selected city |
| Delete | Remove the selected city |
| Alt+U | Move the selected city up |
| Alt+D | Move the selected city down |
| Alt+F | Open Full Weather for the selected city |
| Alt+N | Move focus to the add-city field |
| Alt+C | Open Configure Display & Units |
| Enter (in the city list) | Open Full Weather for the selected city |
| Enter (in a results or alert list) | Add the selected result, or open the next level of detail |
| Escape | Return from Full Weather to the city list |
| F1 | Open this user guide in your browser |

## Data and Privacy

WeatherFast needs no account, sign-in, or API key. It stores its data locally under `%APPDATA%\WeatherFast` — your city list, your display and unit preferences, browse favorites, and a small cache. Nothing is uploaded about you.

The app contacts these services only to fetch the data you ask for:

- **Open-Meteo** — forecasts, hourly and daily data, the precipitation nowcast, historical archive, marine data, and air-quality and pollen data.
- **US National Weather Service** and **Environment Canada** — active weather alerts.
- **OpenStreetMap / Nominatim** — place search and reverse geocoding.
- **ipapi.co** — only when you use Add My Location and precise device location is unavailable, to estimate your city from your IP address.
- **GitHub** — only when checking for or downloading an app update.
