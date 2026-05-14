import SwiftUI

// MARK: - Pack Weight Summary
struct WeightSummary {
    var total: Double = 0
    var base: Double = 0
    var worn: Double = 0
    var consumable: Double = 0
}

// MARK: - Pack View
// Root view for a single pack. Uses List as the top-level scroll container
// so it is never embedded inside another ScrollView.
struct PackView: View {
    @EnvironmentObject var state: AppState
    let tripId: String
    let packIndex: Int

    @State private var showAddGearSheet = false
    @State private var renamingCube: Cube? = nil

    // Always read live from state so changes are immediately reflected
    var trip: Trip? { state.trips.first { $0.id == tripId } }
    var pack: Pack? {
        guard let trip, packIndex < trip.packs.count else { return nil }
        return trip.packs[packIndex]
    }

    var weightSummary: WeightSummary {
        guard let pack else { return WeightSummary() }
        var s = WeightSummary()
        for item in pack.items {
            guard let gear = state.gearById(item.gearId, forTripId: tripId), let w = gear.weight else { continue }
            let t = w * Double(item.qty)
            s.total += t
            switch item.type {
            case .base:        s.base += t
            case .worn:        s.worn += t
            case .consumable:  s.consumable += t
            }
        }
        for ref in pack.bundleRefs {
            guard let bundle = state.bundleById(ref.bundleId, forTripId: tripId) else { continue }
            for bi in bundle.items {
                guard let gear = state.gearById(bi.gearId, forTripId: tripId), let w = gear.weight else { continue }
                let t = w * Double(bi.qty)
                s.total += t
                let itype = ref.itemTypes.first(where: { $0.gearId == bi.gearId })?.type ?? .base
                switch itype {
                case .base:        s.base += t
                case .worn:        s.worn += t
                case .consumable:  s.consumable += t
                }
            }
        }
        return s
    }

    var body: some View {
        Group {
            if let pack {
                List {
                    // ── Weight bar ──────────────────────────────────────────
                    Section {
                        WeightSummaryBar(summary: weightSummary)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    // ── Ungrouped items ─────────────────────────────────────
                    let ungrouped = pack.items.filter { $0.cubeId == nil || $0.cubeId!.isEmpty }
                    if !ungrouped.isEmpty || !pack.cubes.isEmpty {
                        Section(header: Text("Ungrouped").ditherSectionHeader()) {
                            ForEach(ungrouped, id: \.gearId) { item in
                                PackItemRow(item: item,
                                    gear:         state.gearById(item.gearId, forTripId: tripId),
                                    onCheck:      { v in mutateItem(gearId: item.gearId, cubeId: nil, checked: v) },
                                    onTypeChange: { t in mutateItem(gearId: item.gearId, cubeId: nil, type:    t) },
                                    onRemove:     {     removeItem(gearId: item.gearId, cubeId: nil) })
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeItem(gearId: item.gearId, cubeId: nil)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    if !pack.cubes.isEmpty {
                                        Menu {
                                            ForEach(pack.cubes) { cube in
                                                Button(cube.name) { moveItem(gearId: item.gearId, toCubeId: cube.id) }
                                            }
                                        } label: {
                                            Label("Move to Cube", systemImage: "archivebox")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Cube sections ───────────────────────────────────────
                    ForEach(pack.cubes) { cube in
                        let cubeItems = pack.items.filter { $0.cubeId == cube.id }
                        let cubeWeight = cubeItems.compactMap { item -> Double? in
                            guard let g = state.gearById(item.gearId, forTripId: tripId), let w = g.weight else { return nil }
                            return w * Double(item.qty)
                        }.reduce(0, +)

                        Section(header:
                            HStack {
                                Text(cube.name).ditherSectionHeader()
                                if cubeWeight > 0 {
                                    Text(formatWeight(cubeWeight))
                                        .font(.caption2).foregroundColor(.ditherGreen.opacity(0.8))
                                        .textCase(nil)
                                }
                                Spacer()
                                if !(trip?.archived ?? false) {
                                    Button(action: { renamingCube = cube }) {
                                        Image(systemName: "pencil").font(.caption2)
                                    }
                                    .tint(.secondary)
                                    .padding(.trailing, 6)
                                    Button(role: .destructive, action: { removeCube(cube) }) {
                                        Image(systemName: "trash").font(.caption2)
                                    }.tint(.red)
                                }
                            }
                        ) {
                            ForEach(cubeItems, id: \.gearId) { item in
                                PackItemRow(item: item,
                                    gear:         state.gearById(item.gearId, forTripId: tripId),
                                    onCheck:      { v in mutateItem(gearId: item.gearId, cubeId: cube.id, checked: v) },
                                    onTypeChange: { t in mutateItem(gearId: item.gearId, cubeId: cube.id, type:    t) },
                                    onRemove:     {     removeItem(gearId: item.gearId, cubeId: cube.id) })
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeItem(gearId: item.gearId, cubeId: cube.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button { moveItem(gearId: item.gearId, toCubeId: nil) } label: {
                                        Label("Move to Ungrouped", systemImage: "tray")
                                    }
                                    let otherCubes = pack.cubes.filter { $0.id != cube.id }
                                    if !otherCubes.isEmpty {
                                        Menu {
                                            ForEach(otherCubes) { other in
                                                Button(other.name) { moveItem(gearId: item.gearId, toCubeId: other.id) }
                                            }
                                        } label: {
                                            Label("Move to Cube", systemImage: "archivebox")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Bundle refs ─────────────────────────────────────────
                    if !pack.bundleRefs.isEmpty {
                        Section(header: Text("Bundles").ditherSectionHeader()) {
                            ForEach(Array(pack.bundleRefs.enumerated()), id: \.element.bundleId) { idx, ref in
                                BundleRefRow(
                                    ref: ref,
                                    refIndex: idx,
                                    tripId: tripId,
                                    packIndex: packIndex
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeRef(at: idx)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    // ── Add cube (hidden when archived) ─────────────────────
                    if !(trip?.archived ?? false) {
                        Section {
                            Button(action: { addCube() }) {
                                Label("Add Cube", systemImage: "cube.box")
                                    .foregroundColor(.ditherGreen)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .sheet(item: $renamingCube) { cube in
                    RenameCubeSheet(currentName: cube.name) { newName in
                        renameCube(cube, name: newName)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !(trip?.archived ?? false) {
                        Button(action: { showAddGearSheet = true }) {
                            Label("Add Gear", systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.ditherGreen)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }
                    }
                }
                .sheet(isPresented: $showAddGearSheet) {
                    // Always pass a fresh pack from state
                    AddGearToPack(tripId: tripId, packIndex: packIndex)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Mutations (always operate on a fresh copy from state)

    private func withPack(_ body: (inout Pack) -> Void) {
        guard var trip = state.trips.first(where: { $0.id == tripId }),
              packIndex < trip.packs.count else { return }
        body(&trip.packs[packIndex])
        Task { try? await state.updatePack(tripId: tripId, packIndex: packIndex, pack: trip.packs[packIndex]) }
    }

    private func mutateItem(gearId: String, cubeId: String?, checked: Bool? = nil, type: ItemType? = nil) {
        withPack { pack in
            guard let idx = pack.items.firstIndex(where: {
                $0.gearId == gearId && $0.cubeId == cubeId
            }) else { return }
            if let c = checked { pack.items[idx].checked = c }
            if let t = type    { pack.items[idx].type    = t }
        }
    }

    private func removeItem(gearId: String, cubeId: String?) {
        withPack { pack in
            pack.items.removeAll { $0.gearId == gearId && $0.cubeId == cubeId }
        }
    }

    private func addCube() {
        withPack { pack in
            let num = pack.cubes.count + 1
            pack.cubes.append(Cube(localName: "Cube \(num)"))
        }
    }

    private func renameCube(_ cube: Cube, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withPack { pack in
            guard let idx = pack.cubes.firstIndex(where: { $0.id == cube.id }) else { return }
            pack.cubes[idx].name = trimmed
        }
    }

    private func removeCube(_ cube: Cube) {
        withPack { pack in
            pack.cubes.removeAll { $0.id == cube.id }
            for i in pack.items.indices where pack.items[i].cubeId == cube.id {
                pack.items[i].cubeId = nil
            }
        }
    }

    private func removeRef(at index: Int) {
        withPack { pack in
            guard index < pack.bundleRefs.count else { return }
            pack.bundleRefs.remove(at: index)
        }
    }

    // MARK: - Move item between cubes
    private func moveItem(gearId: String, toCubeId: String?) {
        withPack { pack in
            guard let idx = pack.items.firstIndex(where: { $0.gearId == gearId }) else { return }
            guard pack.items[idx].cubeId != toCubeId else { return }
            pack.items[idx].cubeId = toCubeId
        }
    }
}


// MARK: - Rename Cube Sheet
struct RenameCubeSheet: View {
    let currentName: String
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Cube name", text: $name)
                    .onSubmit { commit() }
            }
            .navigationTitle("Rename Cube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(180)])
        .onAppear { name = currentName }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
        dismiss()
    }
}

// MARK: - Weight Summary Bar
struct WeightSummaryBar: View {
    let summary: WeightSummary
    var body: some View {
        HStack(spacing: 16) {
            chip("Total",  summary.total,        .ditherGreen)
            Divider().frame(height: 24)
            chip("Base",   summary.base,         .blue)
            chip("Worn",   summary.worn,         .orange)
            chip("Cons.",  summary.consumable,   .red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
    private func chip(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(formatWeight(value)).font(.subheadline).fontWeight(.semibold).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Pack Item Row
struct PackItemRow: View {
    let item: PackItem
    let gear: GearItem?   // pre-resolved (may come from frozen snapshot for archived trips)
    let onCheck:      (Bool)     -> Void
    let onTypeChange: (ItemType) -> Void
    let onRemove:     ()         -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { onCheck(!item.checked) }) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.checked ? .ditherGreen : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(gear?.name ?? "Unknown item")
                    .font(.body)
                    .strikethrough(item.checked)
                    .foregroundColor(item.checked ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let w = gear?.weight { WeightBadge(grams: w * Double(item.qty)) }
                    Text("×\(item.qty)").font(.caption).foregroundColor(.secondary)
                    if let b = gear?.brand, !b.isEmpty {
                        Text(b).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Menu {
                ForEach(ItemType.allCases, id: \.self) { t in
                    Button(action: { onTypeChange(t) }) {
                        Label(t.label, systemImage: t.icon)
                    }
                }
            } label: {
                Image(systemName: item.type.icon)
                    .foregroundColor(typeColor(item.type))
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }

    private func typeColor(_ type: ItemType) -> Color {
        switch type {
        case .base:        return .blue
        case .worn:        return .orange
        case .consumable:  return .red
        }
    }
}

// MARK: - Bundle Ref Row (card style, matches BundleRowView in GearLockerView)
struct BundleRefRow: View {
    @EnvironmentObject var state: AppState
    let ref: BundleRef
    let refIndex: Int
    let tripId: String
    let packIndex: Int

    var bundle: GearBundle? { state.bundleById(ref.bundleId, forTripId: tripId) }

    var totalWeight: Double {
        bundle?.items.compactMap { bi in
            state.gearById(bi.gearId, forTripId: tripId).flatMap { $0.weight }.map { $0 * Double(bi.qty) }
        }.reduce(0, +) ?? 0
    }

    var checkedCount: Int { ref.checkedItems.count }
    var totalCount: Int   { bundle?.items.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ─────────────────────────────────────
            Button(action: { toggleExpanded() }) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bundle?.name ?? "Bundle")
                            .font(.body).fontWeight(.medium).foregroundColor(.primary)
                        HStack(spacing: 6) {
                            Text("\(totalCount) item\(totalCount == 1 ? "" : "s")")
                                .font(.caption).foregroundColor(.secondary)
                            if totalCount > 0 {
                                Text("·").font(.caption).foregroundColor(.secondary)
                                Text("\(checkedCount)/\(totalCount) checked")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if totalWeight > 0 { WeightBadge(grams: totalWeight) }
                    Image(systemName: ref.expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // ── Expanded item list ──────────────────────────────
            if ref.expanded, let bundle {
                Divider().padding(.top, 8)
                ForEach(bundle.items, id: \.gearId) { bi in
                    let checked  = ref.checkedItems.contains(bi.gearId)
                    let itemType = ref.itemTypes.first { $0.gearId == bi.gearId }?.type ?? .base
                    let gear     = state.gearById(bi.gearId, forTripId: tripId)

                    HStack(spacing: 10) {
                        Button(action: { toggleCheck(bi.gearId) }) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(checked ? .ditherGreen : .secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(gear?.name ?? "Unknown")
                                .font(.subheadline)
                                .strikethrough(checked)
                                .foregroundColor(checked ? .secondary : .primary)
                            HStack(spacing: 6) {
                                if let w = gear?.weight { WeightBadge(grams: w * Double(bi.qty)) }
                                Text("×\(bi.qty)").font(.caption).foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Menu {
                            ForEach(ItemType.allCases, id: \.self) { t in
                                Button(action: { setType(bi.gearId, t) }) {
                                    Label(t.label, systemImage: t.icon)
                                }
                            }
                        } label: {
                            Image(systemName: itemType.icon)
                                .foregroundColor(typeColor(itemType))
                                .font(.subheadline)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func withPack(_ body: (inout Pack) -> Void) {
        guard var trip = state.trips.first(where: { $0.id == tripId }),
              packIndex < trip.packs.count else { return }
        body(&trip.packs[packIndex])
        let pack = trip.packs[packIndex]
        Task { try? await state.updatePack(tripId: tripId, packIndex: packIndex, pack: pack) }
    }

    private func toggleExpanded() {
        withPack { $0.bundleRefs[refIndex].expanded.toggle() }
    }
    private func toggleCheck(_ gearId: String) {
        withPack { pack in
            if pack.bundleRefs[refIndex].checkedItems.contains(gearId) {
                pack.bundleRefs[refIndex].checkedItems.removeAll { $0 == gearId }
            } else {
                pack.bundleRefs[refIndex].checkedItems.append(gearId)
            }
        }
    }
    private func setType(_ gearId: String, _ type: ItemType) {
        withPack { pack in
            let entry = BundleItemType(gearId: gearId, type: type)
            if let i = pack.bundleRefs[refIndex].itemTypes.firstIndex(where: { $0.gearId == gearId }) {
                pack.bundleRefs[refIndex].itemTypes[i] = entry
            } else {
                pack.bundleRefs[refIndex].itemTypes.append(entry)
            }
        }
    }
    private func typeColor(_ t: ItemType) -> Color {
        switch t { case .base: return .blue; case .worn: return .orange; case .consumable: return .red }
    }
}

// MARK: - Add Gear to Pack Sheet
// Reads the live pack from state on every action so it never works on a stale copy.
struct AddGearToPack: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let tripId: String
    let packIndex: Int

    @State private var gearSearch = ""

    private var pack: Pack? {
        guard let trip = state.trips.first(where: { $0.id == tripId }),
              packIndex < trip.packs.count else { return nil }
        return trip.packs[packIndex]
    }

    private var gearInPack:    Set<String> { Set(pack?.items.map { $0.gearId } ?? []) }
    private var bundlesInPack: Set<String> { Set(pack?.bundleRefs.map { $0.bundleId } ?? []) }

    private var availableGear: [GearItem] {
        state.gear.filter {
            !gearInPack.contains($0.id) && (
                gearSearch.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(gearSearch) ||
                $0.brand.localizedCaseInsensitiveContains(gearSearch) ||
                $0.category.localizedCaseInsensitiveContains(gearSearch)
            )
        }
    }

    private var availableBundles: [GearBundle] {
        state.bundles.filter { !bundlesInPack.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !availableBundles.isEmpty {
                    Section(header: Text("Add Bundles").ditherSectionHeader()) {
                        ForEach(availableBundles) { bundle in
                            let totalWeight = bundle.items.compactMap { bi -> Double? in
                                guard let g = state.gearById(bi.gearId), let w = g.weight else { return nil }
                                return w * Double(bi.qty)
                            }.reduce(0, +)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bundle.name).font(.body)
                                    HStack(spacing: 6) {
                                        Text("\(bundle.items.count) items").font(.caption).foregroundColor(.secondary)
                                        if totalWeight > 0 { WeightBadge(grams: totalWeight) }
                                    }
                                }
                                Spacer()
                                Button(action: { addBundle(bundle) }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.ditherGreen).font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section(header: Text("Gear Locker").ditherSectionHeader()) {
                    if state.gear.isEmpty {
                        Text("No gear in your locker yet")
                            .foregroundColor(.secondary).font(.subheadline)
                    } else if availableGear.isEmpty && !gearSearch.isEmpty {
                        Text("No matching gear").foregroundColor(.secondary).font(.subheadline)
                    } else if availableGear.isEmpty {
                        Text("All gear already added to this pack")
                            .foregroundColor(.secondary).font(.subheadline)
                    } else {
                        ForEach(availableGear) { gear in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gear.name).font(.body)
                                    HStack(spacing: 6) {
                                        if !gear.brand.isEmpty { Text(gear.brand).font(.caption).foregroundColor(.secondary) }
                                        if !gear.category.isEmpty { Text(gear.category).font(.caption).foregroundColor(.secondary) }
                                    }
                                }
                                Spacer()
                                if let w = gear.weight { WeightBadge(grams: w * Double(gear.qty)) }
                                Button(action: { addGear(gear) }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.ditherGreen).font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $gearSearch, prompt: "Search gear…")
            .navigationTitle("Add to Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(.ditherGreen)
                }
            }
        }
    }

    private func addGear(_ gear: GearItem) {
        guard var trip = state.trips.first(where: { $0.id == tripId }),
              packIndex < trip.packs.count else { return }
        // Guard against duplicate
        guard !trip.packs[packIndex].items.contains(where: { $0.gearId == gear.id }) else { return }
        trip.packs[packIndex].items.append(
            PackItem(gearId: gear.id, qty: 1, cubeId: nil, checked: false, type: .base)
        )
        let pack = trip.packs[packIndex]
        Task { try? await state.updatePack(tripId: tripId, packIndex: packIndex, pack: pack) }
    }

    private func addBundle(_ bundle: GearBundle) {
        guard var trip = state.trips.first(where: { $0.id == tripId }),
              packIndex < trip.packs.count else { return }
        guard !trip.packs[packIndex].bundleRefs.contains(where: { $0.bundleId == bundle.id }) else { return }
        trip.packs[packIndex].bundleRefs.append(
            BundleRef(bundleId: bundle.id, expanded: true, checkedItems: [], itemTypes: [], cubeId: nil)
        )
        let pack = trip.packs[packIndex]
        Task { try? await state.updatePack(tripId: tripId, packIndex: packIndex, pack: pack) }
    }
}
