import SwiftUI

struct BundleFormView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let bundle: GearBundle?

    @State private var bundleName = ""
    @State private var items: [BundleItem] = []
    @State private var addSearchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var isEditing: Bool { bundle != nil }
    var canSave: Bool { !bundleName.trimmingCharacters(in: .whitespaces).isEmpty }

    var gearInBundle: Set<String> { Set(items.map { $0.gearId }) }

    var gearNotInBundle: [GearItem] {
        state.gear
            .filter { !gearInBundle.contains($0.id) }
            .filter {
                addSearchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(addSearchText) ||
                $0.brand.localizedCaseInsensitiveContains(addSearchText)
            }
    }

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

                Section(header: Text("Bundle Name").ditherSectionHeader()) {
                    TextField("Bundle Name *", text: $bundleName)
                }

                if !items.isEmpty {
                    Section(header: Text("Items in Bundle").ditherSectionHeader()) {
                        ForEach(Array(items.enumerated()), id: \.element.gearId) { index, bundleItem in
                            if let gear = state.gearById(bundleItem.gearId) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(gear.name).font(.body)
                                        Text(gear.brand).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Button(action: {
                                            if items[index].qty > 1 {
                                                items[index] = BundleItem(gearId: items[index].gearId, qty: items[index].qty - 1)
                                            }
                                        }) {
                                            Image(systemName: "minus.circle")
                                                .foregroundColor(.ditherGreen)
                                        }
                                        .buttonStyle(.plain)

                                        Text("\(bundleItem.qty)")
                                            .frame(minWidth: 24)
                                            .multilineTextAlignment(.center)

                                        Button(action: {
                                            items[index] = BundleItem(gearId: items[index].gearId, qty: items[index].qty + 1)
                                        }) {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.ditherGreen)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            items.remove(atOffsets: indexSet)
                        }
                    }
                }

                Section(header: Text("Add Gear").ditherSectionHeader()) {
                    if state.gear.isEmpty {
                        Text("No gear in your locker yet")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        TextField("Search gear...", text: $addSearchText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 4)

                        if gearNotInBundle.isEmpty {
                            if addSearchText.isEmpty {
                                Text("All gear is already in this bundle")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            } else {
                                Text("No matching gear")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        } else {
                            ForEach(gearNotInBundle) { gear in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(gear.name).font(.body)
                                        Text(gear.brand).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let w = gear.weight {
                                        WeightBadge(grams: w)
                                    }
                                    Button(action: {
                                        items.append(BundleItem(gearId: gear.id, qty: 1))
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.ditherGreen)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Bundle" : "New Bundle")
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
                            Text(isEditing ? "Save" : "Create")
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
        guard let bundle = bundle else { return }
        bundleName = bundle.name
        items = bundle.items
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedName = bundleName.trimmingCharacters(in: .whitespaces)

        do {
            if let bundle = bundle {
                try await state.updateBundle(id: bundle.id, name: trimmedName, items: items)
            } else {
                try await state.addBundle(name: trimmedName)
                // After creation, if there are items, update immediately
                if !items.isEmpty, let newBundle = state.bundles.last {
                    try await state.updateBundle(id: newBundle.id, name: trimmedName, items: items)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    BundleFormView(bundle: nil)
        .environmentObject(AppState.shared)
}
