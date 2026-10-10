"""In-app auto-update via GitHub Releases (mirrors QuickMail's update feed).

Checks the repository's latest release, compares its tag to the running
version, and — when newer — downloads the installer asset and launches it. The
app then exits so the per-user installer can replace files without elevation.
Only meaningful for the frozen build; from source it is a no-op check.
"""

import os
import re
import tempfile

from .. import __version__
from . import http

GITHUB_REPO = "TheIdeaPlace/WeatherFast"
RELEASES_URL = f"https://api.github.com/repos/{GITHUB_REPO}/releases?per_page=30"
# This is a multi-platform repo; Windows releases are tagged `windows-v<semver>`
# so the updater never picks up an iOS or web release.
WINDOWS_TAG_PREFIX = "windows-v"


def _version_tuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")) or (0,)


def is_newer(latest, current):
    a, b = _version_tuple(latest), _version_tuple(current)
    n = max(len(a), len(b))
    a += (0,) * (n - len(a))  # zero-pad so 1.1 and 1.1.0 compare equal
    b += (0,) * (n - len(b))
    return a > b


def _windows_version(tag):
    """Return the semver from a `windows-v<semver>` tag, else None."""
    if tag and tag.startswith(WINDOWS_TAG_PREFIX):
        return tag[len(WINDOWS_TAG_PREFIX):]
    return None


def check_for_update(current_version=None):
    """Return {'version', 'url', 'notes'} for the newest Windows release if it
    is newer than the running version, else None.

    Considers only `windows-v*` releases (this repo also ships iOS and web).
    Raises on network/API failure so a manual check can report "couldn't check".
    """
    current = current_version or __version__
    releases = http.get_json(RELEASES_URL) or []
    best, best_ver = None, None
    for r in releases:
        if r.get("draft") or r.get("prerelease"):
            continue
        ver = _windows_version(r.get("tag_name") or "")
        if not ver:
            continue
        if best is None or _version_tuple(ver) > _version_tuple(best_ver):
            best, best_ver = r, ver

    if best is None or not is_newer(best_ver, current):
        return None
    url = None
    for asset in best.get("assets", []):
        if (asset.get("name") or "").lower().endswith("setup.exe"):
            url = asset.get("browser_download_url")
            break
    return {"version": best_ver, "url": url, "notes": best.get("body") or ""}


def download_installer(url, progress=None):
    """Download the installer to a temp file; return its path.

    ``progress`` (optional) is called with (downloaded_bytes, total_bytes).
    """
    resp = http.session().get(url, stream=True, timeout=120)
    resp.raise_for_status()
    total = int(resp.headers.get("Content-Length") or 0)
    name = os.path.basename(url) or "WeatherFast-Setup.exe"
    path = os.path.join(tempfile.gettempdir(), name)
    done = 0
    with open(path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=65536):
            if chunk:
                f.write(chunk)
                done += len(chunk)
                if progress:
                    progress(done, total)
    return path


def launch_installer(path):
    """Launch the downloaded installer (Windows).

    The installer is downloaded over HTTPS from the project's GitHub release
    assets. Note it is not yet code-signed, so Windows SmartScreen may prompt.
    """
    os.startfile(path)  # noqa: S606
