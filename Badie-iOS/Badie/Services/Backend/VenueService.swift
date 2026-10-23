import Foundation

// MARK: - 球馆服务接口
//
// 界面只通过这个接口使用球馆库，模拟后端（MockBackend）和以后的正式后端（Supabase）都实现它。
// - 读取是同步的：正式后端从本地缓存返回，后台再刷新
// - 写入是异步的：正式后端要走网络（模拟后端的同步实现也满足这些要求）
// 服务端对应：supabase/migrations 里的 add_venue / confirm_venue / report_venue / venues_near

@MainActor
protocol VenueService: AnyObject {
    /// 球馆库（不含已合并的旧条目）
    var allVenues: [BadmintonCourt] { get }
    /// 按 ID 取球馆；已合并的旧 ID 跳到保留的那一家
    func venue(id: String) -> BadmintonCourt?
    /// 半径内的球馆，按距离排序
    func venues(near center: Coordinate, radiusKm: Double) -> [BadmintonCourt]
    func nearestVenues(to center: Coordinate, count: Int) -> [BadmintonCourt]
    /// 搜索范围：球馆库里没被暂时下架的（被两人以上报告、等待人工核实的不出现，添加者本人仍能看到）
    var searchableVenues: [BadmintonCourt] { get }
    /// 添加前查重（Place ID 相同 / 200 米内名称相近 / 同一栋楼）
    func duplicates(for candidate: VenueCandidate) -> [VenueSearch.Duplicate]
    func hasConfirmed(_ id: String) -> Bool
    /// 把这里设为常去球馆的人数
    func regularsCount(for venueId: String) -> Int

    @discardableResult
    func addVenue(_ candidate: VenueCandidate, source: VenueSource, aliases: [String], courtCount: Int?,
                  entranceNote: String?, now: Date) async throws -> BadmintonCourt
    func confirmVenue(_ id: String) async throws
    func reportVenue(_ id: String, issue: VenueIssue, detail: String) async throws
}

extension MockBackend: VenueService {}
