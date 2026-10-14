import SwiftUI

// MARK: - 票据形状（左右各一个半圆缺口，用于球局卡片）

struct TicketShape: InsettableShape {
    var cornerRadius: CGFloat = 22
    var notchRadius: CGFloat = 11
    /// 缺口中心距顶部的比例（0-1）
    var notchPosition: CGFloat = 0.62
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
        let notch = notchRadius
        let notchY = rect.minY + rect.height * notchPosition

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: notchY - notch))
        path.addArc(center: CGPoint(x: rect.maxX, y: notchY), radius: notch,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: notchY + notch))
        path.addArc(center: CGPoint(x: rect.minX, y: notchY), radius: notch,
                    startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> TicketShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// 票据虚线分隔
struct DashedDivider: View {
    var color: Color = AppTheme.Colors.onAccent

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - 爆炸星形（VS、折扣式徽章）

struct Starburst: Shape {
    var points: Int = 12
    var innerRatio: CGFloat = 0.78

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var path = Path()
        for index in 0..<(points * 2) {
            let angle = Double(index) * .pi / Double(points) - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct StarburstBadge: View {
    let text: String
    var fill: Color = AppTheme.Colors.butter
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Starburst()
                .fill(AppTheme.Colors.shadow)
                .offset(x: 2, y: 3)
            Starburst()
                .fill(fill)
            Starburst()
                .stroke(AppTheme.Colors.stroke, lineWidth: 2)
            Text(text)
                .font(.system(size: size * 0.3, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.onAccent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 品牌标识：羽毛球（球托 + 羽毛裙）

struct ShuttlecockMark: View {
    var size: CGFloat = 64
    var fill: Color = AppTheme.Colors.lime

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(2, w * 0.045)
            let ink = GraphicsContext.Shading.color(Color(hex: 0x17140F))

            // 羽毛裙（梯形）
            var skirt = Path()
            skirt.move(to: CGPoint(x: w * 0.18, y: h * 0.08))
            skirt.addLine(to: CGPoint(x: w * 0.82, y: h * 0.08))
            skirt.addLine(to: CGPoint(x: w * 0.64, y: h * 0.62))
            skirt.addLine(to: CGPoint(x: w * 0.36, y: h * 0.62))
            skirt.closeSubpath()
            context.fill(skirt, with: .color(.white))
            context.stroke(skirt, with: ink, lineWidth: line)

            // 羽毛分隔线
            for fraction in [0.35, 0.5, 0.65] {
                var rib = Path()
                rib.move(to: CGPoint(x: w * (0.18 + (0.82 - 0.18) * fraction), y: h * 0.08))
                rib.addLine(to: CGPoint(x: w * (0.36 + (0.64 - 0.36) * fraction), y: h * 0.62))
                context.stroke(rib, with: ink, lineWidth: line * 0.7)
            }
            // 绑线
            var band = Path()
            band.move(to: CGPoint(x: w * 0.27, y: h * 0.36))
            band.addLine(to: CGPoint(x: w * 0.73, y: h * 0.36))
            context.stroke(band, with: ink, lineWidth: line * 0.7)

            // 球托（半圆 + 底部）
            let cork = Path(ellipseIn: CGRect(x: w * 0.32, y: h * 0.56, width: w * 0.36, height: h * 0.36))
            context.fill(cork, with: .color(fill))
            context.stroke(cork, with: ink, lineWidth: line)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 文字标识 "badie."
struct Wordmark: View {
    var size: CGFloat = 40

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text("badie")
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.ink)
            Circle()
                .fill(AppTheme.Colors.lime)
                .overlay(Circle().strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
                .frame(width: size * 0.32, height: size * 0.32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Badie")
    }
}
