# Laniakea

A space explorer for iPhone and iPad. Read the latest NASA and ESA news as stories, see the Astronomy Picture of the Day, and travel the universe from our home supercluster down to the planets of other stars, all from live scientific data.

Laniakea ("immeasurable heaven" in Hawaiian) is the supercluster of galaxies the Milky Way lives in.

## Features

| Tab | What it does |
|---|---|
| **Discover** | Recent NASA and ESA news as full-screen stories. Tap to move between them, hold to pause, and open an AI-written version of any story. |
| **Atlas** | An interactive map of the universe, from Laniakea down to individual planets (see below). |
| **Home** | NASA's Astronomy Picture of the Day, with a write-up. |
| **Settings** | Not built yet. |
| **Info** | Credits for every data source. |

### Atlas

Atlas goes from the outside in:

- **Laniakea → galaxy groups → galaxies**, using Cosmicflows-4 distances and Laniakea's published boundary.
- **Laniakea → Local Group → Milky Way → stars with planets → their planets**, or our own **Solar System**.

Every object sits at its real position, linked to its neighbours like an Obsidian graph. Pinch to zoom, tap a dot to select it, and tap again (or **Open**) to go inside. The breadcrumb at the top right shows where you are, and the **Laniakea** button jumps back to the outermost view.

- **Fact sheets** for everything: Laniakea, groups, galaxies, the Milky Way, stars, the Sun and planets. Tap **ⓘ** in the top row or on a selected dot. Estimated values are marked ≈ and minimum values ≥.
- **Filters** at each level by kind (clusters, galaxy types, star classes, planet sizes) and by **constellation**, using the official IAU boundaries.
- **One color scale from top to bottom.** Galaxies and groups show the measured color of their starlight (B−V), and stars are colored by temperature, on the same scale. Rocky planets are brown, and gas and ice planets blue.
- **The Solar System** plays forward in time from today's real planet positions, in a flat map or a tilted 3D view.

## Data

Nothing is bundled with the app. Everything comes from public scientific services through one data layer (`CosmicCatalog`) and is cached on the device, so the app still works offline. None of these need an API key.

| Data | Source |
|---|---|
| Laniakea's boundary | Cosmicflows basins of attraction, Dupuy & Courtois 2023 (A&A 678, A176) |
| Galaxy groups and distances | Cosmicflows-4, Tully et al. 2023 (ApJ 944, 94), via CDS VizieR |
| Galaxy names and types | SIMBAD, CDS Strasbourg |
| Galaxy colors | Third Reference Catalogue of Bright Galaxies (RC3), via CDS VizieR |
| Stars with planets, and their planets | NASA Exoplanet Archive |
| Constellation boundaries | IAU boundaries (Roman 1987), via CDS |
| The Sun and Solar System planets | NASA JPL Horizons |
| Naked-eye stars | Yale Bright Star Catalogue, via CDS VizieR (for the coming sky view) |
| News | Spaceflight News API (NASA and ESA articles only) |
| Picture of the Day | NASA APOD feed |

The first time you open Laniakea in Atlas, the app downloads about 17 MB for its boundary map. After that it loads from the cache.

### Accuracy

The astronomy is meant to match the scientific literature, and the code cites its sources:

- **Coordinates:** the conversions between coordinate systems and the constellation lookup were checked against astropy, and planet constellations against JPL Horizons.
- **Galaxy group positions:** VizieR's copy of the Cosmicflows-4 group table has wrong sky positions for some groups. Groups are placed using their member galaxies instead.
- **Rocky or gas:** planets are classified by the best measurement available. That's whether they're no bigger than pure rock of their mass (Zeng et al. 2016), else their radius (Rogers 2015), else their mass (Chen & Kipping 2017).
- **Planets beyond the Milky Way:** none have been confirmed, so galaxies show none.

## Getting started

**Requirements:** Xcode 27 or later; iOS / iPadOS 18.5 or later.

1. Clone the repo and open `laniakea-dev.xcodeproj`.
2. Choose the **laniakea-dev** scheme and an iPhone or iPad (a simulator or a real device).
3. Build and run. The app needs no keys or configuration.

To install on your own device, set your development team under **Signing & Capabilities**.

## Project structure

```
laniakea-dev/
├── Core/
│   ├── Entities/        Models: Planet, Star, galaxy groups, galaxies, exoplanets…
│   ├── Repos/           Protocols the data layer implements
│   └── Astronomy/       Pure astronomy code: orbits, coordinates, constellations,
│                        star colors, rocky-or-gas rule
├── Infrastructure/
│   └── Catalog/         CosmicCatalog (the one data layer), TAP client, Horizons,
│                        Laniakea boundary loader, disk cache
├── Interactors/         Use cases
└── UI/
    ├── ViewModel/       ObservableObject view models
    └── Views/           SwiftUI views (Atlas/ holds the maps and fact sheets)
generator/               Writes the AI articles (Python, optional)
```

The Xcode project uses synchronized folders, so new files under `laniakea-dev/` are picked up without editing the project file.

## AI articles (optional)

The AI-written articles in Discover and Home are generated once per article and served as static JSON from GitHub Pages, so every user shares them and nothing is generated on the device. The app only reads them. You don't need to run the generator to build or use the app.

The generator (`generator/generate.py`) uses the Claude API and only uses NASA and ESA articles, for copyright reasons. To run it:

1. Put `ANTHROPIC_API_KEY=…` in a `.env` file at the repo root. It's gitignored; never commit it.
2. Install the dependencies from `generator/requirements.txt`.
3. Run the generator with `OUTPUT_DIR=site`. It skips articles that already exist and stops after `MAX_PER_RUN` (default 10).
4. Publish the contents of `site/` to the `gh-pages` branch.

The **Generate AI articles** GitHub Actions workflow does the same when you start it by hand. It needs the `ANTHROPIC_API_KEY` repository secret.

## Roadmap

- **Sky view:** the night sky from where you stand, with the naked-eye stars and constellations.
- Settings, and the saved-objects and saved-articles sections on Home.

## Credits

Built by [@harshsepi0l](https://github.com/harshsepi0l), with [Claude Code](https://claude.com/claude-code).

The data comes from the teams behind Cosmicflows, CDS (VizieR and SIMBAD), the NASA Exoplanet Archive, NASA JPL, NASA, ESA and the Spaceflight News API. The **Info** tab credits each one in full.
