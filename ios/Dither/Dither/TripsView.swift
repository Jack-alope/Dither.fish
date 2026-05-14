import SwiftUI

struct TripsView: View {
    @EnvironmentObject var state: AppState
    @State private var showAddTrip = false

    @ViewBuilder
    func tripRow(_ trip: Trip) -> some View {
        NavigationLink(destination: TripDetailView(tripId: trip.id)) {
            TripRowView(trip: trip)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    if trip.archived {
                        try? await state.unarchiveTrip(id: trip.id)
                    } else {
                        try? await state.archiveTrip(id: trip.id)
                    }
                }
            } label: {
                Label(trip.archived ? "Unarchive" : "Archive",
                      systemImage: trip.archived ? "arrow.uturn.up.circle" : "archivebox")
            }
            .tint(trip.archived ? .blue : .secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { try? await state.deleteTrip(id: trip.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.isLoading && state.trips.isEmpty {
                    ProgressView("Loading trips...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if state.trips.isEmpty {
                    EmptyStateView(
                        icon: "map",
                        title: "No trips yet",
                        message: "Plan your next adventure by tapping the + button"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let error = state.error {
                            ErrorBanner(message: error) { state.error = nil }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        let upcoming  = state.trips.filter { !$0.archived }
                        let completed = state.trips.filter {  $0.archived }

                        if !upcoming.isEmpty {
                            Section(header: Text("Upcoming Trips").ditherSectionHeader()) {
                                ForEach(upcoming) { trip in
                                    tripRow(trip)
                                }
                            }
                        }

                        if !completed.isEmpty {
                            Section(header: Text("Completed Trips").ditherSectionHeader()) {
                                ForEach(completed) { trip in
                                    tripRow(trip)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await state.fetchTrips() }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddTrip = true }) {
                        Label("New Trip", systemImage: "plus")
                    }
                    .tint(.ditherGreen)
                }
            }
            .sheet(isPresented: $showAddTrip) {
                TripFormView(trip: nil)
            }
        }
    }
}

struct TripRowView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(trip.name)
                    .font(.headline)
                if trip.archived {
                    Text("Completed")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
            }

            if !trip.destination.isEmpty {
                Label(trip.destination, systemImage: "location.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                if !trip.startDate.isEmpty || !trip.endDate.isEmpty {
                    Label(dateRange, systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !trip.packs.isEmpty {
                    Label("\(trip.packs.count) pack\(trip.packs.count == 1 ? "" : "s")", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundColor(.ditherGreen)
                }
            }
        }
        .padding(.vertical, 4)
    }

    var dateRange: String {
        let start = formatDateString(trip.startDate)
        let end = formatDateString(trip.endDate)
        if start.isEmpty && end.isEmpty { return "" }
        if start == end { return start }
        return "\(start) – \(end)"
    }
}

#Preview {
    TripsView()
        .environmentObject(AppState.shared)
}
