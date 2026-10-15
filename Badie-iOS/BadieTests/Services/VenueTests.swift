import XCTest
@testable import Badie

/// 球馆：地址格式、搜索（别名/缩写/拼音/地址）、查重、地图链接解析、国家与手机号
final class VenueTests: XCTestCase {

    private let la = Coordinate(latitude: 34.0686, longitude: -118.0276)

    private func venue(_ id: String, _ name: String, aliases: [String] = [], at location: Coordinate,
                       street: String = "1 Main St", city: String = "El Monte", placeId: String? = nil,
                       status: VenueStatus = .verified) -> BadmintonCourt {
        BadmintonCourt(id: id, name: name, aliases: aliases, location: location,
                       address: PostalAddress(street: street, city: city, region: "CA", postalCode: "91731", countryCode: "US"),
                       timeZoneId: "America/Los_Angeles", applePlaceId: placeId, status: status)
    }

    // MARK: Address

    func testUSAddressFormatting() {
        let address = PostalAddress(street: "4800 Rivergrade Rd", unit: "Unit B", city: "Baldwin Park",
                                    region: "CA", postalCode: "91706", countryCode: "us")
        XCTAssertEqual(address.streetLine, "4800 Rivergrade Rd, Unit B")
        XCTAssertEqual(address.cityLine, "Baldwin Park, CA 91706")
        XCTAssertEqual(address.compactLine, "4800 Rivergrade Rd, Unit B, Baldwin Park, CA")
        XCTAssertEqual(address.singleLine, "4800 Rivergrade Rd, Unit B, Baldwin Park, CA 91706")
        XCTAssertEqual(address.countryCode, "US")
        XCTAssertTrue(address.isComplete)
    }

    func testChineseAddressIsLargeToSmall() {
        let address = PostalAddress(street: "工体北路4号", city: "朝阳区", region: "北京市", countryCode: "CN")
        XCTAssertEqual(address.singleLine, "北京市朝阳区工体北路4号")
        XCTAssertEqual(address.compactLine, "朝阳区工体北路4号")
    }

    func testIncompleteAddressIsRejected() {
        XCTAssertFalse(PostalAddress(street: "", city: "El Monte", region: "CA", countryCode: "US").isComplete)
    }

    // MARK: Curated data

    func testCuratedVenuesAreWellFormed() throws {
        let all = BadmintonCourt.curated
        XCTAssertGreaterThanOrEqual(BadmintonCourt.curatedUS.count, 30)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "球馆 ID 必须唯一")
        for venue in all {
            XCTAssertTrue(venue.postalAddress.isComplete, "\(venue.name) 地址不完整")
            let zone = try XCTUnwrap(venue.timeZoneId, venue.name)
            XCTAssertNotNil(TimeZone(identifier: zone), venue.name)
            XCTAssertTrue((-90...90).contains(venue.location.latitude) && (-180...180).contains(venue.location.longitude))
        }
        for venue in BadmintonCourt.curatedUS {
            XCTAssertEqual(venue.currencyCode, "USD")
            XCTAssertTrue((24...50).contains(venue.location.latitude), "\(venue.name) 坐标不在美国本土")
            XCTAssertTrue((-125...(-66)).contains(venue.location.longitude), "\(venue.name) 坐标不在美国本土")
        }
    }

    func testCuratedVenuesAreNotDuplicatesOfEachOther() {
        let all = BadmintonCourt.curated
        for venue in all {
            let others = all.filter { $0.id != venue.id }
            let dupes = VenueSearch.duplicates(name: venue.name, location: venue.location, applePlaceId: nil, in: others)
            XCTAssertTrue(dupes.isEmpty, "\(venue.name) 被误判为与 \(dupes.map(\.venue.name)) 重复")
        }
    }

    func testFindsLABCAndEliteRallyFromLA() {
        let la = Coordinate.fallbackCenter
        XCTAssertEqual(VenueSearch.search(BadmintonCourt.curated, query: "LABC", near: la).first?.venue.id, "v-us-ca-labc")
        XCTAssertEqual(VenueSearch.search(BadmintonCourt.curated, query: "elite rally", near: la).first?.venue.id, "v-us-ca-elite-rally")
        XCTAssertEqual(VenueSearch.search(BadmintonCourt.curated, query: "洛杉矶羽毛球", near: la).first?.venue.id, "v-us-ca-labc")
        // 同名“Elite”的湾区球馆排在后面
        let elite = VenueSearch.search(BadmintonCourt.curated, query: "elite", near: la).map(\.venue.id)
        XCTAssertEqual(elite.first, "v-us-ca-elite-rally")
    }

    // MARK: Search

    func testAcronymAndAliasSearch() {
        let labc = venue("labc", "Los Angeles Badminton Club", aliases: ["洛杉矶羽毛球俱乐部"], at: la)
        let other = venue("other", "Arena Badminton", at: la.offsetBy(eastKm: 2, northKm: 0))
        XCTAssertEqual(VenueSearch.acronym("Los Angeles Badminton Club"), "labc")
        XCTAssertEqual(VenueSearch.search([other, labc], query: "LABC", near: la).first?.venue.id, "labc")
        XCTAssertEqual(VenueSearch.search([other, labc], query: "洛杉矶", near: la).first?.venue.id, "labc")
        XCTAssertEqual(VenueSearch.search([other, labc], query: "angeles bad", near: la).first?.venue.id, "labc")
    }

    func testAddressAndZipSearch() {
        let elite = venue("elite", "Elite Rally Badminton Club", at: la, street: "4800 Rivergrade Rd", city: "Baldwin Park")
        XCTAssertEqual(VenueSearch.search([elite], query: "rivergrade", near: la).first?.venue.id, "elite")
        XCTAssertEqual(VenueSearch.search([elite], query: "91731", near: la).first?.venue.id, "elite")
        XCTAssertTrue(VenueSearch.search([elite], query: "pickleball", near: la).isEmpty)
    }

    func testPinyinSearchForChineseNames() {
        // “海淀”读音唯一，避免多音字（如“朝”）影响断言
        XCTAssertEqual(VenueSearch.search(BadmintonCourt.curatedBeijing, query: "hdym", near: .beijing).first?.venue.id,
                       "v-cn-bj-haidian")
        XCTAssertEqual(VenueSearch.search(BadmintonCourt.curatedBeijing, query: "haidian", near: .beijing).first?.venue.id,
                       "v-cn-bj-haidian")
    }

    func testCloserVenueRanksFirstForEqualMatches() {
        let near = venue("near", "Badminton Center", at: la.offsetBy(eastKm: 1, northKm: 0))
        let far = venue("far", "Badminton Center", at: la.offsetBy(eastKm: 60, northKm: 0))
        XCTAssertEqual(VenueSearch.search([far, near], query: "badminton center", near: la).map(\.venue.id), ["near", "far"])
    }

    // MARK: Duplicates

    func testDuplicateDetection() {
        let labc = venue("labc", "Los Angeles Badminton Club", aliases: ["LABC"], at: la, placeId: "I123")
        let unitB = venue("unitb", "Rally Point", at: la.offsetBy(eastKm: 0.02, northKm: 0))
        let pool = [labc, unitB]

        let samePlace = VenueSearch.duplicates(name: "Totally different", location: la.offsetBy(eastKm: 3, northKm: 0),
                                               applePlaceId: "I123", in: pool)
        XCTAssertEqual(samePlace.first?.kind, .samePlace)

        let likely = VenueSearch.duplicates(name: "LA Badminton Club", location: la.offsetBy(eastKm: 0.1, northKm: 0),
                                            applePlaceId: nil, in: pool)
        XCTAssertEqual(likely.first?.venue.id, "labc")
        XCTAssertEqual(likely.first?.kind, .likely)

        let acronym = VenueSearch.duplicates(name: "LABC", location: la.offsetBy(eastKm: 0.15, northKm: 0),
                                             applePlaceId: nil, in: [labc])
        XCTAssertEqual(acronym.first?.kind, .likely, "简称与全称视为同一家")

        let sameBuilding = VenueSearch.duplicates(name: "Shuttle House", location: la.offsetBy(eastKm: 0.02, northKm: 0),
                                                  applePlaceId: nil, in: [unitB])
        XCTAssertEqual(sameBuilding.first?.kind, .sameBuilding)

        let distinct = VenueSearch.duplicates(name: "Shuttle House", location: la.offsetBy(eastKm: 1, northKm: 0),
                                              applePlaceId: nil, in: pool)
        XCTAssertTrue(distinct.isEmpty)
    }

    func testNameSimilarityIgnoresGenericWords() {
        XCTAssertEqual(VenueSearch.nameSimilarity("Elite Rally Badminton Club", "Elite Rally"), 1, accuracy: 0.001)
        XCTAssertLessThan(VenueSearch.nameSimilarity("Elite Rally Badminton Club", "Arena Badminton Club"), 0.5)
        XCTAssertGreaterThanOrEqual(VenueSearch.nameSimilarity("朝阳体育中心羽毛球馆", "朝阳体育中心"), 0.5)
    }

    // MARK: Map links

    func testGoogleMapsPlaceLinkUsesPinCoordinate() throws {
        let url = try XCTUnwrap(URL(string: "https://www.google.com/maps/place/Los+Angeles+Badminton+Club/@34.0760,-118.0500,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d34.0764690!4d-118.0461160"))
        let link = try XCTUnwrap(MapLinkParser.parse(url))
        XCTAssertEqual(link.provider, .google)
        XCTAssertEqual(link.name, "Los Angeles Badminton Club")
        XCTAssertEqual(try XCTUnwrap(link.coordinate).latitude, 34.076469, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(link.coordinate).longitude, -118.046116, accuracy: 0.000001)
    }

    func testGoogleSearchAndQueryLinks() throws {
        let search = try XCTUnwrap(MapLinkParser.parse(URL(string: "https://www.google.com/maps/search/?api=1&query=Elite+Rally+Badminton&query_place_id=ChIJabc")!))
        XCTAssertEqual(search.query, "Elite Rally Badminton")
        XCTAssertEqual(search.googlePlaceId, "ChIJabc")
        let coordinate = try XCTUnwrap(MapLinkParser.parse(URL(string: "https://maps.google.com/?q=34.07,-118.04")!))
        XCTAssertEqual(coordinate.coordinate, Coordinate(latitude: 34.07, longitude: -118.04))
    }

    func testAppleMapsLinks() throws {
        let ll = try XCTUnwrap(MapLinkParser.parse(URL(string: "https://maps.apple.com/?ll=34.0765,-118.0461&q=LABC")!))
        XCTAssertEqual(ll.provider, .apple)
        XCTAssertEqual(ll.name, "LABC")
        XCTAssertEqual(ll.coordinate, Coordinate(latitude: 34.0765, longitude: -118.0461))
        let place = try XCTUnwrap(MapLinkParser.parse(URL(string: "https://maps.apple.com/place?place-id=I8BD5B9976F940FB5&_provider=9902")!))
        XCTAssertEqual(place.applePlaceId, "I8BD5B9976F940FB5")
    }

    func testFindsMapLinkInsideSharedText() {
        let text = "周六去这里打 👉 https://maps.app.goo.gl/AbCdEf123 （停车在后面）"
        let url = MapLinkParser.firstMapURL(in: text)
        XCTAssertEqual(url?.host, "maps.app.goo.gl")
        XCTAssertTrue(MapLinkParser.needsExpansion(url!))
        XCTAssertNil(MapLinkParser.firstMapURL(in: "https://example.com/not-a-map"))
    }

    func testRejectsInvalidCoordinates() {
        XCTAssertNil(MapLinkParser.coordinate(from: "0,0"))
        XCTAssertNil(MapLinkParser.coordinate(from: "123,45"))
        XCTAssertNotNil(MapLinkParser.coordinate(from: "-33.86, 151.21"))
    }

    // MARK: Country, money, phone

    func testMoneyFormatting() {
        XCTAssertEqual(Money.format(17, currency: "USD"), "$17")
        XCTAssertEqual(Money.format(80, currency: "CNY"), "¥80")
        XCTAssertEqual(Money.format(15, currency: "MYR"), "RM15")
        XCTAssertEqual(Money.icon(for: "USD"), "dollarsign.circle.fill")
    }

    func testPhoneNumbersPerCountry() {
        let us = CountryInfo.info(for: "US")
        let typed = PhoneNumber(country: us, national: "(626) 555-0123")
        XCTAssertTrue(typed.isValid)
        XCTAssertEqual(typed.e164, "+16265550123")
        XCTAssertEqual(typed.display, "+1 626 555 0123")
        XCTAssertEqual(typed.masked, "+1 626 *** 0123")
        XCTAssertEqual(PhoneNumber(country: us, national: "1 626 555 0123").e164, "+16265550123", "允许带国家码 1 输入")
        XCTAssertFalse(PhoneNumber(country: us, national: "026 555 0123").isValid)

        let cn = CountryInfo.info(for: "CN")
        XCTAssertTrue(PhoneNumber(country: cn, national: "13800001234").isValid)
        XCTAssertEqual(PhoneNumber.parse("+8613800001234")?.country.code, "CN")

        let jp = CountryInfo.info(for: "JP")
        let japanese = PhoneNumber(country: jp, national: "090-1234-5678")
        XCTAssertEqual(japanese.e164, "+819012345678", "去掉国内前缀 0")
        XCTAssertTrue(japanese.isValid)

        XCTAssertEqual(PhoneNumber.parse("+85251234567")?.country.code, "HK", "最长国家码优先")
        XCTAssertNil(PhoneNumber.parse("+999123"))
    }

    func testVenueCurrencyAndShuttleFollowCountry() {
        let us = venue("us", "Test", at: la)
        XCTAssertEqual(us.currencyCode, "USD")
        XCTAssertEqual(us.country.navigationApps.first, .appleMaps)
        XCTAssertTrue(us.country.navigationApps.contains(.googleMaps))
        XCTAssertEqual(BadmintonCourt.curatedBeijing[0].currencyCode, "CNY")
        XCTAssertEqual(BadmintonCourt.curatedBeijing[0].country.navigationApps.first, .amap)
    }

    func testConfirmationsPromoteStatus() {
        var added = venue("new", "New Gym", at: la, status: .unconfirmed)
        added.addConfirmation(from: "a")
        added.addConfirmation(from: "a")
        added.addConfirmation(from: "b")
        XCTAssertEqual(added.status, .unconfirmed)
        added.addConfirmation(from: "c")
        XCTAssertEqual(added.status, .confirmed)
        XCTAssertEqual(added.confirmedBy, ["a", "b", "c"])
        XCTAssertNotNil(added.lastConfirmedAt)
    }

    func testBadmintonSearchUsesLocalTerms() {
        XCTAssertEqual(BadmintonKeywords.queries(for: "ID"), ["badminton", "bulu tangkis", "GOR badminton"])
        XCTAssertEqual(BadmintonKeywords.queries(for: "vn"), ["badminton", "sân cầu lông"])
        XCTAssertEqual(BadmintonKeywords.queries(for: "US").first, "badminton")
        XCTAssertLessThanOrEqual(BadmintonKeywords.queries(for: "CN").count, 3, "Apple 搜索有频率限制")
    }
}
