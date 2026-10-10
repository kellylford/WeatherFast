# FastWeather Web Application

A fully accessible HTML/JavaScript version of FastWeather that runs entirely in your web browser. Built with WCAG 2.2 AA compliance to ensure accessibility for all users.

## Features

- **Fully Accessible**: Meets WCAG 2.2 AA standards for accessibility
- **Screen Reader Compatible**: Proper ARIA labels, roles, and live regions
- **Keyboard Navigation**: Complete keyboard support with focus management
- **Responsive Design**: Works on desktop, tablet, and mobile devices
- **No Backend Required**: Runs entirely in the browser using localStorage
- **Fast & Simple**: Current weather and detailed forecasts without clutter
- **No API Key Required**: Uses the free Open-Meteo weather service
- **Privacy First**: All data stored locally in your browser

## WCAG 2.2 AA Compliance

This application implements the following accessibility features:

### Visual Design
- **Contrast Ratios**: All text meets or exceeds 4.5:1 contrast ratio for normal text and 3:1 for large text
- **Color Independence**: Information is not conveyed by color alone
- **Resizable Text**: Text can be resized up to 200% without loss of functionality
- **Visible Focus**: Clear focus indicators on all interactive elements (3px outline)

### Keyboard Accessibility
- **Skip Link**: Skip to main content link at the top of the page
- **Keyboard Navigation**: All functionality accessible via keyboard
- **Focus Management**: Proper focus order and focus trapping in modals
- **Tab Navigation**: Arrow key navigation in tab controls
- **Escape Key**: Close modals with Escape key

### Screen Reader Support
- **Semantic HTML**: Proper use of HTML5 semantic elements (header, main, nav, section, article, footer)
- **ARIA Labels**: Descriptive labels on all interactive elements
- **ARIA Roles**: Proper roles (dialog, tablist, tab, tabpanel, listbox, status, alert)
- **Live Regions**: Status updates announced to screen readers (aria-live)
- **Alternative Text**: All meaningful icons have aria-labels

### Forms & Controls
- **Touch Targets**: Minimum 44x44px touch target size for all interactive elements
- **Form Labels**: All form inputs have associated labels
- **Error Messages**: Clear error messages with role="alert"
- **Input Purpose**: Autocomplete attributes where appropriate

### Responsive & Adaptive
- **Responsive Design**: Adapts to different screen sizes and orientations
- **Dark Mode**: Respects prefers-color-scheme media query
- **Reduced Motion**: Respects prefers-reduced-motion for users sensitive to animation
- **High Contrast**: Enhanced support for high contrast mode

## Usage

### Running Locally

1. Clone the repository and switch to the WebApp branch:
   ```bash
   git clone https://github.com/TheIdeaPlace/WeatherFast.git
   cd FastWeather
   git checkout WebApp
   ```

2. Open `index.html` in your web browser:
   - Double-click the file, or
   - Right-click and choose "Open with" your preferred browser, or
   - Serve with a local web server:
     ```bash
     python -m http.server 8000
     # Then navigate to http://localhost:8000
     ```

### Using the Application

1. **Add Cities**:
   - **Search by Name**: Enter a city name, state, and country (e.g., "San Diego, California")
   - **Use Current Location**: Click "Use My Current Location" to automatically add your current location
     - Your browser will ask for permission the first time
     - Location data never leaves your browser - it's only used to find the nearest city
     - If you've already added your current location, you'll see a message indicating it's already in your list
   - Press Enter or click "Add City"
   - If multiple matches are found, select from the list

2. **View Weather**:
   - Current conditions are displayed for each city
   - Click the 📊 icon for detailed 7-day forecast
   - Click 🔄 to refresh a specific city's weather

3. **Customize Display**:
   - Click "Configure" to choose which weather details to show
   - Select units (Fahrenheit/Celsius, mph/km/h, inches/mm)
   - Changes apply immediately with "Apply" or save with "Save & Close"

4. **Manage Cities**:
   - Use ↑↓ buttons to reorder cities
   - Click 🗑️ to remove a city
   - Your cities are saved in browser localStorage

### Keyboard Shortcuts

- **Tab**: Navigate between interactive elements
- **Enter/Space**: Activate buttons and selections
- **Escape**: Close modals and dialogs
- **Arrow Keys**: Navigate tabs in configuration dialog
- **Ctrl+R**: Refresh all cities

## Browser Compatibility

- Chrome/Edge 90+
- Firefox 88+
- Safari 14+
- Opera 76+

All modern browsers with ES6+ support and localStorage.

## Data Storage

All data is stored locally in your browser using:
- **localStorage['fastweather-cities']**: Your saved cities
- **localStorage['fastweather-config']**: Your display preferences

No data is sent to any server except:
- **OpenStreetMap Nominatim**: For geocoding city names (search only)
- **Open-Meteo API**: For fetching weather data

## Technologies Used

- **HTML5**: Semantic markup with ARIA attributes
- **CSS3**: Modern CSS with CSS custom properties (variables)
- **JavaScript (ES6+)**: Vanilla JavaScript, no frameworks
- **LocalStorage API**: For persistent data storage
- **Fetch API**: For API calls
- **Open-Meteo API**: Free weather data service
- **OpenStreetMap Nominatim**: Free geocoding service

## Accessibility Testing

This application has been designed to work with:
- **Screen Readers**: NVDA, JAWS, VoiceOver, TalkBack
- **Keyboard Only**: Full functionality without a mouse
- **Browser Zoom**: Up to 200% zoom level
- **Dark Mode**: Automatic dark theme detection
- **High Contrast Mode**: Enhanced visibility in high contrast

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Attribution

Weather data provided by [Open-Meteo.com](https://open-meteo.com/) (CC BY 4.0)  
Geocoding by [OpenStreetMap Nominatim](https://nominatim.openstreetmap.org/)

## Contributing

Contributions are welcome! Please ensure all changes maintain WCAG 2.2 AA compliance.

## Support

For issues or questions, please open an issue on GitHub.
