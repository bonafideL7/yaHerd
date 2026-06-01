import SwiftUI

struct HomeView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image("Cow")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("yaHerd")
                            .font(.title2.weight(.semibold))

                        Text("Use the tabs below to move between Home and herd records. Open pasture tiles from the YaHerd screen. Management settings are available from the top-right button.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Navigation") {
                Label("YaHerd contains animal records.", systemImage: "tag")
                Label("Use the YaHerd screen button to switch between animal records and pasture tiles.", systemImage: "square.grid.2x2")
                Label("Manage is available from the top-right button.", systemImage: "slider.horizontal.3")
            }
        }
        .navigationTitle("Home")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
