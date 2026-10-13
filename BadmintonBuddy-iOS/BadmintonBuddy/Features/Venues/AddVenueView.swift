import SwiftUI
import MapKit

/// 手动添加球馆：移动地图让图钉对准入口 → 自动识别地址（可改）→ 填名称 → 查重 → 加入。
/// 也可以搜地址跳转，或粘贴 Google / Apple 地图链接。
struct AddVenueView: View {
    var initialName = ""
    var initialCoordinate: Coordinate
    /// 演示/截图用：预填地址，不做反向地理编码
    var initialAddress: PostalAddress?
    /// 演示/截图用：打开即检查附近是否已有同一家
    var checksDuplicatesOnAppear = false
    let onAdded: (BadmintonCourt) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var addressSearch = AppleMapsSearch(addressesOnly: true)
    @State private var position: MapCameraPosition = .automatic
    @State private var pin: Coordinate
    @State private var address: PostalAddress?
    @State private var timeZoneId: String?
    @State private var isGeocoding = false
    @State private var editsAddress = false
    @State private var addressQuery = ""

    @State private var name = ""
    @State private var alias = ""
    @State private var unit = ""
    @State private var entranceNote = ""
    @State private var courtCount = 0

    @State private var street = ""
    @State private var city = ""
    @State private var region = ""
    @State private var postalCode = ""

    @State private var duplicates: [VenueSearch.Duplicate] = []
    @State private var checkedDuplicates = false
    @State private var geocodeTask: Task<Void, Never>?

    init(initialName: String = "", initialCoordinate: Coordinate, initialAddress: PostalAddress? = nil,
         checksDuplicatesOnAppear: Bool = false, onAdded: @escaping (BadmintonCourt) -> Void) {
        self.initialName = initialName
        self.initialCoordinate = initialCoordinate
        self.initialAddress = initialAddress
        self.checksDuplicatesOnAppear = checksDuplicatesOnAppear
        self.onAdded = onAdded
        _pin = State(initialValue: initialCoordinate)
        _position = State(initialValue: .region(MKCoordinateRegion(center: initialCoordinate.clCoordinate,
                                                                    latitudinalMeters: 600, longitudinalMeters: 600)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加球馆")
                        .font(AppTheme.Typography.title)
                        .foregroundStyle(AppTheme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("放好图钉、核对地址，其他球友才能找到同一个地方")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: "关闭") { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    locateSection
                    addressCard
                    detailsSection
                    if !duplicates.isEmpty {
                        DuplicateChoiceList(duplicates: duplicates) { venue in
                            onAdded(venue)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .onAppear {
            if name.isEmpty { name = initialName }
            if let initialAddress {
                apply(initialAddress)
            } else {
                scheduleGeocode()
            }
            if checksDuplicatesOnAppear, let finalAddress = composedAddress {
                let candidate = VenueCandidate(name: trimmedName, location: pin, address: finalAddress)
                duplicates = appState.backend.duplicates(for: candidate)
                checkedDuplicates = true
            }
        }
        .onChange(of: addressQuery) { _, value in
            if locationManager.allowsMapSearch {
                addressSearch.update(query: value, near: pin, radiusKm: 80)
            }
        }
    }

    // MARK: Locate

    private var locateSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                SearchField(text: $addressQuery, placeholder: "搜索地址，快速移动图钉")
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in await applyPastedLink(text) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(AppTheme.Colors.ink)
            }
            if !addressSearch.completions.isEmpty && !addressQuery.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(addressSearch.completions.prefix(5).enumerated()), id: \.offset) { index, completion in
                        if index > 0 { InsetDivider() }
                        Button {
                            jump(to: completion)
                        } label: {
                            MapResultRow(title: completion.title, subtitle: completion.subtitle, query: addressQuery)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
            }
            ZStack {
                Map(position: $position) {
                    UserAnnotation()
                }
                .mapStyle(.standard(pointsOfInterest: .including([.parking, .publicTransport, .school, .park])))
                .onMapCameraChange(frequency: .onEnd) { context in
                    let center = Coordinate(context.region.center)
                    guard center.distanceKm(to: pin) > 0.003 else { return }
                    pin = center
                    checkedDuplicates = false
                    duplicates = []
                    scheduleGeocode()
                }
                // 固定在地图中心的图钉
                Image(systemName: "mappin")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(AppTheme.Colors.dangerFill)
                    .shadow(color: AppTheme.Colors.shadow.opacity(0.35), radius: 0, x: 2, y: 2)
                    .offset(y: -17)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .strokeBorder(AppTheme.Colors.stroke, lineWidth: 2))
            .accessibilityLabel("地图，移动地图让图钉对准球馆入口")
            Text("移动地图，让图钉对准球馆入口（工业区、学校里的场馆尤其要对准）")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.inkTertiary)
        }
    }

    // MARK: Address

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("图钉处的地址")
                    .font(AppTheme.Typography.footnoteBold)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                Spacer()
                Button(editsAddress ? "收起" : "地址不对？修改") {
                    withAnimation(AppTheme.Motion.standard) { editsAddress.toggle() }
                }
                .buttonStyle(TextActionStyle())
            }
            if isGeocoding {
                HStack(spacing: AppTheme.Spacing.sm) {
                    LoadingDots()
                    Text("正在识别地址…")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
            } else if let current = composedAddress, current.isComplete {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.streetLine)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text(current.cityLine)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("没识别到街道地址，请移动图钉或点“修改”手动填写")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            if editsAddress {
                VStack(spacing: AppTheme.Spacing.md) {
                    BrutalTextField(label: "街道门牌", placeholder: "例：10410 Valley Blvd", text: $street)
                    HStack(spacing: AppTheme.Spacing.md) {
                        BrutalTextField(label: "城市", placeholder: "例：El Monte", text: $city)
                        BrutalTextField(label: "州/省", placeholder: "CA", text: $region)
                            .frame(maxWidth: 110)
                    }
                    BrutalTextField(label: "邮编", placeholder: "91731", text: $postalCode, keyboard: .numbersAndPunctuation)
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)
    }

    // MARK: Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            BrutalTextField(label: "球馆名称", placeholder: "例：Los Angeles Badminton Club", text: $name, characterLimit: 60)
            BrutalTextField(label: "常用简称（选填）", placeholder: "例：LABC、洛羽", text: $alias, characterLimit: 20)
            BrutalTextField(label: "单元/楼层（选填）", placeholder: "例：Unit B、2F", text: $unit, characterLimit: 20)
            BrutalTextField(label: "入口说明（选填）", placeholder: "例：从后门进，停车场在侧面", text: $entranceNote, characterLimit: 80)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("场地数（选填）")
                        .font(AppTheme.Typography.footnoteBold)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                    Text(courtCount == 0 ? "不确定" : "\(courtCount) 片")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                }
                Spacer()
                Stepper("场地数", value: $courtCount, in: 0...40)
                    .labelsHidden()
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                submit()
            } label: {
                Text(checkedDuplicates && !duplicates.isEmpty ? "都不是，添加为新球馆" : "检查并添加")
            }
            .buttonStyle(.brutalPrimary)
            .disabled(!canSubmit)
            if let hint = submitHint {
                Text(hint)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InsetDivider() }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        (2...60).contains(trimmedName.count) && (composedAddress?.isComplete ?? false) && !isGeocoding
    }

    private var submitHint: String? {
        if trimmedName.count < 2 { return "填写球馆名称" }
        if !(composedAddress?.isComplete ?? false) { return "需要街道和城市，方便别人确认位置" }
        return nil
    }

    /// 识别结果 + 手动修改后的地址
    private var composedAddress: PostalAddress? {
        let country = address?.countryCode ?? CountryInfo.deviceCountry.code
        guard !street.isEmpty || !city.isEmpty else { return address }
        return PostalAddress(street: street, unit: unit, city: city, region: region, postalCode: postalCode, countryCode: country)
    }

    // MARK: Actions

    private func apply(_ resolved: PostalAddress) {
        address = resolved
        street = resolved.street
        city = resolved.city
        region = resolved.region
        postalCode = resolved.postalCode
    }

    private func scheduleGeocode() {
        guard locationManager.allowsMapSearch else { return }
        geocodeTask?.cancel()
        let target = pin
        isGeocoding = true
        geocodeTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let result = await AppleMapsSearch.reverseGeocode(target)
            guard !Task.isCancelled else { return }
            isGeocoding = false
            if let result {
                apply(result.address)
                timeZoneId = result.timeZoneId
            } else {
                address = nil
                street = ""; city = ""; region = ""; postalCode = ""
            }
        }
    }

    private func move(to coordinate: Coordinate) {
        pin = coordinate
        withAnimation(AppTheme.Motion.standard) {
            position = .region(MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 400, longitudinalMeters: 400))
        }
    }

    private func jump(to completion: MKLocalSearchCompletion) {
        Task {
            guard let candidate = try? await addressSearch.resolve(completion) else {
                appState.showToast("没找到这个地址", style: .error)
                return
            }
            addressQuery = ""
            addressSearch.clear()
            move(to: candidate.location)
            apply(candidate.address)
            timeZoneId = candidate.timeZoneId
        }
    }

    private func applyPastedLink(_ text: String) async {
        guard var url = MapLinkParser.firstMapURL(in: text) else {
            addressQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        if MapLinkParser.needsExpansion(url), let expanded = await AppleMapsSearch.expand(url) {
            url = expanded
        }
        guard let link = MapLinkParser.parse(url) else {
            appState.showToast("没能识别这个地图链接", style: .error)
            return
        }
        if let linkName = link.name, trimmedName.isEmpty { name = linkName }
        if let coordinate = link.coordinate {
            move(to: coordinate)
            scheduleGeocode()
        } else if let query = link.query ?? link.name {
            addressQuery = query
        }
    }

    private func submit() {
        guard let finalAddress = composedAddress else { return }
        let candidate = VenueCandidate(name: trimmedName, location: pin, address: finalAddress,
                                       applePlaceId: nil, timeZoneId: timeZoneId ?? TimeZone.current.identifier)
        if !checkedDuplicates {
            checkedDuplicates = true
            duplicates = appState.backend.duplicates(for: candidate)
            if !duplicates.isEmpty {
                Haptics.error()
                return
            }
        }
        do {
            let venue = try appState.backend.addVenue(candidate, source: .player, aliases: [alias],
                                                      courtCount: courtCount > 0 ? courtCount : nil,
                                                      entranceNote: entranceNote)
            Haptics.success()
            appState.showToast("已添加：\(venue.name)，等球友确认", style: .success)
            onAdded(venue)
        } catch {
            appState.showError(error)
        }
    }
}
