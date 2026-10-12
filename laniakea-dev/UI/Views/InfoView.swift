import SwiftUI

struct InfoView: View {
    private struct Credit: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let url: String
    }

    private let credits = [
        Credit(title: "Planet orbits and facts", detail: "NASA JPL Horizons System",
               url: "https://ssd.jpl.nasa.gov/horizons/"),
        Credit(title: "Naked-eye stars", detail: "Yale Bright Star Catalogue (Hoffleit & Warren), via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=V/50"),
        Credit(title: "Laniakea's boundary", detail: "Cosmicflows basins of attraction, Dupuy & Courtois 2023 (A&A 678, A176)",
               url: "https://projets.ip2i.in2p3.fr/cosmicflows/"),
        Credit(title: "Galaxy groups and distances", detail: "Cosmicflows-4, Tully et al. 2023 (ApJ 944, 94), via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=J/ApJ/944/94"),
        Credit(title: "Galaxy names, types and sizes", detail: "SIMBAD astronomical database, CDS Strasbourg",
               url: "https://simbad.cds.unistra.fr"),
        Credit(title: "Planets of other stars", detail: "NASA Exoplanet Archive, Caltech/IPAC",
               url: "https://exoplanetarchive.ipac.caltech.edu"),
        Credit(title: "Star distances", detail: "Hipparcos, the new reduction (van Leeuwen 2007), via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=I/311"),
        Credit(title: "Star sizes", detail: "JMMC Stellar Diameters Catalogue v2 (Chelli et al. 2016), via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=II/346"),
        Credit(title: "Star temperatures", detail: "PASTEL catalogue (Soubiran et al. 2016), via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=B/pastel"),
        Credit(title: "Star names", detail: "IAU Catalog of Star Names, Working Group on Star Names",
               url: "https://www.iau.org/public/themes/naming_stars/"),
        Credit(title: "Photos of the Sun and planets", detail: "NASA Image and Video Library (public domain); each photo shows its own credit",
               url: "https://images.nasa.gov"),
        Credit(title: "Sky photos of galaxies", detail: "Digitized Sky Survey (DSS2), cut out by the CDS hips2fits service",
               url: "https://alasky.cds.unistra.fr/hips-image-services/hips2fits"),
        Credit(title: "Galaxy colors", detail: "Third Reference Catalogue of Bright Galaxies (RC3), de Vaucouleurs et al. 1991, via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=VII/155"),
        Credit(title: "Constellation boundaries", detail: "IAU boundaries (Delporte 1930) as arranged by Roman 1987, via CDS",
               url: "https://cdsarc.cds.unistra.fr/viz-bin/cat/VI/42"),
        Credit(title: "Black holes in X-ray binaries", detail: "BlackCAT, Corral-Santana et al. 2016 (A&A 587, A61), via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=J/A+A/587/A61"),
        Credit(title: "Galaxy black-hole masses", detail: "van den Bosch 2016 (ApJ 831, 134), via CDS VizieR",
               url: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=J/ApJ/831/134"),
        Credit(title: "Gaia black holes", detail: "Data from the European Space Agency mission Gaia, processed by the Gaia DPAC",
               url: "https://www.cosmos.esa.int/gaia"),
        Credit(title: "Sagittarius A* and M87*", detail: "GRAVITY Collaboration 2022 (A&A 657, L12); Event Horizon Telescope Collaboration 2019 and 2022",
               url: "https://eventhorizontelescope.org"),
        Credit(title: "Astronomy Picture of the Day", detail: "NASA Science",
               url: "https://science.nasa.gov/apod/"),
        Credit(title: "Space news", detail: "Spaceflight News API, with stories from NASA and ESA",
               url: "https://www.spaceflightnewsapi.net"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(credits) { credit in
                        if let url = URL(string: credit.url) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(credit.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(credit.detail)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } header: {
                    Text("Data and imagery")
                } footer: {
                    Text("Article write-ups are generated by AI from the original NASA and ESA posts and may contain mistakes.")
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
