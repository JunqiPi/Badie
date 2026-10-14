import SwiftUI

// MARK: - 轻提示

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
            Text(toast.message)
                .font(AppTheme.Typography.subheadlineBold)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .sticker(fill, radius: 16, shadow: AppTheme.Elevation.low)
        .padding(.horizontal, AppTheme.Spacing.screen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var icon: String {
        switch toast.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var fill: Color {
        switch toast.style {
        case .info: return AppTheme.Colors.sky
        case .success: return AppTheme.Colors.lime
        case .error: return AppTheme.Colors.pink
        }
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?
    var tint: Color = AppTheme.Colors.lavender
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            IconTile(systemName: icon, fill: tint, size: 64)
                .rotationEffect(.degrees(-6))
            Text(title)
                .font(AppTheme.Typography.title3)
                .foregroundStyle(AppTheme.Colors.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.brutal(.primary, size: .medium, fullWidth: false))
                    .padding(.top, AppTheme.Spacing.xs)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 横幅（定位关闭、演示模式等）

struct NoticeBanner: View {
    let icon: String
    let text: String
    var tint: Color = AppTheme.Colors.butter
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
            Text(text)
                .font(AppTheme.Typography.footnoteBold)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.brutal(.secondary, size: .small, fullWidth: false))
            }
        }
        .foregroundStyle(AppTheme.Colors.onAccent)
        .padding(AppTheme.Spacing.md)
        .sticker(tint, radius: 16, shadow: .zero)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 加载

struct LoadingDots: View {
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppTheme.Colors.ink)
                    .frame(width: 7, height: 7)
                    .opacity(reduceMotion ? 0.6 : (phase == index ? 1 : 0.3))
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("加载中")
    }
}

// MARK: - 输入框

struct BrutalTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var errorText: String?
    var characterLimit: Int?
    var axis: Axis = .horizontal

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer()
                if let characterLimit {
                    Text("\(text.count)/\(characterLimit)")
                        .font(AppTheme.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(text.count > characterLimit ? AppTheme.Colors.danger : AppTheme.Colors.inkTertiary)
                }
            }
            TextField(placeholder, text: $text, axis: axis)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.ink)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .focused($focused)
                .lineLimit(axis == .vertical ? 4 : 1)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
                .frame(minHeight: 52)
                .sticker(AppTheme.Colors.surface, radius: 14,
                         shadow: focused ? AppTheme.Elevation.low : .zero,
                         stroke: errorText == nil ? AppTheme.Colors.stroke : AppTheme.Colors.danger)
                .animation(AppTheme.Motion.press, value: focused)
            if let errorText {
                Text(errorText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
        }
    }
}

// MARK: - 日期条（未来 N 天，显示可约人数）

struct DateStrip: View {
    let days: [Date]
    @Binding var selection: Date
    var counts: (Date) -> Int? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(days, id: \.self) { day in
                    DateChip(day: day, isSelected: Calendar.current.isDate(day, inSameDayAs: selection), count: counts(day)) {
                        Haptics.selection()
                        withAnimation(AppTheme.Motion.standard) { selection = day }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, 6)
        }
    }
}

private struct DateChip: View {
    let day: Date
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(AppTheme.Typography.caption)
                Text("\(Calendar.current.component(.day, from: day))")
                    .scaledFont(size: 20, relativeTo: .title3)
                    .monospacedDigit()
                if let count {
                    Text("\(count)人")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.onAccent : AppTheme.Colors.ink)
            .frame(width: 52)
            .padding(.vertical, AppTheme.Spacing.sm)
            .sticker(isSelected ? AppTheme.Colors.lime : AppTheme.Colors.surface, radius: 16,
                     shadow: isSelected ? AppTheme.Elevation.low : .zero)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(DateText.relativeDay(day))\(count.map { "，\($0) 人有空" } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var label: String {
        Calendar.current.isDateInToday(day) ? "今天" : DateText.weekday(day)
    }
}
