import SwiftUI

struct CatalogView: View {
    @EnvironmentObject var state: AppState
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var showSuggestSheet = false
    @State private var editingCatalogItem: CatalogItem?
    @State private var addedItemName: String? = nil
    @State private var variantPickerItem: CatalogItem? = nil

    var categories: [String] {
        var cats = ["All"]
        let found = Set(state.catalog.map { $0.category }).sorted()
        cats.append(contentsOf: found)
        return cats
    }

    var filteredCatalog: [CatalogItem] {
        state.catalog.filter { item in
            let matchCat = selectedCategory == "All" || item.category == selectedCategory
            let matchSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.brand.localizedCaseInsensitiveContains(searchText)
            return matchCat && matchSearch
        }
    }

    var groupedCatalog: [(String, [CatalogItem])] {
        let grouped = Dictionary(grouping: filteredCatalog, by: { $0.category })
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Admin pending items section
                if state.isAdmin && !state.pendingCatalog.isEmpty {
                    Section(header:
                        HStack {
                            Text("Pending Approval").ditherSectionHeader()
                            Spacer()
                            Text("\(state.pendingCatalog.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                    ) {
                        ForEach(state.pendingCatalog) { item in
                            PendingCatalogRow(item: item, onEdit: { editingCatalogItem = item })
                        }
                    }
                }

                // Catalog items grouped by category
                if filteredCatalog.isEmpty && !state.catalog.isEmpty {
                    Section {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No results",
                            message: "Try a different search or category"
                        )
                        .listRowBackground(Color.clear)
                    }
                } else if state.catalog.isEmpty {
                    Section {
                        EmptyStateView(
                            icon: "books.vertical",
                            title: "Catalog is empty",
                            message: "Be the first to suggest gear!"
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groupedCatalog, id: \.0) { (category, items) in
                        Section(header: Text(category).ditherSectionHeader()) {
                            ForEach(items) { item in
                                CatalogItemRow(item: item)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            if item.variants.isEmpty {
                                                Task { await addToLocker(item) }
                                            } else {
                                                variantPickerItem = item
                                            }
                                        } label: {
                                            Label("Add to Locker", systemImage: "plus.circle.fill")
                                        }
                                        .tint(.ditherGreen)
                                    }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search catalog...")
            .overlay(alignment: .bottom) {
                if let name = addedItemName {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("\(name) added to gear locker")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.ditherGreen.opacity(0.95))
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: addedItemName)
            .sheet(item: $variantPickerItem) { item in
                CatalogVariantPickerSheet(item: item) { variant in
                    Task { await addToLocker(item, variant: variant) }
                }
            }
            .refreshable {
                await state.fetchCatalog()
                if state.isAdmin { await state.loadPending() }
            }
            .navigationTitle("Catalog")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSuggestSheet = true }) {
                        Label("Suggest Item", systemImage: "plus")
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
            .sheet(isPresented: $showSuggestSheet) {
                SuggestCatalogItemView()
            }
            .sheet(item: $editingCatalogItem) { item in
                EditCatalogItemView(item: item)
            }
            .task {
                await state.fetchCatalog()
                if state.isAdmin { await state.loadPending() }
            }
        }
    }

    private func addToLocker(_ item: CatalogItem, variant: CatalogVariant? = nil) async {
        let name   = variant != nil ? "\(item.name) (\(variant!.name))" : item.name
        let weight = variant?.weight ?? item.weight
        try? await state.addGear(
            name: name,
            brand: item.brand,
            category: item.category,
            weight: weight,
            qty: 1,
            notes: item.notes
        )
        addedItemName = name
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        addedItemName = nil
    }
}

// MARK: - Catalog Item Row
struct CatalogItemRow: View {
    let item: CatalogItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if !item.variants.isEmpty {
                        Text("\(item.variants.count) variant\(item.variants.count == 1 ? "" : "s")")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.ditherGreen.opacity(0.12))
                            .foregroundColor(.ditherGreen)
                            .clipShape(Capsule())
                    }
                }
                if !item.brand.isEmpty {
                    Text(item.brand)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if item.variants.isEmpty, let w = item.weight {
                WeightBadge(grams: w)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Variant Picker Sheet
struct CatalogVariantPickerSheet: View {
    let item: CatalogItem
    let onSelect: (CatalogVariant) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String? = nil

    var body: some View {
        NavigationStack {
            List(item.variants) { variant in
                Button {
                    selectedId = variant.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variant.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            if let w = variant.weight {
                                Text(formatWeight(w))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if selectedId == variant.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.ditherGreen)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Locker") {
                        if let id = selectedId,
                           let variant = item.variants.first(where: { $0.id == id }) {
                            onSelect(variant)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(.ditherGreen)
                    .disabled(selectedId == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { selectedId = item.variants.first?.id }
    }

    private func formatWeight(_ g: Double) -> String {
        g >= 1000 ? String(format: "%.2f kg", g / 1000) : "\(Int(g)) g"
    }
}

// MARK: - Pending Catalog Row (Admin)
struct PendingCatalogRow: View {
    @EnvironmentObject var state: AppState
    let item: CatalogItem
    let onEdit: () -> Void

    @State private var isApproving = false
    @State private var isRejecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text("\(item.brand) · \(item.category)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let submitter = item.submittedBy {
                        Text("Suggested by \(submitter)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let w = item.weight {
                    WeightBadge(grams: w)
                }
            }

            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: { Task { await reject() } }) {
                    if isRejecting {
                        ProgressView().tint(.red)
                    } else {
                        Label("Reject", systemImage: "xmark.circle")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRejecting || isApproving)

                Button(action: { Task { await approve() } }) {
                    if isApproving {
                        ProgressView().tint(.ditherGreen)
                    } else {
                        Label("Approve", systemImage: "checkmark.circle")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.ditherGreenLight)
                            .foregroundColor(.ditherGreen)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isApproving || isRejecting)
            }
        }
        .padding(.vertical, 4)
    }

    private func approve() async {
        isApproving = true
        defer { isApproving = false }
        try? await state.approveItem(id: item.id)
    }

    private func reject() async {
        isRejecting = true
        defer { isRejecting = false }
        try? await state.rejectItem(id: item.id)
    }
}

// MARK: - Suggest Catalog Item
struct SuggestCatalogItemView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var category = ""
    @State private var weightText = ""
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var submitted = false

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if submitted {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.ditherGreen)
                            Text("Suggestion Submitted!")
                                .font(.headline)
                            Text("Your suggestion will be reviewed by our team.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if let error = errorMessage {
                        Section {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                                Text(error).font(.caption).foregroundColor(.red)
                            }
                        }
                    }

                    Section(header: Text("Item Info").ditherSectionHeader()) {
                        TextField("Name *", text: $name)
                        TextField("Brand", text: $brand)
                        TextField("Category", text: $category)
                    }

                    Section(header: Text("Specs").ditherSectionHeader()) {
                        HStack {
                            TextField("Weight", text: $weightText)
                                .keyboardType(.decimalPad)
                            Text("grams").foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("Notes").ditherSectionHeader()) {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }
                }
            }
            .navigationTitle("Suggest Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !submitted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: { Task { await submit() } }) {
                            if isLoading {
                                ProgressView().tint(.ditherGreen)
                            } else {
                                Text("Submit")
                                    .fontWeight(.semibold)
                                    .foregroundColor(canSave ? .ditherGreen : .secondary)
                            }
                        }
                        .disabled(!canSave || isLoading)
                    }
                }
            }
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let w = Double(weightText.trimmingCharacters(in: .whitespaces))
        do {
            try await state.suggestItem(
                name: name.trimmingCharacters(in: .whitespaces),
                brand: brand,
                category: category,
                weight: w,
                notes: notes
            )
            submitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Edit Catalog Item (Admin)
struct EditCatalogItemView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: CatalogItem

    @State private var name = ""
    @State private var brand = ""
    @State private var category = ""
    @State private var weightText = ""
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(error).font(.caption).foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("Item Info").ditherSectionHeader()) {
                    TextField("Name *", text: $name)
                    TextField("Brand", text: $brand)
                    TextField("Category", text: $category)
                }

                Section(header: Text("Specs").ditherSectionHeader()) {
                    HStack {
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text("grams").foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Notes").ditherSectionHeader()) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Catalog Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { Task { await save() } }) {
                        if isLoading {
                            ProgressView().tint(.ditherGreen)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundColor(canSave ? .ditherGreen : .secondary)
                        }
                    }
                    .disabled(!canSave || isLoading)
                }
            }
            .onAppear { prefill() }
        }
    }

    private func prefill() {
        name = item.name
        brand = item.brand
        category = item.category
        if let w = item.weight { weightText = String(Int(w)) }
        notes = item.notes
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let w = Double(weightText.trimmingCharacters(in: .whitespaces))
        do {
            try await state.editCatalogItem(
                id: item.id,
                name: name.trimmingCharacters(in: .whitespaces),
                brand: brand,
                category: category,
                weight: w,
                notes: notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    CatalogView()
        .environmentObject(AppState.shared)
}
