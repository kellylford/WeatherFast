# FastWeather Webapp - Country Display Issue

**Status**: UNRESOLVED  
**Date**: January 18, 2026  
**User Reports**: Web browser shows only 52 countries instead of 101 in Browse Cities feature

## Current State

### What Works:
- ✓ Windows desktop app shows all 101 countries correctly
- ✓ JSON files contain correct data (101 countries, 323KB, verified with Python)
- ✓ Both `CityData/international-cities-cached.json` and `webapp/international-cities-cached.json` are identical and correct
- ✓ City Search/Add feature may be working (not confirmed)

### What's Broken:
- ✗ Browser displays only 52 countries in Browse Cities → International dropdown
- ✗ Issue persists across multiple browsers
- ✗ Issue persists in private/incognito mode
- ✗ Issue persists after clearing cache using clear-cache.html tool
- ✗ Issue persists after uploading to web server

## File Verification

### international-cities-cached.json
```bash
# Both files identical:
webapp/international-cities-cached.json: 323K, Jan 18 20:48, 101 countries
CityData/international-cities-cached.json: 323K, Jan 18 20:48, 101 countries

# Python verification:
import json
data = json.load(open('webapp/international-cities-cached.json', encoding='utf-8'))
len(data)  # Returns: 101
'Greenland' in data  # Returns: True
'Uzbekistan' in data  # Returns: True
```

## Root Cause Analysis

The webapp originally had **two separate city data systems**:

### System 1: JavaScript Source Files (OLD - DELETED)
- **Files**: `us-cities-data.js`, `international-cities-data.js`
- **Format**: JavaScript objects with variables `US_CITIES_BY_STATE` and `INTERNATIONAL_CITIES_BY_COUNTRY`
- **Status**: These files were REMOVED during cleanup but HTML/JS still referenced them
- **Countries**: Only contained ~47-52 original countries

### System 2: JSON Cache Files (NEW - CURRENT)
- **Files**: `us-cities-cached.json`, `international-cities-cached.json`
- **Format**: JSON with pre-geocoded coordinates
- **Status**: Contains all 101 countries
- **Used by**: City search/add, Windows app, iOS app, macOS app

## Fixes Attempted

### Fix #1: Service Worker Cache Update (January 18, 2026)
**File**: `webapp/service-worker.js`

**Problem Identified**: Service worker using cache-first strategy, serving old JSON from cache

**Change Made**:
```javascript
// Changed cache version
const CACHE_NAME = 'fastweather-v2-92countries'; // Later: v3-101countries

// Added network-first for JSON files
if (url.pathname.endsWith('.json') && 
    (url.pathname.includes('cities-cached') || url.pathname.includes('manifest'))) {
    event.respondWith(
        fetch(request)
            .then(response => { /* update cache and return fresh data */ })
            .catch(() => caches.match(request)) // offline fallback
    );
}
```

**Result**: Did not fix issue

---

### Fix #2: Remove JavaScript File References
**File**: `webapp/index.html`

**Problem Identified**: HTML tried to load deleted .js files

**Before**:
```html
<script src="us-cities-data.js"></script>
<script src="international-cities-data.js"></script>
<script src="app.js"></script>
```

**After**:
```html
<script src="app.js"></script>
```

**Result**: Did not fix issue

---

### Fix #3: Update Browse Cities Code to Use JSON Data
**File**: `webapp/app.js`

**Problem Identified**: Browse Cities code checked for undefined variables from deleted .js files

**Before**:
```javascript
// Browse Cities selection handler
if (typeof INTERNATIONAL_CITIES_BY_COUNTRY === 'undefined') {
    console.error('INTERNATIONAL_CITIES_BY_COUNTRY not loaded');
    return;
}
const countryCities = INTERNATIONAL_CITIES_BY_COUNTRY[countryName];
displayLocationCities(countryName, countryCities, countryCities.length, 'international');
```

**After**:
```javascript
// Use cached JSON data instead
if (!cachedInternationalCoordinates) {
    console.error('Cached international city coordinates not loaded');
    return;
}
const countryCities = cachedInternationalCoordinates[countryName];
const cityNames = countryCities.map(city => city.name);
displayLocationCities(countryName, cityNames, cityNames.length, 'international');
```

**Result**: Did not fix issue

---

### Fix #4: Replace Hardcoded Country Dropdowns
**File**: `webapp/index.html`

**Problem Identified**: TWO hardcoded dropdowns in HTML only listed ~52 countries

**Dropdown 1 - Add City Filter** (`country-select`):
```html
<!-- BEFORE: 52 hardcoded countries with ISO codes -->
<select id="country-select" name="country">
    <option value="">Any Country</option>
    <option value="ar">Argentina</option>
    <option value="au">Australia</option>
    <!-- ... 50 more hardcoded options ... -->
</select>

<!-- AFTER: To be populated dynamically -->
<select id="country-select" name="country">
    <option value="">Any Country</option>
    <!-- Populated dynamically from international-cities-cached.json -->
</select>
```

**Dropdown 2 - Browse Cities** (`country-select-browse`):
```html
<!-- BEFORE: 52 hardcoded countries -->
<select id="country-select-browse" name="country">
    <option value="">-- Select a Country --</option>
    <option value="Argentina">Argentina</option>
    <!-- ... 50 more hardcoded options ... -->
</select>

<!-- AFTER: To be populated dynamically -->
<select id="country-select-browse" name="country">
    <option value="">-- Select a Country --</option>
    <!-- Populated dynamically from international-cities-cached.json -->
</select>
```

**Result**: Did not fix issue (dropdowns likely not being populated by JavaScript)

---

### Fix #5: Add Dynamic Dropdown Population
**File**: `webapp/app.js`

**Function Added**: `populateCountryDropdown()`

```javascript
// Populate country dropdown from cached data
function populateCountryDropdown() {
    if (!cachedInternationalCoordinates) {
        console.error('Cannot populate country dropdown: cachedInternationalCoordinates is not loaded');
        return;
    }
    
    // Get sorted list of countries
    const countries = Object.keys(cachedInternationalCoordinates).sort();
    
    // Country name to ISO code mapping (101 countries)
    const countryCodeMap = {
        'Algeria': 'dz', 'Angola': 'ao', 'Argentina': 'ar', /* ... etc ... */
    };
    
    // 1. Populate Browse Cities dropdown (uses country names)
    const browseSelect = document.getElementById('country-select-browse');
    if (browseSelect) {
        while (browseSelect.options.length > 1) {
            browseSelect.remove(1);
        }
        countries.forEach(country => {
            const option = document.createElement('option');
            option.value = country;
            option.textContent = country;
            browseSelect.appendChild(option);
        });
    }
    
    // 2. Populate Add City filter dropdown (uses ISO codes)
    const filterSelect = document.getElementById('country-select');
    if (filterSelect) {
        while (filterSelect.options.length > 1) {
            filterSelect.remove(1);
        }
        countries.forEach(country => {
            const option = document.createElement('option');
            const code = countryCodeMap[country] || country.toLowerCase().substring(0, 2);
            option.value = code;
            option.textContent = country;
            filterSelect.appendChild(option);
        });
    }
}
```

**Called From**: `loadCachedInternationalCoordinates()` after successful JSON fetch

**Result**: Unknown - likely not executing or executing but dropdowns reverting

---

## Debugging Steps to Try Next

### 1. Check Browser Console
Open browser DevTools (F12) and check Console tab for:
- ✓ `✓ Successfully loaded cached international city coordinates for 101 countries`
- ✓ `✓ Populated Browse Cities dropdown with 101 countries`
- ✓ `✓ Populated Add City filter dropdown with 101 countries`
- ✗ Any errors related to JSON loading
- ✗ Any errors about undefined variables

### 2. Verify JSON Actually Loads
In browser console, run:
```javascript
fetch('international-cities-cached.json')
  .then(r => r.json())
  .then(data => console.log('Countries:', Object.keys(data).length));
```
Expected: `Countries: 101`

### 3. Check If Dropdowns Are Populated
In browser console, run:
```javascript
const browse = document.getElementById('country-select-browse');
console.log('Browse dropdown options:', browse.options.length);

const filter = document.getElementById('country-select');
console.log('Filter dropdown options:', filter.options.length);
```
Expected: Both should show 102 (1 default + 101 countries)

### 4. Check Timing Issue
Possible issue: Dropdowns being populated AFTER some other code resets them

In browser console, after page loads:
```javascript
// Manually trigger population
populateCountryDropdown();
// Then check dropdowns again
```

### 5. Network Tab Check
In DevTools → Network tab:
- Look for `international-cities-cached.json` request
- Check Status: should be 200 (not 304 cached, not 404)
- Check Size: should be ~323KB
- Click on it → Preview tab → Verify it has 101 countries

### 6. Check Service Worker State
In DevTools → Application tab (Chrome) or Storage tab (Firefox):
- Service Workers section
- Check which version is active
- Click "Unregister" to completely remove it
- Reload page and retest

### 7. Verify File Upload
On web server, verify:
```bash
# Check file exists and size
ls -lh international-cities-cached.json
# Should be ~323KB, recent date

# Check first few lines of JSON
head -20 international-cities-cached.json
# Should show country names like Algeria, Angola, Argentina...

# Count actual countries in file
grep -o '"[A-Z][a-zA-Z ]*":' international-cities-cached.json | wc -l
# Should be 101
```

## Possible Issues Not Yet Investigated

### Issue 1: JavaScript Load Order
- `app.js` might execute before DOM is ready
- `populateCountryDropdown()` might run before dropdowns exist in DOM
- **Check**: Is `DOMContentLoaded` event listener wrapping the initialization?

### Issue 2: Hard Refresh Not Actually Clearing Cache
- Ctrl+Shift+R might not be clearing service worker cache
- **Try**: Complete unregister of service worker via DevTools

### Issue 3: Server-Side Caching
- Web server might be caching and serving old HTML/JS files
- **Check**: Verify file timestamps on server match local files
- **Try**: Add cache-busting query params: `app.js?v=20260118`

### Issue 4: Multiple Instances of Files
- There might be duplicate HTML/JS files in different directories
- **Check**: Search server for all `index.html` files
- **Verify**: Accessing the correct URL path

### Issue 5: Code Execution Error
- `populateCountryDropdown()` might be throwing an error silently
- **Check**: Wrap function in try/catch with console logging
- **Add**: `console.log()` statements at each step in the function

### Issue 6: Race Condition
- Dropdowns populated correctly but something else resets them afterwards
- **Check**: Add mutation observer to watch dropdown changes
- **Try**: Set breakpoint in browser DevTools on dropdown.appendChild()

## Files Modified (Ready to Upload)

### 1. webapp/index.html
- Removed: `<script src="us-cities-data.js"></script>`
- Removed: `<script src="international-cities-data.js"></script>`
- Replaced: Both country dropdowns now have minimal HTML (to be populated by JS)

### 2. webapp/app.js
- Updated: `loadCachedInternationalCoordinates()` to call `populateCountryDropdown()`
- Updated: Browse Cities selection handler to use `cachedInternationalCoordinates`
- Added: Complete `populateCountryDropdown()` function with 101-country ISO code mapping

### 3. webapp/service-worker.js
- Updated: Cache version to `v3-101countries`
- Added: Network-first strategy for JSON files

### 4. webapp/clear-cache.html (New)
- Tool to clear all caches, unregister service workers, clear localStorage
- Access at: `http://yourserver/clear-cache.html`

## Working Test Case (Windows App)

The Windows desktop app correctly displays all 101 countries. It uses the same JSON file but has a simpler architecture:

**File**: `fastweather.py` (lines 495-570)
- Loads `international-cities-cached.json` directly
- Uses Python's `json.load()`
- Displays in wxPython dialog
- No caching, no service workers, no async loading

**This proves**:
- JSON file is correct
- Data structure is valid
- Problem is specific to webapp JavaScript/caching layer

## Next Steps for Debugging

1. **Open webapp in browser with DevTools open**
2. **Go to Console tab** - look for errors or success messages
3. **Run manual tests** (see "Debugging Steps to Try Next" above)
4. **Check Network tab** - verify JSON file loads
5. **Try in completely clean browser** - new browser profile or different computer
6. **Compare with Windows app behavior** - what does it do differently?

## Questions for User

1. When you say "52 countries", where exactly do you see this number?
   - In the Browse Cities dropdown?
   - In the Add City filter dropdown?
   - In browser console logs?
   - Counting options manually?

2. What does browser console show?
   - Any errors?
   - Success messages about loading 101 countries?
   - Messages about populating dropdowns?

3. What happens if you:
   - Completely unregister service worker via DevTools?
   - Open in brand new browser (not just private mode)?
   - Check Network tab - does JSON file actually download?

4. Can you verify on web server:
   - File `international-cities-cached.json` exists and is 323KB?
   - File `index.html` has the updated code (no script tags for -data.js)?
   - File `app.js` has the updated code (populateCountryDropdown function)?

## Contact Info for Handoff

User: kellylford  
Repo: github.com/TheIdeaPlace/WeatherFast  
Branch: main  
Date: January 18, 2026  

All code changes are ready in local files, tested in Windows app (works), but webapp browser display still broken despite multiple fix attempts and cache clearing.
