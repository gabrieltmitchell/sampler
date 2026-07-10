import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    netWorthCard
                    statsGrid
                    goalCard
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("WealthPath")
        }
    }

    private var netWorthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Net Worth")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("hero_card_eyebrow")

            Text("$284,520")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .accessibilityIdentifier("hero_card_title")

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                Text("+$12,340 this month")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.green)
            .accessibilityIdentifier("hero_card_body")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.22, blue: 0.18), Color(red: 0.12, green: 0.32, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hero_card")
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            stat(title: "Monthly savings", value: "$2,400")
                .accessibilityIdentifier("annotations_stat_card")
            stat(title: "Investments", value: "$186K")
                .accessibilityIdentifier("export_modes_stat_card")
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Retirement Goal")
                .font(.headline)
                .accessibilityIdentifier("checkout_card_title")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target by 2045")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("$1,000,000")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    Text("68%")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.green)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                        Capsule()
                            .fill(Color.green)
                            .frame(width: geometry.size.width * 0.68)
                    }
                }
                .frame(height: 10)

                Text("$680,000 saved · $320,000 to go")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Retirement goal, 68 percent complete, 680 thousand saved of 1 million target")
            .accessibilityIdentifier("plan_card")

            Button {
            } label: {
                Text("Adjust Plan")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.08, green: 0.22, blue: 0.18))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityIdentifier("continue_button")
        }
        .padding(20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkout_card")
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.title.weight(.bold))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    ContentView()
}
