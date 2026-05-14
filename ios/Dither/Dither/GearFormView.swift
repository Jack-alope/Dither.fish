import SwiftUI

struct GearFormView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let gear: GearItem?

    @State private var name = ""
    @State private var brand = ""
    @State private var category = ""
    @State private var weightText = ""
    @State private var qty = 1
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCategorySuggestions = false

    var isEditing: Bool { gear != nil }

    var existingCategories: [String] {
        Array(Set(state.gear.map { $0.category })).sorted().filter { !$0.isEmpty }
    }

    var filteredCategories: [String] {
        if category.isEmpty {
            return existingCategories
        }
        return existingCategories.filter { $0.localizedCaseInsensitiveContains(category) }
    }

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

                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Category", text: $category, onEditingChanged: { editing in
                            showCategorySuggestions = editing
                        })

                        if showCategorySuggestions && !filteredCategories.isEmpty {
                            Divider()
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(filteredCategories, id: \.self) { cat in
                                        Button(cat) {
                                            category = cat
                                            showCategorySuggestions = false
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.ditherGreenLight)
                                        .foregroundColor(.ditherGreen)
                                        .clipShape(Capsule())
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }

                Section(header: Text("Weight & Quantity").ditherSectionHeader()) {
                    HStack {
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text("grams")
                            .foregroundColor(.secondary)
                    }

                    Stepper("Quantity: \(qty)", value: $qty, in: 1...999)
                }

                Section(header: Text("Notes").ditherSectionHeader()) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
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
                            Text(isEditing ? "Save" : "Add")
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
        guard let gear = gear else { return }
        name = gear.name
        brand = gear.brand
        category = gear.category
        if let w = gear.weight { weightText = String(Int(w)) }
        qty = gear.qty
        notes = gear.notes
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let weightGrams = Double(weightText.trimmingCharacters(in: .whitespaces))
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        do {
            if let gear = gear {
                try await state.updateGear(
                    id: gear.id,
                    name: trimmedName,
                    brand: brand,
                    category: category,
                    weight: weightGrams,
                    qty: qty,
                    notes: notes
                )
            } else {
                try await state.addGear(
                    name: trimmedName,
                    brand: brand,
                    category: category,
                    weight: weightGrams,
                    qty: qty,
                    notes: notes
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    GearFormView(gear: nil)
        .environmentObject(AppState.shared)
}
