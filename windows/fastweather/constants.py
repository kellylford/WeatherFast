"""Shared constants: API endpoints, unit-conversion factors, default cities."""

# Unit conversion factors
KMH_TO_MPH = 0.621371
MM_TO_INCHES = 0.0393701
HPA_TO_INHG = 0.02953
HPA_TO_MMHG = 0.750062
KMH_TO_MS = 1 / 3.6
METERS_TO_MILES = 1 / 1609.34
METERS_TO_KM = 1 / 1000.0

# API endpoints
OPEN_METEO_API_URL = "https://api.open-meteo.com/v1/forecast"
OPEN_METEO_MARINE_URL = "https://marine-api.open-meteo.com/v1/marine"
OPEN_METEO_AIR_QUALITY_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"
OPEN_METEO_ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"

# HTTP
USER_AGENT = "WeatherFast GUI/1.0"
DEFAULT_TIMEOUT = 10

# Published, formatted user guide (built from docs/user-guide.md by the
# publish-user-guide workflow and served from GitHub Pages).
USER_GUIDE_URL = "https://theideaplace.github.io/WeatherFast/"

# Default seed cities: display name -> [lat, lon]
DEFAULT_CITIES = {
    "Madison, Wisconsin, United States": [43.074761, -89.3837613],
    "San Diego, California, United States": [32.7174202, -117.162772],
    "Portland, Oregon, United States": [45.5202471, -122.674194],
    "London, England, United Kingdom": [51.5074456, -0.1277653],
    "Miami, Florida, United States": [25.7741728, -80.19362],
    "Redmond, Washington, United States": [47.6694141, -122.1238767],
    "Mexico City, Ciudad de México, México": [19.3207722, -99.1514678],
    "Seaside, Oregon, United States": [45.993246, -123.920213],
    "Fond du Lac, Wisconsin, United States": [43.7731217, -88.4417538],
    "Mission Viejo, California, United States": [33.612472, -117.6425884],
    "Maui, Hawaii, United States of America": [20.8029568, -156.3106833],
}
