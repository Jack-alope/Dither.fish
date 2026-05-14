import SwiftUI

struct GearLockerView: View {
    @EnvironmentObject var state: AppState
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var showAddGear = false
    @State private var showAddBundle = false
    @State private var editingGear: GearItem?
    @State private var editingBundle: GearBundle?
    @State private var expandedBundles: Set<String> = []

    var categories: [String] {
        var cats = ["All"]
        let found = Set(state.gear.map { $0.category }).sorted()
        cats.append(contentsOf: found)
        return cats
    }

    var filteredGear: [GearItem] {
        state.gear.filter { item in
            let matchCategory = selectedCategory == "All" || item.category == selectedCategory
            let matchSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.brand.localizedCaseInsensitiveContains(searchText)
            return matchCategory && matchSearch
        }
    }

    var groupedGear: [(String, [GearItem])] {
        let grouped = Dictionary(grouping: filteredGear, by: { $0.category })
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.isLoading && state.gear.isEmpty {
                    ProgressView("Loading gear...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let error = state.error {
                            ErrorBanner(message: error) { state.error = nil }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        // Gear sections
                        if filteredGear.isEmpty && !state.gear.isEmpty {
                            Section {
                                EmptyStateView(
                                    icon: "magnifyingglass",
                                    title: "No results",
                                    message: "Try a different search or category"
                                )
                                .listRowBackground(Color.clear)
                            }
                        } else if state.gear.isEmpty {
                            Section {
                                EmptyStateView(
                                    icon: "briefcase",
                                    title: "Your gear locker is empty",
                                    message: "Tap + Add Item to get started"
                                )
                                .listRowBackground(Color.clear)
                            }
                        } else {
                            ForEach(groupedGear, id: \.0) { (category, items) in
                                Section(header: Text(category).ditherSectionHeader()) {
                                    ForEach(items) { item in
                                        GearRowView(item: item)
                                            .contentShape(Rectangle())
                                            .onTapGesture { editingGear = item }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    Task { try? await state.deleteGear(id: item.id) }
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                            }
                        }

                        // Bundles section
                        Section(header: Text("Bundles").ditherSectionHeader()) {
                            if state.bundles.isEmpty {
                                Text("No bundles yet")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(state.bundles) { bundle in
                                    BundleRowView(
                                        bundle: bundle,
                                        isExpanded: expandedBundles.contains(bundle.id),
                                        onTap: {
                                            if expandedBundles.contains(bundle.id) {
                                                expandedBundles.remove(bundle.id)
                                            } else {
                                                expandedBundles.insert(bundle.id)
                                            }
                                        },
                                        onEdit: { editingBundle = bundle }
                                    )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            Task { try? await state.deleteBundle(id: bundle.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            editingBundle = bundle
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.ditherGreen)
                                    }
                                }
                            }

                            Button(action: { showAddBundle = true }) {
                                Label("New Bundle", systemImage: "plus.circle.fill")
                                    .foregroundColor(.ditherGreen)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Search gear...")
                    .refreshable { await state.fetchAll() }
                }
            }
            .navigationTitle("Gear Locker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddGear = true }) {
                        Label("Add Item", systemImage: "plus")
                    }
                    .tint(.ditherGreen)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if categories.count > 1 {
                        Menu {
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(categories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                        } label: {
                            Label(selectedCategory == "All" ? "Category" : selectedCategory, systemImage: "line.3.horizontal.decrease.circle")
                                .tint(.ditherGreen)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddGear) {
                GearFormView(gear: nil)
            }
            .sheet(item: $editingGear) { item in
                GearFormView(gear: item)
            }
            .sheet(isPresented: $showAddBundle) {
                BundleFormView(bundle: nil)
            }
            .sheet(item: $editingBundle) { bundle in
                BundleFormView(bundle: bundle)
            }
        }
    }
}

// MARK: - Gear Row
struct GearRowView: View {
    let item: GearItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(item.brand)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let w = item.weight {
                    WeightBadge(grams: w)
                }
                if item.qty > 1 {
                    Text("x\(item.qty)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Bundle Row
struct BundleRowView: View {
    @EnvironmentObject var state: AppState
    let bundle: GearBundle
    let isExpanded: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    var totalWeight: Double {
        bundle.items.compactMap { item in
            state.gearById(item.gearId).flatMap { $0.weight }.map { $0 * Double(item.qty) }
        }.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bundle.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Text("\(bundle.items.count) item\(bundle.items.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if totalWeight > 0 {
                        WeightBadge(grams: totalWeight)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.top, 8)
                ForEach(bundle.items, id: \.gearId) { bundleItem in
                    if let gear = state.gearById(bundleItem.gearId) {
                        HStack {
                            Text(gear.name)
                                .font(.subheadline)
                            Spacer()
                            Text("x\(bundleItem.qty)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let w = gear.weight {
                                WeightBadge(grams: w * Double(bundleItem.qty))
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                Button(action: onEdit) {
                    Label("Edit Bundle", systemImage: "pencil")
                        .font(.caption)
                        .foregroundColor(.ditherGreen)
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GearLockerView()
        .environmentObject(AppState.shared)
}
