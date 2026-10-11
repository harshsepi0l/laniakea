# Laniakea

A space explorer for iPhone and iPad. Read the latest NASA and ESA news as stories, see the Astronomy Picture of the Day, and travel the universe from our home supercluster down to the planets of other stars, all from live scientific data.

**Status:** in development, coming to the App Store.

Laniakea ("immeasurable heaven" in Hawaiian) is the supercluster of galaxies the Milky Way lives in.

## Features

| Tab | What it does |
|---|---|
| **Discover** | Recent NASA and ESA news as full-screen stories. Tap to move between them, hold to pause, and open an AI-written version of any story. |
| **Atlas** | An interactive map of the universe, from Laniakea down to individual planets (see below). |
| **Home** | NASA's Astronomy Picture of the Day, with an AI-written explanation. |
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

The app's astronomy data comes live from public scientific services and is saved on the device, so places you've visited still work offline.

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

The first time you open Laniakea in Atlas, the app downloads about 17 MB for its boundary map. After that it opens straight away.

### Accuracy

The astronomy is meant to match the scientific literature:

- **Coordinates:** the conversions between coordinate systems and the constellation lookup were checked against astropy, and planet constellations against JPL Horizons.
- **Galaxy group positions:** VizieR's copy of the Cosmicflows-4 group table has wrong sky positions for some groups. Groups are placed using their member galaxies instead.
- **Rocky or gas:** planets are classified by the best measurement available. That's whether they're no bigger than pure rock of their mass (Zeng et al. 2016), else their radius (Rogers 2015), else their mass (Chen & Kipping 2017).
- **Planets beyond the Milky Way:** none have been confirmed, so galaxies show none.

## Roadmap

- **Sky view:** the night sky from where you stand, with the naked-eye stars and constellations.
- Settings, and saved objects and articles on Home.

## Credits

Built by [@harshsepi0l](https://github.com/harshsepi0l), with [Claude Code](https://claude.com/claude-code).

The data comes from the teams behind Cosmicflows, CDS (VizieR and SIMBAD), the NASA Exoplanet Archive, NASA JPL, NASA, ESA and the Spaceflight News API. The **Info** tab credits each one in full.

## License

© 2026 harshsepi0l. All rights reserved. This repository is not open source: the code, design and content may not be copied, modified or redistributed without permission.
