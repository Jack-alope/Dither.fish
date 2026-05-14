import SwiftUI

struct TripDetailView: View {
    @EnvironmentObject var state: AppState
    let tripId: String

    @State private var selectedPackIndex: Int = 0
    @State private var showEditTrip = false
    @State private var showDeleteConfirm = false
    @State private var isAddingPack = false

    // Pack rename / delete
    @State private var renamingPackIndex: Int? = nil
    @State private var showRenamePackSheet = false
    @State private var deletingPackIndex: Int? = nil
    @State private var showDeletePackConfirm = false

    @Environment(\.dismiss) private var dismiss

    var trip: Trip? {
        state.trips.first { $0.id == tripId }
    }

    var body: some View {
        Group {
            if let trip {
                VStack(spacing: 0) {
                    // Archived banner
                    if trip.archived {
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox.fill")
                            Text("This trip is archived — gear is frozen at the time of completion.")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary)
                    }

                    // Trip info header
                    TripInfoHeader(trip: trip)

                    // Pack tab selector (shown whenever there are packs)
                    if !trip.packs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(trip.packs.enumerated()), id: \.offset) { i, pack in
                                    Button(action: { selectedPackIndex = i }) {
                                        Text(pack.name)
                                            .font(.subheadline)
                                            .fontWeight(selectedPackIndex == i ? .semibold : .regular)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(selectedPackIndex == i ? Color.ditherGreen : Color(.systemGray5))
                                            .foregroundColor(selectedPackIndex == i ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                    .contextMenu {
                                        Button {
                                            renamingPackIndex = i
                                            showRenamePackSheet = true
                                        } label: {
                                            Label("Rename Pack", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            deletingPackIndex = i
                                            showDeletePackConfirm = true
                                        } label: {
                                            Label("Delete Pack", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .background(Color(.systemBackground))
                        Divider()
                    }

                    // Pack content — fills remaining space
                    let packIdx = min(selectedPackIndex, max(0, trip.packs.count - 1))
                    if trip.packs.isEmpty {
                        EmptyStateView(
                            icon: "archivebox",
                            title: "No packs yet",
                            message: "Tap + Add Pack to start organising your gear"
                        )
                        Spacer()
                    } else {
                        PackView(tripId: tripId, packIndex: packIdx)
                    }
                }
                .navigationTitle(trip.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if !trip.archived {
                            Button(action: { Task { await addPack(trip) } }) {
                                if isAddingPack {
                                    ProgressView().tint(.ditherGreen)
                                } else {
                                    Label("Add Pack", systemImage: "plus.square.on.square")
                                }
                            }
                            .tint(.ditherGreen)
                            .disabled(isAddingPack)

                            Button(action: { showEditTrip = true }) {
                                Image(systemName: "pencil")
                            }
                            .tint(.ditherGreen)
                        }

                        Menu {
                            if trip.archived {
                                Button {
                                    Task { try? await state.unarchiveTrip(id: tripId) }
                                } label: {
                                    Label("Unarchive Trip", systemImage: "arrow.uturn.up.circle")
                                }
                            } else {
                                Button {
                                    Task { try? await state.archiveTrip(id: tripId) }
                                } label: {
                                    Label("Archive Trip", systemImage: "archivebox")
                                }
                            }
                            Divider()
                            Button(role: .destructive, action: { showDeleteConfirm = true }) {
                                Label("Delete Trip", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .tint(.ditherGreen)
                    }
                }
                .sheet(isPresented: $showEditTrip) {
                    TripFormView(trip: trip)
                }
                .sheet(isPresented: $showRenamePackSheet) {
                    if let idx = renamingPackIndex, idx < trip.packs.count {
                        RenamePackSheet(
                            currentName: trip.packs[idx].name,
                            onSave: { newName in
                                Task { try? await state.renamePack(tripId: tripId, packIndex: idx, name: newName) }
                            }
                        )
                    }
                }
                .confirmationDialog("Delete Trip", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete \"\(trip.name)\"", role: .destructive) {
                        Task {
                            try? await state.deleteTrip(id: tripId)
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete the trip and all its packs.")
                }
                .confirmationDialog("Delete Pack", isPresented: $showDeletePackConfirm, titleVisibility: .visible) {
                    Button("Delete \"\(deletingPackIndex.flatMap { $0 < trip.packs.count ? trip.packs[$0].name : nil } ?? "Pack")\"", role: .destructive) {
                        if let idx = deletingPackIndex {
                            Task { try? await state.deletePack(tripId: tripId, packIndex: idx) }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently remove the pack and all its gear assignments.")
                }
                .onChange(of: trip.packs.count) {
                    if selectedPackIndex >= trip.packs.count {
                        selectedPackIndex = max(0, trip.packs.count - 1)
                    }
                }
            } else {
                ContentUnavailableView("Trip not found", systemImage: "map")
            }
        }
    }

    private func addPack(_ trip: Trip) async {
        isAddingPack = true
        defer { isAddingPack = false }
        try? await state.addPackToTrip(tripId: tripId)
        if let t = state.trips.first(where: { $0.id == tripId }) {
            selectedPackIndex = t.packs.count - 1
        }
    }
}

// MARK: - Rename Pack Sheet
struct RenamePackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentName: String
    let onSave: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pack name", text: $name)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Rename Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { onSave(trimmed) }
                        dismiss()
                    }
                    .tint(.ditherGreen)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(180)])
        .onAppear { name = currentName }
    }
}

// MARK: - Trip info header strip
struct TripInfoHeader: View {
    let trip: Trip
    var body: some View {
        let hasInfo = !trip.destination.isEmpty || !trip.startDate.isEmpty || !trip.endDate.isEmpty || !trip.notes.isEmpty
        if hasInfo {
            VStack(alignment: .leading, spacing: 6) {
                if !trip.destination.isEmpty {
                    Label(trip.destination, systemImage: "location.fill")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                let dateStr = buildDateRange(trip)
                if !dateStr.isEmpty {
                    Label(dateStr, systemImage: "calendar")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                if !trip.notes.isEmpty {
                    Text(trip.notes)
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            Divider()
        }
    }

    private func buildDateRange(_ trip: Trip) -> String {
        let s = formatDateString(trip.startDate)
        let e = formatDateString(trip.endDate)
        if s.isEmpty && e.isEmpty { return "" }
        if s == e || e.isEmpty { return s }
        if s.isEmpty { return e }
        return "\(s) – \(e)"
    }
}
