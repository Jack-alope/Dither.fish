import SwiftUI

struct TripFormView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let trip: Trip?

    @State private var name = ""
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400 * 3)
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var isEditing: Bool { trip != nil }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

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

                Section(header: Text("Trip Details").ditherSectionHeader()) {
                    TextField("Trip Name *", text: $name)
                    TextField("Destination", text: $destination)
                }

                Section(header: Text("Dates").ditherSectionHeader()) {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .tint(.ditherGreen)
                    DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .tint(.ditherGreen)
                }

                Section(header: Text("Notes").ditherSectionHeader()) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isEditing ? "Edit Trip" : "New Trip")
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
        guard let trip = trip else { return }
        name = trip.name
        destination = trip.destination
        notes = trip.notes

        if let d = dateFormatter.date(from: trip.startDate) { startDate = d }
        if let d = dateFormatter.date(from: trip.endDate) { endDate = d }
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let startStr = dateFormatter.string(from: startDate)
        let endStr = dateFormatter.string(from: endDate)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        do {
            if var trip = trip {
                trip.name = trimmedName
                trip.destination = destination
                trip.startDate = startStr
                trip.endDate = endStr
                trip.notes = notes
                try await state.updateTrip(trip)
            } else {
                try await state.addTrip(
                    name: trimmedName,
                    destination: destination,
                    startDate: startStr,
                    endDate: endStr,
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
    TripFormView(trip: nil)
        .environmentObject(AppState.shared)
}
