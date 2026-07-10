import SwiftUI

struct ContentView: View {
    private let activityData: [(day: String, minutes: CGFloat)] = [
        ("27", 28), ("28", 35), ("29", 22), ("30", 44), ("1", 31), ("2", 50), ("3", 18),
        ("4", 42), ("5", 48), ("6", 25), ("7", 55), ("8", 42), ("9", 60), ("10", 38)
    ]

    private let workouts: [(icon: String, name: String, time: String, calories: String)] = [
        ("figure.run", "Morning Run", "Today · 32 min", "286 kcal"),
        ("figure.strengthtraining.traditional", "Strength Training", "Yesterday · 45 min", "210 kcal"),
        ("figure.yoga", "Yoga Flow", "Wed · 28 min", "124 kcal"),
        ("figure.cycling", "Evening Ride", "Tue · 50 min", "340 kcal"),
        ("figure.walk", "Brisk Walk", "Mon · 22 min", "98 kcal"),
    ]

    @State private var selectedDay: Int? = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepsCard
                    activityChart
                    goalCard
                    workoutHistory
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FitPath")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "applewatch")
                            .font(.subheadline.weight(.semibold))
                        Text("78%")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.95))
                    .accessibilityLabel("Watch connected, 78 percent battery")
                    .accessibilityIdentifier("wearable_status")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(red: 0.20, green: 0.45, blue: 0.95))
                    }
                    .accessibilityLabel("Profile")
                    .accessibilityIdentifier("profile_button")
                }
            }
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Steps")
                .font(.caption)
                .foregroundStyle(Color(red: 0.55, green: 0.75, blue: 1.0))
                .accessibilityIdentifier("hero_card_eyebrow")

            Text("8,420")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .accessibilityIdentifier("hero_card_title")

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                Text("+1,240 vs yesterday")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color(red: 0.55, green: 0.82, blue: 1.0))
            .accessibilityIdentifier("hero_card_body")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.35),
                    Color(red: 0.08, green: 0.22, blue: 0.55)
                ],
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

    private var activityChart: some View {
        let maxMinutes = activityData.map(\.minutes).max() ?? 1
        let selected = selectedDay.map { activityData[$0] }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                if let selected {
                    Text("\(Int(selected.minutes)) min · \(selected.day)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.95))
                        .accessibilityLabel("\(Int(selected.minutes)) minutes on day \(selected.day)")
                }
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(activityData.indices, id: \.self) { index in
                    let entry = activityData[index]
                    let height = max(12, (entry.minutes / maxMinutes) * 110)
                    let isSelected = selectedDay == index

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDay = index
                        }
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    isSelected
                                        ? Color(red: 0.20, green: 0.45, blue: 0.95)
                                        : Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.28)
                                )
                                .frame(height: height)

                            Text(entry.day)
                                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color(red: 0.20, green: 0.45, blue: 0.95) : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Day \(entry.day), \(Int(entry.minutes)) active minutes")
                }
            }
            .frame(height: 140, alignment: .bottom)
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("annotations_stat_card")
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.95))
                Text("Weekly Step Goal")
                    .font(.headline)
                    .accessibilityIdentifier("checkout_card_title")
            }

            HStack(spacing: 16) {
                activityRings
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target this week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("50,000 steps")
                                .font(.title3.weight(.semibold))
                        }
                        Spacer()
                        Text("68%")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.95))
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.15))
                            Capsule()
                                .fill(Color(red: 0.20, green: 0.45, blue: 0.95))
                                .frame(width: geometry.size.width * 0.68)
                        }
                    }
                    .frame(height: 10)

                    Text("34,000 done · 16,000 to go")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Weekly step goal, 68 percent complete, 34 thousand steps of 50 thousand target")
            .accessibilityIdentifier("plan_card")

            HStack(spacing: 16) {
                fitnessIcon(systemName: "flame.fill", label: "Move", color: Color(red: 0.95, green: 0.30, blue: 0.35))
                fitnessIcon(systemName: "figure.walk", label: "Steps", color: Color(red: 0.35, green: 0.85, blue: 0.45))
                fitnessIcon(systemName: "figure.run", label: "Exercise", color: Color(red: 0.35, green: 0.75, blue: 0.95))
            }

            Button {
            } label: {
                Text("Log Activity")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.08, green: 0.22, blue: 0.55))
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

    private var activityRings: some View {
        let deepBlue = Color(red: 0.08, green: 0.22, blue: 0.55)
        let midBlue = Color(red: 0.20, green: 0.45, blue: 0.95)
        let lightBlue = Color(red: 0.45, green: 0.70, blue: 1.0)

        return ZStack {
            Circle()
                .stroke(deepBlue.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: 0.82)
                .stroke(deepBlue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(midBlue.opacity(0.2), lineWidth: 8)
                .padding(10)
            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(midBlue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(10)

            Circle()
                .stroke(lightBlue.opacity(0.25), lineWidth: 8)
                .padding(20)
            Circle()
                .trim(from: 0, to: 0.55)
                .stroke(lightBlue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(20)
        }
        .accessibilityHidden(true)
    }

    private var workoutHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Workout History")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(workouts.indices, id: \.self) { index in
                    let workout = workouts[index]
                    HStack(spacing: 14) {
                        Image(systemName: workout.icon)
                            .font(.title3)
                            .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.95))
                            .frame(width: 40, height: 40)
                            .background(Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name)
                                .font(.subheadline.weight(.semibold))
                            Text(workout.time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(workout.calories)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.45, blue: 0.95))
                    }
                    .padding(.vertical, 12)

                    if index < workouts.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("export_modes_stat_card")
    }

    private func fitnessIcon(systemName: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12))
                .clipShape(Circle())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}
