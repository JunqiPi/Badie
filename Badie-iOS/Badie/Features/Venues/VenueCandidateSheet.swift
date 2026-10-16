import SwiftUI

/// 核对位置：地图结果或粘贴链接得到的地点，在加入球馆库前先看地图和完整地址，
/// 并检查附近是否已有同一家（“是这个”直接选已有球馆）。
struct VenueCandidateSheet: View {
    let candidate: VenueCandidate
    let duplicates: [VenueSearch.Duplicate]
    let source: VenueSource
    let onChosen: (BadmintonCourt) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var alias = ""
    @State private var entranceNote = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("核对位置")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.top, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    // 查重结果放在最上面：已有同一家时，先看到它
                    if !duplicates.isEmpty {
                        DuplicateChoiceList(duplicates: duplicates, onChoose: onChosen)
                    }
                    VenueMapPreview(name: candidate.name, coordinate: candidate.location, height: 200, interactive: true)
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(candidate.name)
                            .font(AppTheme.Typography.title2)
                            .foregroundStyle(AppTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        VenueAddressBlock(address: candidate.address)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            TagPill(text: String(localized: "距你 \(DistanceFormatter.string(km: candidate.location.distanceKm(to: locationManager.coordinate)))"),
                                    icon: "location.fill", fill: AppTheme.Colors.sky)
                            TagPill(text: String(localized: "来自 Apple 地图"), icon: "map.fill", fill: AppTheme.Colors.surfaceMuted,
                                    foreground: AppTheme.Colors.ink)
                        }
                        if let phone = candidate.phone {
                            Label(phone, systemImage: "phone.fill")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.inkSecondary)
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                    .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.lg, shadow: .zero)

                    if !candidate.address.isComplete {
                        NoticeBanner(icon: "exclamationmark.triangle.fill",
                                     text: String(localized: "这个地点缺少街道地址，别人很难确认位置。请改用“添加球馆”放图钉并补全地址。"))
                    }

                    BrutalTextField(label: String(localized: "常用简称（选填）"), placeholder: String(localized: "例：LABC、洛羽"), text: $alias, characterLimit: 20)
                    BrutalTextField(label: String(localized: "入口说明（选填）"), placeholder: String(localized: "例：工业区里，从后门进，2 楼"), text: $entranceNote,
                                    characterLimit: 80)
                }
                .padding(.horizontal, AppTheme.Spacing.screen)
                .padding(.bottom, AppTheme.Spacing.xl)
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    save()
                } label: {
                    if isSaving {
                        LoadingDots()
                    } else if isBlocked {
                        Text("请选择上面已有的球馆")
                    } else {
                        Text(duplicates.isEmpty ? String(localized: "就是这里，加入并选择") : String(localized: "都不是，加入为新球馆"))
                    }
                }
                .buttonStyle(.brutalPrimary)
                .disabled(isSaving || isBlocked || !candidate.address.isComplete)
                Text("加入后显示“待确认”，3 位球友确认（或在这里签到打球）后显示“球友确认”。")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.screen)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.Colors.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { InsetDivider() }
        }
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
    }

    private var isBlocked: Bool { duplicates.contains { $0.kind.blocksAdding } }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let venue = try await appState.venueService.addVenue(candidate, source: source, aliases: [alias],
                                                                     courtCount: nil, entranceNote: entranceNote, now: Date())
                Haptics.success()
                appState.showToast(String(localized: "已加入球馆库：\(venue.name)"), style: .success)
                onChosen(venue)
            } catch {
                appState.showError(error)
            }
        }
    }
}
