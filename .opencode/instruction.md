# Spell Compare / AA Tracker

## Overview
Vanilla HTML/CSS/JS static site — no build tools, no frameworks, no package.json. Runs locally with `python3 -m http.server 8080`. Deployed on GitHub Pages.

## Pages
- `index.html` — "Missing Spells" spell comparison tool (EverQuest)
- `froggy.html` — "Froggy Locations" reference
- `aa-tracker.html` — "AA Tracker" (Alternate Ability rank tracking with multi-character support)

## Conventions
- **Styling**: Single `style.css` with CSS custom properties (`--bg`, `--text`, etc.) for theming. Supports light/dark mode via `@media (prefers-color-scheme: dark)`.
- **JS**: Inline `<script>` per page or `script.js` for index.html. DOM rendering via `innerHTML` string concatenation. No framework.
- **Icons**: Tabler Icons (`@tabler/icons-webfont`) loaded from CDN.
- **Data**: localStorage for persistence. AA tracker uses key `aa-tracker-data` with `{ current, chars }` structure.
- **Navigation**: Static `<a>` links in a shared `.nav-bar`. Active page gets `.active` class.
- **HTML pattern**: Cards (`.card`) with panel sections (`.panel-section`), labels (`.panel-label`), and section dividers (`.section-divider`).
- **Naming**: kebab-case CSS classes, camelCase JS functions.

## Key Commands
- Serve locally: `python3 -m http.server 8080`
- No build, test, or lint commands exist.

## GitHub Pages
- Deployed from the `main` branch (or `/docs` folder). Files are served as-is.
- Cache-bust tip: hard refresh or add `?v=N` to CSS/JS URLs.
