import SwiftUI

/// A fact sheet for anything in Atlas: a summary, a grid of facts, and where they come from.
struct FactSheetView: View {
    @StateObject private var model: FactSheetViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(subject: FactSubject, repo: CosmicRepo = CosmicCatalog.shared) {
        _model = StateObject(wrappedValue: FactSheetViewModel(subject: subject, repo: repo))
    }

    var body: some View {
        let sheet = model.sheet
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        if let t = sheet.temperatureK {
                            let color = StarColor.swiftUI(temperature: t, dark: colorScheme == .dark)
                            Circle().fill(color).frame(width: 16, height: 16).shadow(color: color.opacity(0.7), radius: 6)
                        }
                        Text(sheet.title).font(.system(size: 30, weight: .bold))
                        if model.isLoading { ProgressView() }
                    }
                    Text(sheet.summary).font(.system(size: 16)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = model.error {
                    HStack(spacing: 12) {
                        Text(error).font(.system(size: 14)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(.bordered).tint(.orange)
                    }
                }

                if !sheet.facts.isEmpty {
                    FactGrid(facts: sheet.facts)
                }

                ForEach(sheet.lists) { list in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(list.title).font(.system(size: 15, weight: .semibold))
                        ForEach(list.items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                                Text(item).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sheet.notes, id: \.self) { note in
                        Text(note).font(.system(size: 13)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Source: \(sheet.source)").font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .task { await model.load() }
        .factSheetPresentation()
    }
}

/// One labelled value in a fact sheet's grid.
struct FactCell: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(2)
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray5), lineWidth: 1))
    }
}

/// Facts two to a row, each row as tall as its tallest cell so the grid stays even.
struct FactGrid: View {
    let facts: [FactSheet.Fact]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { i in
                GridRow {
                    cell(facts[i])
                    if i + 1 < facts.count {
                        cell(facts[i + 1])
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func cell(_ fact: FactSheet.Fact) -> some View {
        FactCell(label: fact.label, value: fact.value, detail: fact.detail)
    }
}

extension View {
    /// Half height on iPhone with room to pull up; full height on iPad, where a half-height sheet is a
    /// short card that cuts off its facts. Opaque, so the map behind doesn't show through the text.
    func factSheetPresentation() -> some View {
        presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemBackground))
    }
}
