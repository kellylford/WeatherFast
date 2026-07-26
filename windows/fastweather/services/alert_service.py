"""Per-city US weather alerts via the National Weather Service (api.weather.gov).

NWS is US-only. Results are cached 5 minutes and expired alerts are filtered
out. A fetch failure raises (so the UI can show a distinct "couldn't check"
state) and must never be presented as "no alerts".
"""

from ..cache.memory_cache import TTLCache
from . import http, nws

NWS_ALERTS_URL = "https://api.weather.gov/alerts/active"

_cache = TTLCache(default_ttl=300)  # 5 minutes


def fetch_alerts(lat, lon, use_cache=True):
    """Return a severity-sorted list of active WeatherAlert for a US coordinate.

    Raises on network/parse failure so callers can distinguish "couldn't check"
    from "no active alerts".
    """
    key = f"{lat:.3f},{lon:.3f}"
    if use_cache:
        cached = _cache.get(key)
        if cached is not None:
            return cached

    data = http.get_json(NWS_ALERTS_URL, params={"point": f"{lat},{lon}"})
    alerts = [nws.parse_feature(f) for f in data.get("features", [])]
    alerts = [a for a in alerts if not a.is_expired()]
    alerts.sort(key=lambda a: a.sort_key)
    _cache.set(key, alerts)
    return alerts
