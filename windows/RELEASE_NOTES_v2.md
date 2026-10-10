# FastWeather v2.0 Windows App Release Notes

**Release Date:** January 17, 2026

## Major Features

### 🗺️ Browse Cities by State/Country
- **NEW:** Browse and add cities from pre-loaded lists organized by U.S. state or international country
- Navigate through states → cities hierarchically with intuitive back navigation
- Access via "Browse Cities by State/Country" button or **Alt+W** keyboard shortcut
- Pre-geocoded city coordinates for 50 cities per U.S. state and major international cities
- Dramatically faster than manual geocoding (instant vs. 20+ second waits)
- Alphabetically sorted city lists for easy navigation

### ⚡ Performance Improvements
- **Thread Pool & Caching System:** Weather data now cached for 10 minutes with intelligent thread pooling
- **Concurrent Request Limiting:** Maximum 5 simultaneous API requests (down from 50+) prevents system overload
- **Smart Cache Management:** Reduces API calls by 90%+ for repeated queries
- **Browse Performance:** Browsing 50 cities now takes 3-5 seconds instead of causing app hangs (10+ seconds)
- Manual refresh clears cache to force fresh data when needed

### ⌨️ Keyboard Shortcuts & Help
- **NEW F1/? Help Screen:** Comprehensive keyboard shortcuts reference accessible via F1 or ?
- **Enhanced Navigation:** Full keyboard shortcuts for all major operations
- **Browse Navigation Improvements:**
  - **Alt+W** - Open browse cities dialog
  - **Alt+A** - Add selected city from browse view
  - Escape - Navigate back through browse hierarchy
  - Focus restoration - Returns to previously selected state/country when going back

### 🎯 Accessibility Enhancements
- Hierarchical navigation with proper focus restoration
- Clear visual and auditory feedback for all actions

## Complete Keyboard Shortcuts

### Navigation
- **F1 or ?** - Show keyboard shortcuts help
- **Escape** - Go back / Navigate hierarchy
- **Tab / Shift+Tab** - Move between controls
- **Up/Down Arrow** - Navigate lists
- **Home/End** - Jump to start/end of list
- **First letter** - Jump to items starting with that letter (repeated presses cycle)
- **Enter** - Activate/Select item

### City Management
- **Alt+N** - Focus new city input field
- **Alt+W** - Browse cities by state/country
- **Delete** - Remove selected city
- **Alt+U** - Move city up in list
- **Alt+D** - Move city down in list

### Weather
- **F5 or Ctrl+R** - Refresh weather for selected city
- **Alt+F** - Show full weather details
- **Alt+C** - Configure weather display

### Browse Navigation
- **Enter** - Navigate into selection
- **Escape** - Go back one level
- **Alt+A** - Add selected city to your list

## Technical Improvements

### Architecture
- Implemented `ThreadPoolExecutor` with configurable worker limit (5 concurrent)
- Weather cache with timestamp tracking and automatic expiration
- Cache-aware fetch method with smart invalidation
- Improved error handling and user feedback

### Data Files
- **us-cities-cached.json** - Pre-geocoded coordinates for 50 cities × 50 U.S. states
- **international-cities-cached.json** - Pre-geocoded coordinates for major international cities
- Eliminates slow Nominatim API calls for browsing

### Code Quality
- 700+ lines of new code with improved organization
- Consistent async patterns using thread pool
- Better separation of concerns (browse, weather, UI)

## Bug Fixes
- Fixed: Cities added via browse now appear immediately in main list (no restart required)
- Fixed: Focus properly restored when navigating back through browse hierarchy
- Fixed: Screen reader compatibility in help view (removed empty items)
- Fixed: Cache clearing on manual refresh to ensure fresh data

## Breaking Changes
None - Fully backward compatible with v1.1

## Known Issues
None reported

## Upgrade Notes
- Existing city lists are preserved
- No configuration changes required
- Cache files bundled with application automatically

## Performance Comparison

| Operation | v1.1 | v2.0 |
|-----------|------|------|
| Browse 50 cities | 10-15s (hang) | 3-5s (smooth) |
| Re-browse same state | 10-15s | <1s (cached) |
| Concurrent API requests | Unlimited (50+) | 5 (controlled) |
| Duplicate API calls | Every time | Cached 10 min |
| Add city from browse | Requires restart | Instant update |

---

**Full Changelog:** [v1.1...v2.0](https://github.com/TheIdeaPlace/WeatherFast/compare/v1.1...v2.0)

**Download:** See [Releases](https://github.com/TheIdeaPlace/WeatherFast/releases)
