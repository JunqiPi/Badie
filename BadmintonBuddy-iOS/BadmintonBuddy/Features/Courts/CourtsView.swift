import SwiftUI
import MapKit

/// 附近球馆：地图 + 列表，可收藏、查看详情、导航、加入匹配
struct CourtsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var matchManager: MatchManager

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedCourt: BadmintonCourt?
    @State private var showRadius = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "附近球馆") {
                IconButton(systemName: "slider.horizontal.3", accessibilityLabel: "出行范围") {
                    showRadius = true
                }
            }
            ZStack(alignment: .bottom) {
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
                .frame(maxHeight: .infinity)

                if locationManager.isSearchingCourts {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        LoadingDots()
                        Text("正在搜索附近球馆…")
                            .font(AppTheme.Typography.footnoteBold)
                    }
                    .padding(AppTheme.Spacing.md)
                    .sticker(AppTheme.Colors.surface, radius: 14)
                    .padding(.bottom, AppTheme.Spacing.md)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous).strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
            .padding(.horizontal, AppTheme.Spacing.screen)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    SectionTitle(title: "\(locationManager.nearbyCourts.count) 家球馆",
                                 detail: "\(Int(locationManager.preferences.travelRadiusKm)) 公里内")
                    if locationManager.nearbyCourts.isEmpty {
                        EmptyStateView(icon: "mappin.slash", title: "出行范围内没有球馆",
                                       message: "调大出行范围试试", actionTitle: "调整范围") { showRadius = true }
                    }
                    ForEach(locationManager.nearbyCourts) { court in
                        Button {
                            selectedCourt = court
                            withAnimation { position = .region(MKCoordinateRegion(center: court.location.clCoordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)) }
                        } label: {
                            CourtRow(court: court,
                                     distance: court.formattedDistance(from: locationManager.coordinate),
                                     isFavorite: locationManager.isFavorite(court.id),
                                     isSelectedForMatch: matchManager.draft.courtIds.contains(court.id))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                    if locationManager.courts.contains(where: { $0.source == .sample }) {
                        Text("当前城市暂无收录数据，部分为示例球馆")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
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
    }
}

struct CourtRow: View {
    let court: BadmintonCourt
    let distance: String
    var isFavorite = false
    var isSelectedForMatch = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            IconTile(systemName: "figure.badminton", fill: isSelectedForMatch ? AppTheme.Colors.lime : AppTheme.Colors.sky, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(court.name)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.dangerFill)
                            .accessibilityLabel("已收藏")
                    }
                }
                Text("\(distance) · \(court.formattedCourtCount) · ¥\(court.pricePerHour)/时\(court.isEstimatedInfo ? "（估）" : "")")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .lineLimit(1)
                Text(court.operatingHours.isOpen(at: Date()) ? "营业中 · \(court.operatingHours.formattedTimeRange)" : "已打烊 · \(court.operatingHours.formattedTimeRange)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(court.operatingHours.isOpen(at: Date()) ? AppTheme.Colors.success : AppTheme.Colors.inkTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
        .padding(AppTheme.Spacing.md)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md, shadow: AppTheme.Elevation.low)
        .accessibilityElement(children: .combine)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(court.name)
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(court.address)
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkSecondary)
                    }
                    Spacer()
                    IconButton(systemName: locationManager.isFavorite(court.id) ? "heart.fill" : "heart",
                               accessibilityLabel: locationManager.isFavorite(court.id) ? "取消收藏" : "收藏",
                               accent: locationManager.isFavorite(court.id) ? AppTheme.Colors.pink : nil) {
                        Haptics.selection()
                        locationManager.toggleFavorite(court.id)
                    }
                }
                .padding(.top, AppTheme.Spacing.xl)

                HStack(spacing: AppTheme.Spacing.sm) {
                    StatTile(value: court.formattedDistance(from: locationManager.coordinate), label: "距离")
                    StatTile(value: "¥\(court.pricePerHour)", label: court.isEstimatedInfo ? "每小时（估）" : "每小时")
                    StatTile(value: "\(court.courtCount)", label: "场地数")
                }

                VStack(alignment: .leading, spacing: 0) {
                    InfoRow(icon: "clock.fill", tint: AppTheme.Colors.peach,
                            title: court.operatingHours.formattedTimeRange,
                            subtitle: court.operatingHours.formattedDaysOpen + (court.isEstimatedInfo ? " · 营业时间为估算" : ""))
                    if let phone = court.phone {
                        InsetDivider()
                        Button {
                            Task { _ = await MapsLauncher.call(phone) }
                        } label: {
                            InfoRow(icon: "phone.fill", tint: AppTheme.Colors.mint, title: phone, subtitle: "致电球馆预订场地")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)

                if !court.amenities.isEmpty {
                    FlowLayout(spacing: AppTheme.Spacing.sm) {
                        ForEach(court.amenities, id: \.self) { amenity in
                            TagPill(text: amenity.rawValue, icon: amenity.icon, fill: AppTheme.Colors.sky)
                        }
                    }
                }

                let selected = matchManager.draft.courtIds.contains(court.id)
                Button {
                    if !matchManager.draft.toggleCourt(court.id) {
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
        .confirmationDialog("选择导航方式", isPresented: $showNavigation, titleVisibility: .visible) {
            ForEach(MapsLauncher.Provider.allCases) { provider in
                Button(provider.rawValue) {
                    Task {
                        if !(await MapsLauncher.open(court, with: provider)) {
                            appState.showToast("未安装\(provider.rawValue)", style: .error)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 球馆单选（建房间时使用）

struct CourtPickerSheet: View {
    @Binding var selectedId: String?
    var slot: TimeSlot?

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack {
                Text("选择球馆")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") { dismiss() }
            }
            .padding(.top, AppTheme.Spacing.xl)
            CourtsMiniMap(courts: locationManager.nearbyCourts, center: locationManager.coordinate,
                          selectedIds: Set([selectedId].compactMap { $0 }))
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous).strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
            ScrollView {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(locationManager.nearbyCourts) { court in
                        Button {
                            Haptics.selection()
                            selectedId = court.id
                            dismiss()
                        } label: {
                            HStack {
                                CourtRow(court: court, distance: court.formattedDistance(from: locationManager.coordinate),
                                         isFavorite: locationManager.isFavorite(court.id), isSelectedForMatch: selectedId == court.id)
                            }
                            .overlay(alignment: .topTrailing) {
                                if let slot, !court.operatingHours.covers(slot) {
                                    TagPill(text: "该时段未营业", fill: AppTheme.Colors.pink)
                                        .offset(x: -8, y: -8)
                                }
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }
}

// MARK: - 出行范围

struct TravelRadiusSheet: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var radius: Double = UserPreferences.defaultTravelRadius

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("出行范围")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.ink)
                .padding(.top, AppTheme.Spacing.xl)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Int(radius))")
                    .scaledFont(size: 48)
                    .monospacedDigit()
                Text("公里内")
                    .font(AppTheme.Typography.headline)
            }
            .foregroundStyle(AppTheme.Colors.ink)
            Slider(value: $radius, in: UserPreferences.minimumTravelRadius...UserPreferences.maximumTravelRadius, step: 1)
                .tint(AppTheme.Colors.ink)
                .accessibilityLabel("出行范围")
                .accessibilityValue("\(Int(radius)) 公里")
            Text("只显示并匹配这个范围内的球馆和球友")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
            Button("完成") {
                locationManager.updateTravelRadius(radius)
                dismiss()
            }
            .buttonStyle(.brutalPrimary)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear { radius = locationManager.preferences.travelRadiusKm }
    }
}
