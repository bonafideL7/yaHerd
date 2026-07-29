import SwiftUI

struct WorkingTreatmentDoseEditor: View {
    @Binding var dose: WorkingTreatmentDose
    var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dose")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Enter dose amount", value: $dose.amount, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .disabled(!isEnabled)

            Picker("Unit", selection: $dose.unit) {
                Text("Select unit").tag(Optional<WorkingTreatmentDoseUnit>.none)
                ForEach(WorkingTreatmentDoseUnit.allCases) { unit in
                    Text(unit.label).tag(Optional(unit))
                }
            }
            .disabled(!isEnabled)

            Picker("Route", selection: $dose.route) {
                Text("Select route").tag(Optional<WorkingTreatmentAdministrationRoute>.none)
                ForEach(WorkingTreatmentAdministrationRoute.allCases) { route in
                    Text(route.label).tag(Optional(route))
                }
            }
            .disabled(!isEnabled)
        }
        .padding(.vertical, 2)
    }
}
