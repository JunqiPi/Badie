import StoreKit
import SwiftUI

/// 打赏：三档消耗型内购，不解锁任何功能。价格和收款在 App Store Connect 里设置。
/// 美国区改用 Ko-fi 链接（苹果只允许美国区放外部付款链接），Ko-fi 不抽成
@MainActor
final class TipJar: ObservableObject {
    enum Tier: String, CaseIterable {
        case small = "com.badie.app.tip.small"
        case medium = "com.badie.app.tip.medium"
        case large = "com.badie.app.tip.large"

        var title: String {
            switch self {
            case .small: return String(localized: "一瓶水")
            case .medium: return String(localized: "一杯咖啡")
            case .large: return String(localized: "一场球")
            }
        }

        var icon: String {
            switch self {
            case .small: return "drop.fill"
            case .medium: return "cup.and.saucer.fill"
            case .large: return "figure.badminton"
            }
        }
    }

    @Published private(set) var products: [Tier: Product] = [:]
    @Published private(set) var loadFailed = false
    @Published private(set) var buying: Tier?
    @Published private(set) var usesKofi = false

    func load() async {
        guard products.isEmpty, !usesKofi else { return }
        // 按 App Store 的地区判断，不看手机语言和定位
        if LegalLinks.kofi != nil, await Storefront.current?.countryCode == "USA" {
            usesKofi = true
            return
        }
        do {
            let items = try await Product.products(for: Tier.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: items.compactMap { item in Tier(rawValue: item.id).map { ($0, item) } })
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    /// 付成功返回 true；取消或等家长批准返回 false
    func buy(_ tier: Tier) async throws -> Bool {
        guard let product = products[tier] else { return false }
        buying = tier
        defer { buying = nil }
        guard case .success(let result) = try await product.purchase(), case .verified(let transaction) = result else { return false }
        await transaction.finish()
        return true
    }

    /// 启动时调用：之前没处理完的（比如家长批准后才付的）在这里结束
    nonisolated static func finishPending() {
        Task.detached {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
            }
        }
    }
}

struct TipJarSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var jar = TipJar()
    @State private var thanked = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                Text("支持 Badie")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                IconButton(systemName: "xmark", accessibilityLabel: String(localized: "关闭")) { dismiss() }
            }
            .padding(.top, AppTheme.Spacing.xl)

            if thanked {
                Text("谢谢你。我们会继续把 Badie 做好。")
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(AppTheme.Colors.lime, shadow: .zero)
            } else {
                Text("Badie 免费，没有广告。觉得好用，可以请我们喝点什么。")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if jar.usesKofi, let kofi = LegalLinks.kofi {
                    kofiRow(kofi)
                } else if jar.loadFailed {
                    Text("现在打不开，稍后再试。")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                } else {
                    ForEach(TipJar.Tier.allCases, id: \.self) { tier in row(tier) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.screen)
        .padding(.bottom, AppTheme.Spacing.xl)
        .background(AppTheme.Colors.canvas.ignoresSafeArea())
        .task { await jar.load() }
    }

    private func kofiRow(_ url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: "heart.fill", fill: AppTheme.Colors.butter, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("在 Ko-fi 上打赏")
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                    Text("用银行卡付，金额随意。")
                        .font(AppTheme.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.inkSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inkTertiary)
            }
            .padding(AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md)
        }
        .buttonStyle(PressableStyle())
    }

    private func row(_ tier: TipJar.Tier) -> some View {
        Button {
            Task {
                do {
                    if try await jar.buy(tier) { withAnimation(AppTheme.Motion.standard) { thanked = true } }
                } catch {
                    appState.showError(error)
                }
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                IconTile(systemName: tier.icon, fill: AppTheme.Colors.butter, size: 40)
                Text(tier.title)
                    .font(AppTheme.Typography.bodyBold)
                    .foregroundStyle(AppTheme.Colors.ink)
                Spacer()
                if jar.buying == tier {
                    ProgressView()
                } else if let product = jar.products[tier] {
                    Text(product.displayPrice)
                        .font(AppTheme.Typography.bodyBold)
                        .foregroundStyle(AppTheme.Colors.ink)
                } else {
                    ProgressView()
                }
            }
            .padding(AppTheme.Spacing.md)
            .sticker(AppTheme.Colors.surface, radius: AppTheme.Radius.md)
        }
        .buttonStyle(PressableStyle())
        .disabled(jar.buying != nil || jar.products[tier] == nil)
    }
}
