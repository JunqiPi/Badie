import SwiftUI
import MapKit

/// 选择球馆：一个搜索框，结果分两层——平台球馆库在前，Apple 地图在后；
/// 没输入时先给“已选 / 常去 / 附近”。地图结果选中后先查重、看地图核对，再加入球馆库。
/// 每一行都带地址，用户能确认“是不是这一家”。
struct VenuePickerView: View {
    enum Mode: Equatable {
        /// 快速匹配：最多选 N 个
        case multiple(max: Int)
        /// 建房间：选 1 个，选完关闭
        case single
        /// 浏览：点开详情
        case browse
    }

    let mode: Mode
    @Binding var selection: [String]
    var slot: TimeSlot?
    var initialQuery = ""
    /// 未登录（注册流程中）时只能从球馆库里选，不能新增
    var allowsAdding = true
    var onOpen: ((BadmintonCourt) -> Void)?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var mapSearch = AppleMapsSearch()
    @State private var query = ""
    @State private var hits: [VenueSearch.Hit] = []
    @State private var resolvingId: String?
    @State private var pendingCandidate: PendingCandidate?
    @State private var addDraft: AddVenueDraft?
    @State private var suggestions: [VenueCandidate] = []
    @State private var detailVenue: BadmintonCourt?
    @State private var didAppear = false
    @FocusState private var searchFocused: Bool

    private var backend: MockBackend { appState.backend }
    /// 正式后端只能选已收录的球馆：本机添加的球馆服务器上没有
    private var canAdd: Bool { allowsAdding && !appState.isRemote }
    private var venueService: any VenueService { appState.venueService }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.sm)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        idleContent
                    } else {
                        searchContent
                    }
                    if canAdd {
                        addVenueFooter
                    } else {
                        Text(appState.isRemote ? String(localized: "没找到？目前只能选已收录的球馆。")
                                               : String(localized: "没找到？注册完成后可以在“附近球馆”里添加。"))
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            query = initialQuery
            runSearch()
            loadSuggestionsIfNeeded()
        }
        .onChange(of: query) { _, _ in runSearch() }
        .sheet(item: $pendingCandidate) { pending in
            VenueCandidateSheet(candidate: pending.candidate, duplicates: pending.duplicates,
                                source: pending.source) { venue in
                pendingCandidate = nil
                choose(venue)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailVenue) { venue in
            CourtDetailSheet(court: venue)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $addDraft) { draft in
            AddVenueView(initialName: draft.name, initialCoordinate: draft.coordinate) { venue in
                addDraft = nil
                choose(venue)
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                if case .multiple(let max) = mode {
                    Text("已选 \(selection.count)/\(max) · 选同一个球馆的人才会被匹配到一起")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            }
            Spacer()
            if case .multiple = mode {
                Button("完成") { dismiss() }
                    .buttonStyle(BrutalButtonStyle(kind: .primary, size: .small, fullWidth: false))
            } else {
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.top, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.md)
    }

    private var title: String {
        switch mode {
        case .multiple, .single: return String(localized: "选择球馆")
        case .browse: return String(localized: "搜索球馆")
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                TextField("球馆名、简称（如 LABC）或地址", text: $query)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.Colors.inkTertiary)
                    }
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 48)
            .sticker(AppTheme.Colors.surface, radius: 14, shadow: searchFocused ? AppTheme.Elevation.low : .zero)
            if canAdd {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in await handlePastedLink(text) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(AppTheme.Colors.ink)
                .accessibilityLabel("粘贴地图链接")
            }
        }
    }

    // MARK: Idle (no query)

    @ViewBuilder
    private var idleContent: some View {
        let selected = locationManager.courts(ids: selection)
        if case .multiple = mode, !selected.isEmpty {
            section(String(localized: "已选"), detail: nil, venues: selected)
        }
        let favorites = locationManager.favoriteCourts.filter { !selection.contains($0.id) || mode == .browse }
        if !favorites.isEmpty {
            section(String(localized: "常去"), detail: nil, venues: favorites)
        }
        let shown = Set(selected.map(\.id) + favorites.map(\.id))
        let nearby = locationManager.nearbyCourts.filter { !shown.contains($0.id) }
        if !nearby.isEmpty {
            section(String(localized: "附近"), detail: locationManager.radiusText, venues: nearby)
        } else if favorites.isEmpty {
            NoticeBanner(icon: "mappin.slash",
                         text: String(localized: "\(locationManager.radiusText)还没有收录的球馆。搜索名称或地址，或从下面 Apple 地图的结果里选。"))
        }
        if canAdd && !suggestions.isEmpty {
            mapSection(title: String(localized: "Apple 地图上的附近结果"),
                       rows: suggestions.map { MapRowItem(id: $0.id, title: $0.name, subtitle: $0.address.compactLine) }) { id in
                if let candidate = suggestions.first(where: { $0.id == id }) { review(candidate, source: .appleMaps) }
            }
        }
    }

    // MARK: Search results

    @ViewBuilder
    private var searchContent: some View {
        if hits.isEmpty && visibleCompletions.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: String(localized: "没有找到“\(query)”"),
                           message: String(localized: "试试球馆的英文名、简称或街道地址；也可以粘贴 Google / Apple 地图链接。"))
        }
        if !hits.isEmpty {
            section(String(localized: "Badie 球馆库"), detail: String(localized: "\(hits.count) 个"), venues: hits.map(\.venue))
        }
        if canAdd && !visibleCompletions.isEmpty {
            mapSection(title: String(localized: "Apple 地图"),
                       rows: visibleCompletions.map { MapRowItem(id: completionId($0), title: $0.title, subtitle: $0.subtitle) }) { id in
                if let completion = visibleCompletions.first(where: { completionId($0) == id }) { resolve(completion) }
            }
        }
    }

    /// 去掉与球馆库结果同名的地图联想，避免同一家出现两次
    private var visibleCompletions: [MKLocalSearchCompletion] {
        let names = hits.map(\.venue.name)
        return mapSearch.completions
            .filter { completion in !names.contains { VenueSearch.nameSimilarity($0, completion.title) >= 0.8 } }
            .prefix(6)
            .map { $0 }
    }

    private func completionId(_ completion: MKLocalSearchCompletion) -> String {
        completion.title + "|" + completion.subtitle
    }

    // MARK: Sections

    private func section(_ title: String, detail: String?, venues: [BadmintonCourt]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: title, detail: detail)
            VStack(spacing: 0) {
                ForEach(Array(venues.enumerated()), id: \.element.id) { index, venue in
                    if index > 0 { InsetDivider() }
                    Button {
                        tap(venue)
                    } label: {
                        VenueRow(
                            venue: venue,
                            distance: venue.formattedDistance(from: locationManager.coordinate),
                            regulars: venueService.regularsCount(for: venue.id),
                            isFavorite: locationManager.isFavorite(venue.id),
                            query: query,
                            accessory: accessory(for: venue),
                            isClosedForSlot: slot.map { !venue.isOpen(for: $0) } ?? false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(venue.id) ? [.isSelected, .isButton] : .isButton)
                    .contextMenu {
                        Button {
                            showDetail(venue)
                        } label: {
                            Label("查看详情与地图", systemImage: "map")
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
        }
    }

    private func mapSection(title: String, rows: [MapRowItem], onTap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(title: title, detail: String(localized: "选中后核对位置"))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { InsetDivider() }
                    Button {
                        onTap(row.id)
                    } label: {
                        MapResultRow(title: row.title, subtitle: row.subtitle, query: query,
                                     isLoading: resolvingId == row.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(resolvingId != nil)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surfaceMuted, radius: AppTheme.Radius.lg, shadow: .zero)
        }
    }

    private var addVenueFooter: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("找不到你常去的球馆？")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.ink)
            Text("放个图钉、核对地址就能添加。添加后其他球友也能搜到，3 位球友确认后显示“球友确认”。")
                .font(AppTheme.Typography.footnote)
                .foregroundStyle(AppTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                addDraft = AddVenueDraft(name: query.trimmingCharacters(in: .whitespaces), coordinate: locationManager.coordinate)
            } label: {
                Label("添加球馆", systemImage: "plus.circle.fill")
            }
            .buttonStyle(BrutalButtonStyle(kind: .secondary, size: .medium, fullWidth: true))
        }
        .padding(.top, AppTheme.Spacing.sm)
    }

    private func accessory(for venue: BadmintonCourt) -> VenueRow.Accessory {
        switch mode {
        case .multiple: return .checkbox(isOn: selection.contains(venue.id))
        case .single: return .radio(isOn: selection.contains(venue.id))
        case .browse: return .chevron
        }
    }

    // MARK: Actions

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            hits = []
            mapSearch.clear()
            return
        }
        hits = venueService.searchVenues(trimmed, near: locationManager.coordinate, limit: 15)
        if locationManager.allowsMapSearch && canAdd {
            mapSearch.update(query: trimmed, near: locationManager.coordinate)
        }
    }

    /// 出行范围内收录太少时，用 Apple 地图找附近的羽毛球场地作为建议（不会自动入库）
    private func loadSuggestionsIfNeeded() {
        guard canAdd, locationManager.allowsMapSearch, locationManager.nearbyCourts.count < 3 else { return }
        let center = locationManager.coordinate
        Task {
            let found = await AppleMapsSearch.searchBadmintonVenues(near: center, countryCode: backend.currentCountryCode)
            let known = venueService.allVenues
            suggestions = found.filter { candidate in
                !VenueSearch.duplicates(name: candidate.name, location: candidate.location,
                                        applePlaceId: candidate.applePlaceId,
                                        alternatePlaceIds: candidate.alternatePlaceIds, in: known)
                    .contains { $0.kind != .sameBuilding }
            }
        }
    }

    private func tap(_ venue: BadmintonCourt) {
        switch mode {
        case .browse:
            showDetail(venue)
        default:
            choose(venue)
        }
    }

    private func showDetail(_ venue: BadmintonCourt) {
        if let onOpen {
            onOpen(venue)
        } else {
            detailVenue = venue
        }
    }

    private func choose(_ venue: BadmintonCourt) {
        Haptics.selection()
        switch mode {
        case .multiple(let max):
            if let index = selection.firstIndex(of: venue.id) {
                selection.remove(at: index)
            } else if selection.count < max {
                selection.append(venue.id)
            } else {
                appState.showToast(String(localized: "最多选择 \(max) 个球馆，先取消一个"))
            }
        case .single:
            selection = [venue.id]
            dismiss()
        case .browse:
            showDetail(venue)
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        let id = completionId(completion)
        resolvingId = id
        Task {
            defer { resolvingId = nil }
            do {
                let candidate = try await mapSearch.resolve(completion)
                review(candidate, source: .appleMaps)
            } catch {
                appState.showToast(String(localized: "暂时无法获取这个地点，请稍后再试"), style: .error)
            }
        }
    }

    /// 地图地点 → 查重 → Place ID 相同直接选已有球馆，否则打开核对页
    private func review(_ candidate: VenueCandidate, source: VenueSource) {
        let duplicates = venueService.duplicates(for: candidate)
        if let same = duplicates.first(where: { $0.kind == .samePlace }) {
            appState.showToast(String(localized: "球馆库里已有：\(same.venue.name)"), style: .success)
            choose(same.venue)
            return
        }
        pendingCandidate = PendingCandidate(candidate: candidate, duplicates: duplicates, source: source)
    }

    /// 粘贴 Google / Apple 地图链接
    private func handlePastedLink(_ text: String) async {
        guard var url = MapLinkParser.firstMapURL(in: text) else {
            // 不是链接：当作搜索词
            query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        if MapLinkParser.needsExpansion(url) {
            guard let expanded = await AppleMapsSearch.expand(url) else {
                appState.showToast(String(localized: "链接打不开，试试直接搜索名称"), style: .error)
                return
            }
            url = expanded
        }
        guard let link = MapLinkParser.parse(url) else {
            appState.showToast(String(localized: "没能识别这个地图链接，试试直接搜索名称"), style: .error)
            return
        }
        if let placeId = link.applePlaceId, let item = await AppleMapsSearch.mapItem(placeId: placeId) {
            review(VenueCandidate(mapItem: item), source: .appleMaps)
            return
        }
        let center = link.coordinate ?? locationManager.coordinate
        if let name = link.name ?? link.query,
           let match = await AppleMapsSearch.search(name, near: center, radiusKm: 5, limit: 3)
            .min(by: { $0.location.distanceKm(to: center) < $1.location.distanceKm(to: center) }),
           link.coordinate == nil || match.location.distanceKm(to: center) < 0.3 {
            review(match, source: .appleMaps)
            return
        }
        if let coordinate = link.coordinate {
            // 只有坐标：带着坐标和名称去“添加球馆”，由用户核对地址
            addDraft = AddVenueDraft(name: link.name ?? "", coordinate: coordinate)
            return
        }
        appState.showToast(String(localized: "没能定位这个链接，试试直接搜索名称"), style: .error)
    }
}

// MARK: - Helpers

private struct MapRowItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

private struct PendingCandidate: Identifiable {
    let candidate: VenueCandidate
    let duplicates: [VenueSearch.Duplicate]
    let source: VenueSource
    var id: String { candidate.id }
}

struct AddVenueDraft: Identifiable {
    let id = UUID()
    var name: String
    var coordinate: Coordinate
}
