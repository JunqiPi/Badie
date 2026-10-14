import SwiftUI
import MapKit

// MARK: - 球馆可信度标记

struct VenueStatusBadge: View {
    let status: VenueStatus

    var body: some View {
        TagPill(text: status.title, icon: status.icon, fill: fill)
            .accessibilityLabel(accessibilityText)
    }

    private var fill: Color {
        switch status {
        case .verified: return AppTheme.Colors.mint
        case .confirmed: return AppTheme.Colors.sky
        case .unconfirmed: return AppTheme.Colors.butter
        }
    }

    private var accessibilityText: String {
        switch status {
        case .verified: return String(localized: "平台已核实地址")
        case .confirmed: return String(localized: "多位球友确认过地址")
        case .unconfirmed: return String(localized: "新添加，地址待确认")
        }
    }
}

// MARK: - 高亮搜索词

extension Text {
    /// 名称中与搜索词匹配的部分加粗并加柠檬底色，帮助用户一眼核对
    init(_ string: String, highlighting query: String) {
        var attributed = AttributedString(string)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty,
           let range = string.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]),
           let lower = AttributedString.Index(range.lowerBound, within: attributed),
           let upper = AttributedString.Index(range.upperBound, within: attributed) {
            attributed[lower..<upper].backgroundColor = AppTheme.Colors.lime.opacity(0.55)
            attributed[lower..<upper].foregroundColor = AppTheme.Colors.ink
        }
        self.init(attributed)
    }
}

// MARK: - 球馆行：名称 + 完整地址 + 距离/场地数/常去人数

struct VenueRow: View {
    enum Accessory: Equatable {
        case none
        case chevron
        case checkbox(isOn: Bool)
        case radio(isOn: Bool)
    }

    let venue: BadmintonCourt
    let distance: String
    var regulars: Int = 0
    var isFavorite = false
    var query = ""
    var accessory: Accessory = .chevron
    var isClosedForSlot = false

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            IconTile(systemName: "figure.badminton", fill: tileFill, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(venue.name, highlighting: query)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.dangerFill)
                            .accessibilityLabel("常去")
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Text(distance)
                        .font(AppTheme.Typography.footnoteBold)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                        .fixedSize()
                }
                if let alias = matchedAlias {
                    Text("又名 \(alias)")
                        .font(AppTheme.Typography.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                // 完整地址，用来确认“是不是这一家”
                Text(venue.postalAddress.compactLine, highlighting: query)
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    VenueStatusBadge(status: venue.status)
                    if !metaText.isEmpty {
                        Text(metaText)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                            .lineLimit(1)
                    }
                }
                if isClosedForSlot {
                    Label("所选时段不营业", systemImage: "moon.zzz.fill")
                        .font(AppTheme.Typography.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }
            accessoryView
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var tileFill: Color {
        switch accessory {
        case .checkbox(true), .radio(true): return AppTheme.Colors.lime
        default: return AppTheme.Colors.sky
        }
    }

    private var matchedAlias: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, venue.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == nil else { return nil }
        let normalized = VenueSearch.normalize(trimmed)
        return venue.aliases.first { VenueSearch.normalize($0).hasPrefix(normalized) }
    }

    private var metaText: String {
        var parts: [String] = []
        if let courts = venue.courtCount { parts.append(String(localized: "\(courts) 片场地")) }
        if regulars > 0 { parts.append(String(localized: "\(regulars) 人常去")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        case .checkbox(let isOn):
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isOn ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
                .accessibilityHidden(true)
        case .radio(let isOn):
            Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isOn ? AppTheme.Colors.ink : AppTheme.Colors.inkTertiary)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Apple 地图结果行（尚未进入球馆库）

struct MapResultRow: View {
    let title: String
    let subtitle: String
    var query = ""
    var isLoading = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            IconTile(systemName: "mappin.and.ellipse", fill: AppTheme.Colors.surfaceMuted, size: 42,
                     iconColor: AppTheme.Colors.ink)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title, highlighting: query)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle.isEmpty ? String(localized: "地址待确认") : subtitle)
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Apple 地图 · 选中后核对位置再加入")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            Spacer(minLength: 0)
            if isLoading {
                ProgressView()
                    .tint(AppTheme.Colors.ink)
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看位置并加入球馆库")
    }
}

// MARK: - 地图预览（确认位置用）

struct VenueMapPreview: View {
    let name: String
    let coordinate: Coordinate
    var height: CGFloat = 170
    var interactive = false

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate.clCoordinate,
                                                         latitudinalMeters: 700, longitudinalMeters: 700)),
            interactionModes: interactive ? .all : []) {
            Marker(name, systemImage: "figure.badminton", coordinate: coordinate.clCoordinate)
                .tint(AppTheme.Colors.ink)
        }
        .mapStyle(.standard(pointsOfInterest: .including([.parking, .publicTransport])))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            .strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
        .accessibilityLabel("\(name)的位置地图")
    }
}

// MARK: - 地址块（大字、可复制）

struct VenueAddressBlock: View {
    let address: PostalAddress
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(address.streetLine)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                Text(address.cityLine)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = address.singleLine
                Haptics.success()
                appState.showToast(String(localized: "地址已复制"), style: .success)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("复制地址")
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - “是不是这一家？”查重列表

struct DuplicateChoiceList: View {
    let duplicates: [VenueSearch.Duplicate]
    let onChoose: (BadmintonCourt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            Text(blocksAdding
                 ? String(localized: "名称和位置都跟已有球馆太接近，请直接选择它。大家选同一个球馆才能匹配到一起。")
                 : String(localized: "选同一个球馆，大家才能匹配到一起。如果是同楼的另一家，可以继续添加。"))
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            VStack(spacing: 0) {
                ForEach(Array(duplicates.enumerated()), id: \.element.venue.id) { index, duplicate in
                    if index > 0 { InsetDivider() }
                    Button {
                        onChoose(duplicate.venue)
                    } label: {
                        VenueRow(venue: duplicate.venue, distance: String(localized: "相距 \(DistanceFormatter.string(km: duplicate.distanceMeters / 1000))"),
                                 accessory: .none)
                            .overlay(alignment: .bottomTrailing) {
                                Text("是这个")
                                    .font(AppTheme.Typography.footnoteBold)
                                    .foregroundStyle(AppTheme.Colors.onAccent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(AppTheme.Colors.lime))
                                    .overlay(Capsule().strokeBorder(AppTheme.Colors.stroke, lineWidth: 1.5))
                                    .padding(.bottom, AppTheme.Spacing.md)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
        }
    }

    private var blocksAdding: Bool { duplicates.contains { $0.kind.blocksAdding } }

    private var title: String {
        blocksAdding ? String(localized: "球馆库里已有这家球馆") : String(localized: "同一位置已有球馆，是同一个吗？")
    }
}
