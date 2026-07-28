import SwiftUI

struct WorkingTreatmentDoseEditor: View {
    @Binding var dose: WorkingTreatmentDose
    var isEnabled = true

    var body: some View {
        LabeledContent("Dose") {
            TextField("Amount", value: $dose.amount, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 110)
                .disabled(!isEnabled)
        }

        Picker("Unit", selection: $dose.unit) {
            Text("None").tag(Optional<WorkingTreatmentDoseUnit>.none)
            ForEach(WorkingTreatmentDoseUnit.allCases) { unit in
                Text(unit.label).tag(Optional(unit))
            }
        }
        .disabled(!isEnabled)

        Picker("Route", selection: $dose.route) {
            Text("None").tag(Optional<WorkingTreatmentAdministrationRoute>.none)
            ForEach(WorkingTreatmentAdministrationRoute.allCases) { route in
                Text(route.label).tag(Optional(route))
            }
        }
        .disabled(!isEnabled)
    }
}
