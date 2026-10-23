# Delivery map provider recovery — 0.3.11

The jobsite picker previously requested the standard OpenStreetMap raster tile server. A production screenshot showed HTTP 403 Access blocked tiles. This release replaces that service with OpenFreeMap's documented commercial-use public instance and its Liberty vector style, rendered using MapLibre's official Leaflet adapter.

Existing Leaflet click handling, marker, radius circle, coordinates and geofence persistence remain unchanged. The picker waits for the map style to load before accepting clicks. OpenFreeMap, OpenMapTiles and OpenStreetMap attribution is visible. The MapLibre worker is bundled locally by Vite, and the map engine is lazy-loaded only when coordinate editing is opened. There are no database or existing coordinate changes.

If WebGL or map requests are unavailable, the editor retains direct coordinate entry, pasted Google Maps coordinates and the external Google Maps search link. Save coordinates remains the explicit persistence action.

Validation: 52 production tests passed, including map readiness, click selection, disabled state, attribution and cleanup. TypeScript and production Vite build passed. A local browser preview was unavailable because the browser could not reach the local development server; this was not counted as a map rendering test.

Provider documentation: https://openfreemap.org/quick_start/ and https://openfreemap.org/ (commercial use and required attribution). No proxy, header spoofing or alternate routing of the blocked OpenStreetMap tile service is used.
