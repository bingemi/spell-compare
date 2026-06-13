# Everquest Utilities

A set of browser-based tools for tracking EverQuest character progress. All data is stored in your browser's localStorage — no server, no sign-up.

## Pages

- **Missing Spells** (`index.html`) — Compare your character's spellbook against the master spell list to find missing spells. Supports all 16 classes, level filtering, and expansion-based comparisons.
- **Froggy Locations** (`froggy.html`) — Reference list of Froggy hiding locations.
- **AA Tracker** (`aa-tracker.html`) — Track Alternate Ability ranks across multiple characters. Add AAs with tier (Greater/Exalted/Ascendant), ranks, notes, and cap status. Sort and filter the table. Get a summary of books needed per class.

## Run locally

```bash
python3 -m http.server 8080
```

Then open `http://localhost:8080` in your browser.

## Tech

- Vanilla HTML / CSS / JavaScript
- [Tabler Icons](https://tabler.io/icons) via CDN
- CSS custom properties with light/dark mode via `prefers-color-scheme`
- localStorage for data persistence
- Multi-character support with JSON export/import
