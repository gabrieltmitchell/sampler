import SwiftUI

struct ContentView: View {
    private let skeleton = Color.gray.opacity(0.14)
    private let outline = Color.gray.opacity(0.12)

    var body: some View {
        ZStack {
            Color(hex: 0xFAFAFA)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    heroModule
                    splitModules
                    timelineModule
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Skeleton app interface with header, modules, chart, and timeline")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                skeletonLine(width: 118, height: 14)
                skeletonLine(width: 176, height: 28)
            }

            Spacer()

            Circle()
                .fill(.white)
                .frame(width: 48, height: 48)
                .overlay {
                    Circle()
                        .fill(skeleton)
                        .frame(width: 26, height: 26)
                }
                .overlay {
                    Circle()
                        .stroke(outline, lineWidth: 1)
                }
                .softShadow()
                .accessibilityLabel("Profile button placeholder")
                .accessibilityIdentifier("profile_button")
        }
        .padding(.top, 4)
    }

    private var heroModule: some View {
        card(height: 182) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(skeleton)
                        .frame(width: 52, height: 52)

                    Spacer()

                    Capsule()
                        .fill(skeleton)
                        .frame(width: 76, height: 30)
                }

                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(skeleton)
                        .frame(height: 34)

                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            skeletonLine(width: 184, height: 14)
                            skeletonLine(width: 132, height: 12)
                            skeletonLine(width: 92, height: 12)
                        }

                        Spacer()

                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(skeleton)
                            .frame(width: 72, height: 48)
                    }
                }
                .padding(.top, 2)
                .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("hero_module")
    }

    private var splitModules: some View {
        HStack(spacing: 14) {
            card(height: 136, shadow: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Circle()
                        .fill(skeleton)
                        .frame(width: 42, height: 42)

                    Spacer(minLength: 8)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(skeleton)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                    skeletonLine(width: 72, height: 12)
                }
            }
            .accessibilityIdentifier("summary_module")

            card(height: 148, shadow: false, contentPadding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(skeleton)
                                .frame(width: 22, height: 22)
                            skeletonLine(width: index == 1 ? 78 : 96, height: 10)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("module_stack")
        }
    }

    private var timelineModule: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                timelineRow(isLast: index == 2)
            }
        }
        .background(alignment: .topLeading) {
            DashedVerticalLine()
                .stroke(outline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 1.5)
                .padding(.leading, 7.25)
                .padding(.top, 30)
                .padding(.bottom, 30)
        }
        .accessibilityIdentifier("timeline_module")
        .accessibilityLabel("Timeline list placeholder")
    }

    private func timelineRow(isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(outline, lineWidth: 1.5)
                }
                .padding(.top, 22)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    skeletonLine(width: 120, height: 10)
                    skeletonLine(width: 72, height: 10)
                    skeletonLine(width: 108, height: 10)
                    skeletonLine(width: 48, height: 10)
                }

                Spacer(minLength: 8)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(skeleton)
                    .frame(width: 92, height: 92)
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(outline, lineWidth: 1)
            }
        }
        .padding(.bottom, isLast ? 0 : 14)
    }

    private func card<Content: View>(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        shadow: Bool = true,
        contentPadding: CGFloat = 18,
        contentAlignment: Alignment = .topLeading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .frame(width: width, height: height, alignment: contentAlignment)
            .padding(contentPadding)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(outline, lineWidth: 1)
            }
            .modifier(SoftShadowModifier(isEnabled: shadow))
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(skeleton)
            .frame(width: width, height: height)
    }
}

private struct SoftShadowModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.softShadow()
        } else {
            content
        }
    }
}

private extension View {
    func softShadow() -> some View {
        shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 10)
    }
}

private struct DashedVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

#Preview {
    ContentView()
}
