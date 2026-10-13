import SwiftUI
import MapKit

/// 附近球馆：地图 + 列表（每行带地址），可搜索、添加、收藏、查看详情、导航
struct CourtsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedCourt: BadmintonCourt?
    @State private var showRadius = false
    @State private var showSearch = false
    @State private var addDraft: AddVenueDraft?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "附近球馆") {
                HStack(spacing: AppTheme.Spacing.sm) {
                    IconButton(systemName: "magnifyingglass", accessibilityLabel: "搜索球馆") {
                        showSearch = true
                    }
                    IconButton(systemName: "slider.horizontal.3", accessibilityLabel: "出行范围") {
                        showRadius = true
                    }
                }
            }
            Map(position: $position) {
                ForEach(locationManager.nearbyCourts) { court in
                    Annotation(court.name, coordinate: court.location.clCoordinate, anchor: .bottom) {
                        Button {
                            selectedCourt = court
                        } label: {
                            CourtPin(isSelected: matchManager.draft.courtIds.contains(court.id), size: 38)
                        }
                        .accessibilityLabel(court.name)
                    }
                }
                UserAnnotation()
                MapCircle(center: locationManager.coordinate.clCoordinate, radius: locationManager.preferences.travelRadiusKm * 1000)
                    .foregroundStyle(AppTheme.Colors.lime.opacity(0.12))
                    .stroke(Color(hex: 0x17140F).opacity(0.4), lineWidth: 1.5)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous).strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
            .padding(.horizontal, AppTheme.Spacing.screen)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    SectionTitle(title: "\(locationManager.nearbyCourts.count) 家球馆", detail: locationManager.radiusText)
                    if locationManager.nearbyCourts.isEmpty {
                        EmptyStateView(icon: "mappin.slash", title: "\(locationManager.radiusText)还没有收录的球馆",
                                       message: "搜索球馆名或地址，也可以自己添加常去的球馆。",
                                       actionTitle: "搜索球馆") { showSearch = true }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(locationManager.nearbyCourts.enumerated()), id: \.element.id) { index, court in
                                if index > 0 { InsetDivider() }
                                Button {
                                    selectedCourt = court
                                    withAnimation {
                                        position = .region(MKCoordinateRegion(center: court.location.clCoordinate,
                                                                              latitudinalMeters: 3000, longitudinalMeters: 3000))
                                    }
                                } label: {
                                    VenueRow(venue: court,
                                             distance: court.formattedDistance(from: locationManager.coordinate),
                                             regulars: appState.backend.regularsCount(for: court.id),
                                             isFavorite: locationManager.isFavorite(court.id))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
                    }
                    Button {
                        addDraft = AddVenueDraft(name: "", coordinate: locationManager.coordinate)
                    } label: {
                        Label("找不到？添加球馆", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium, fullWidth: true))
                    .padding(.top, AppTheme.Spacing.sm)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
        .sheet(item: $selectedCourt) { court in
            CourtDetailSheet(court: court)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRadius) {
            TravelRadiusSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSearch) {
            VenuePickerView(mode: .browse, selection: .constant([]))
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $addDraft) { draft in
            AddVenueView(initialCoordinate: draft.coordinate) { venue in
                addDraft = nil
                selectedCourt = venue
            }
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - 球馆详情

struct CourtDetailSheet: View {
    let court: BadmintonCourt

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    @State private var showNavigation = false
    @State private var showReport = false
    @State private var hasConfirmed = false

    /// 最新数据（确认后状态会变化）
    private var venue: BadmintonCourt { appState.backend.venue(id: court.id) ?? court }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(venue.name)
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !venue.aliases.isEmpty {
                            Text("又名 " + venue.aliases.joined(separator: " · "))
                                .font(AppTheme.Typography.footnoteBold)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                        VenueStatusBadge(status: venue.status)
                    }
                    Spacer()
                    IconButton(systemName: locationManager.isFavorite(venue.id) ? "heart.fill" : "heart",
                               accessibilityLabel: locationManager.isFavorite(venue.id) ? "取消常去" : "设为常去",
                               accent: locationManager.isFavorite(venue.id) ? AppTheme.Colors.pink : nil) {
                        Haptics.selection()
                        locationManager.toggleFavorite(venue.id)
                    }
                }
                .padding(.top, AppTheme.Spacing.xl)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    VenueMapPreview(name: venue.name, coordinate: venue.location, height: 160)
                    VenueAddressBlock(address: venue.postalAddress)
                    if let note = venue.entranceNote {
                        Label(note, systemImage: "door.left.hand.open")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)

                HStack(spacing: AppTheme.Spacing.sm) {
                    StatTile(value: venue.formattedDistance(from: locationManager.coordinate), label: "距离")
                    StatTile(value: venue.courtCount.map { "\($0)" } ?? "–", label: "场地数")
                    StatTile(value: "\(appState.backend.regularsCount(for: venue.id))", label: "人常去")
                }

                VStack(alignment: .leading, spacing: 0) {
                    InfoRow(icon: Money.icon(for: venue.currencyCode), tint: AppTheme.Colors.butter,
                            title: venue.pricingText,
                            subtitle: venue.pricingNote ?? (venue.pricing.isKnown ? "以球馆实际收费为准" : "去过的球友可以告诉大家"))
                    InsetDivider()
                    InfoRow(icon: "clock.fill", tint: AppTheme.Colors.peach,
                            title: venue.hoursText,
                            subtitle: venue.operatingHours.map { $0.formattedDaysOpen + timeZoneSuffix } ?? "出发前建议先电话确认")
                    if let phone = venue.phone {
                        InsetDivider()
                        Button {
                            Task { _ = await MapsLauncher.call(phone) }
                        } label: {
                            InfoRow(icon: "phone.fill", tint: AppTheme.Colors.mint, title: phone, subtitle: "致电球馆预订场地")
                        }
                        .buttonStyle(.plain)
                    }
                    if let website = venue.website, let url = URL(string: website) {
                        InsetDivider()
                        Link(destination: url) {
                            InfoRow(icon: "safari.fill", tint: AppTheme.Colors.sky,
                                    title: url.host ?? website, subtitle: "官网 / 预订页面")
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)

                trustSection

                if !venue.amenities.isEmpty {
                    FlowLayout(spacing: AppTheme.Spacing.sm) {
                        ForEach(venue.amenities, id: \.self) { amenity in
                            TagPill(text: amenity.rawValue, icon: amenity.icon, fill: AppTheme.Colors.sky)
                        }
                    }
                }

                let selected = matchManager.draft.courtIds.contains(venue.id)
                Button {
                    if !matchManager.draft.toggleCourt(venue.id) {
                        appState.showToast("快速匹配最多选择 \(MatchDraft.maxCourts) 个球馆")
                    } else {
                        Haptics.selection()
                    }
                } label: {
                    Label(selected ? "已加入快速匹配（点按移除）" : "加入快速匹配的球馆", systemImage: selected ? "checkmark.circle.fill" : "plus.circle.fill")
                }
                .buttonStyle(.brutal(selected ? .secondary : .primary, size: .medium))

                Button {
                    showNavigation = true
                } label: {
                    Label("导航到这里", systemImage: "location.north.line.fill")
                }
                .buttonStyle(.brutal(.inverse, size: .medium))
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear { hasConfirmed = appState.backend.hasConfirmed(venue.id) }
        .confirmationDialog("选择导航方式", isPresented: $showNavigation, titleVisibility: .visible) {
            ForEach(MapsLauncher.apps(for: venue)) { app in
                Button(app.title) {
                    Task {
                        if !(await MapsLauncher.open(venue, with: app)) {
                            appState.showToast("未安装\(app.title)", style: .error)
                        }
                    }
                }
            }
        }
        .confirmationDialog("这个球馆有什么问题？", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(VenueIssue.allCases) { issue in
                Button(issue.rawValue) {
                    do {
                        try appState.backend.reportVenue(venue.id, issue: issue)
                        appState.showToast("谢谢，我们会尽快核实", style: .success)
                    } catch {
                        appState.showError(error)
                    }
                }
            }
        } message: {
            Text("一个人的报告不会让球馆下架；多位球友报告后会进入人工核实。")
        }
    }

    private var timeZoneSuffix: String {
        venue.timeZoneAbbreviation.map { " · 当地时间（\($0)）" } ?? ""
    }

    // MARK: 可信度

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(sourceText)
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppTheme.Spacing.sm) {
                if venue.status != .verified {
                    Button {
                        do {
                            try appState.backend.confirmVenue(venue.id)
                            hasConfirmed = true
                            Haptics.success()
                            appState.showToast("谢谢确认！", style: .success)
                        } catch {
                            appState.showError(error)
                        }
                    } label: {
                        Label(hasConfirmed ? "你已确认过" : "我去过，地址正确", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: true))
                    .disabled(hasConfirmed)
                }
                Button {
                    showReport = true
                } label: {
                    Label("信息有误", systemImage: "exclamationmark.bubble.fill")
                }
                .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .small, fullWidth: venue.status != .verified))
            }
        }
        .padding(AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surfaceMuted, radius: AppTheme.Radius.lg, shadow: .zero)
    }

    private var sourceText: String {
        let freshness = venue.lastConfirmedAt.map { " · 最近确认 \(DateText.relative($0))" } ?? ""
        switch venue.status {
        case .verified:
            return "平台已核实地址\(freshness)"
        case .confirmed:
            return "\(venue.confirmedBy.count) 位球友确认过地址\(freshness)"
        case .unconfirmed:
            let origin = venue.source == .appleMaps ? "来自 Apple 地图，由球友加入" : "由球友添加"
            return "\(origin) · \(venue.confirmedBy.count)/\(BadmintonCourt.confirmationsNeeded) 位确认\(freshness)"
        }
    }
}

// MARK: - 球馆单选（建房间、改房间信息时使用）

struct CourtPickerSheet: View {
    @Binding var selectedId: String?
    var slot: TimeSlot?

    var body: some View {
        VenuePickerView(
            mode: .single,
            selection: Binding(
                get: { selectedId.map { [$0] } ?? [] },
                set: { selectedId = $0.first }
            ),
            slot: slot
        )
    }
}

// MARK: - 出行范围（公里/英里跟随设备地区）

struct TravelRadiusSheet: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = UserPreferences.defaultTravelRadius

    private var unit: DistanceUnit { locationManager.distanceUnit }

    private var range: ClosedRange<Double> {
        let low = (unit.value(fromKm: UserPreferences.minimumTravelRadius)).rounded(.up)
        let high = (unit.value(fromKm: UserPreferences.maximumTravelRadius)).rounded(.down)
        return max(1, low)...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("出行范围")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Int(value))")
                    .scaledFont(size: 48)
                    .monospacedDigit()
                Text("\(unit.title)内")
                    .font(AppTheme.Typography.headline)
            }
            .foregroundStyle(AppTheme.Colors.ink)
            Slider(value: $value, in: range, step: 1)
                .tint(AppTheme.Colors.ink)
                .accessibilityLabel("出行范围")
                .accessibilityValue("\(Int(value)) \(unit.title)")
            Text("只显示并匹配这个范围内的球馆和球友；搜索不受范围限制")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Button("完成") {
                let km = min(UserPreferences.maximumTravelRadius, max(UserPreferences.minimumTravelRadius, unit.km(from: value)))
                locationManager.updateTravelRadius(km)
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            value = min(range.upperBound, max(range.lowerBound, unit.value(fromKm: locationManager.preferences.travelRadiusKm).rounded()))
        }
    }
}
