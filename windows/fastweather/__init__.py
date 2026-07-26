"""WeatherFast Windows desktop application package.

Accessible GUI weather app built on wxPython and the Open-Meteo API.
Refactored from the original single-file ``fastweather.py`` monolith into a
service / model / cache / ui layered package (see the parity roadmap).

Note: the Python package/module is still imported as ``fastweather`` (import
name only, never shown to users); the product name is WeatherFast.
"""

__version__ = "3.0.1"
