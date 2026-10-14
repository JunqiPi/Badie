import Foundation

// MARK: - 美国收录球馆（首发市场）
//
// 由 docs/DESIGN.md §9 的调研生成：每家至少 2 个独立来源互相印证地址（官网、Yelp、地图条目、俱乐部目录），
// 坐标来自 US Census Geocoder 门牌地址匹配（Elite Rally 来自 OpenStreetMap，精确到街道）。
// 价格为工作日晚间非会员价，来自官网或公开预订页；未公开的标为未知，不估算。
// 已排除确认或疑似关门的球馆（如 Yan Long、Arcadia BC、IBC Irvine 等）。

extension BadmintonCourt {
    static let curatedUS: [BadmintonCourt] = [
        // 来源 7 个：https://www.labadmintonclub.com/ https://www.labadmintonclub.com/pricing https://www.yelp.com/biz/los-angeles-badminton-club-el-monte
        // 注意：Chinese directory (ccyp) writes '10410 E. Valley Blvd'; an old Badminton Central forum entry gives 10388 Valley Blvd. Court count 15 comes from badmintonclubs.org, not the official site.
        BadmintonCourt(
            id: "v-us-ca-labc",
            name: "Los Angeles Badminton Club",
            aliases: ["LABC", "LA Badminton Club", "L.A. Badminton Club", "洛杉磯羽毛球俱樂部", "洛杉矶羽毛球俱乐部"],
            location: Coordinate(latitude: 34.076502, longitude: -118.046195),
            address: PostalAddress(street: "10410 Valley Blvd", unit: nil, city: "El Monte", region: "CA", postalCode: "91731", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 15,
            pricing: .dropIn(perPerson: 10),
            pricingNote: "散客 $10/人次 · 包场 $20/场·时",
            phone: "(626) 279-9919",
            website: "https://www.labadmintonclub.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 7 个：https://booking.eliterallybc.com/ https://www.yelp.com/biz/elite-rally-badminton-club-baldwin-park https://www.mapquest.com/us/california/elite-rally-badminton-club-388163031
        // 注意：City conflict: Yelp, MapQuest, Yahoo Local and Roadtrippers list 'Baldwin Park, CA 91706'; Atly files it under Irwindale, and the SWBA directory listed the previous club at this same address (Yan Long Badminton Club, now closed) as Irwindale. A Census incorporated-place lookup puts both the OSM stre
        BadmintonCourt(
            id: "v-us-ca-elite-rally",
            name: "Elite Rally Badminton Club",
            aliases: ["Elite Rally", "Elite Rally BC"],
            location: Coordinate(latitude: 34.095632, longitude: -117.986341),
            address: PostalAddress(street: "4800 Rivergrade Rd", unit: "Ste B", city: "Baldwin Park", region: "CA", postalCode: "91706", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 11,
            pricing: .dropIn(perPerson: 15),
            pricingNote: "散客 $15/人次",
            phone: "(213) 628-4135",
            website: "https://booking.eliterallybc.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 7 个：https://sgvbadminton.com/ https://www.sgvbc.net/ https://www.yelp.com/biz/san-gabriel-valley-badminton-club-el-monte
        // 注意：Unit differs: new official site (sgvbadminton.com) says '# J'; older official site (sgvbc.net, 2023) and localgymsandfitness say 'Unit I / Ste I'. Price changed: sgvbc.net (2023) listed $12 walk-in and $25/hr; current booking system says $14 entry and $28/hr. 18 courts total, of which 12 are reserva
        BadmintonCourt(
            id: "v-us-ca-san-gabriel-valley-badminton-club",
            name: "San Gabriel Valley Badminton Club",
            aliases: ["SGVBC", "SGV Badminton Club", "San Gabriel Valley BC", "聖蓋博羽毛球‧乒乓球俱樂部", "圣盖博羽毛球‧乒乓球俱乐部"],
            location: Coordinate(latitude: 34.068869, longitude: -118.066513),
            address: PostalAddress(street: "9255 Telstar Ave", unit: "Unit J", city: "El Monte", region: "CA", postalCode: "91731", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 18,
            pricing: .dropIn(perPerson: 14),
            pricingNote: "散客 $14/人次 · 包场 $28/场·时",
            phone: "(626) 307-4650",
            website: "https://sgvbadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://www.arenabadminton.com/ https://www.yelp.com/biz/arena-badminton-and-sports-club-pomona https://www.waze.com/live-map/directions/us/ca/pomona/arena-badminton-and-sports-club?to=place.ChIJAcuu67Ezw4ARLPr7EGa5pWE
        // 注意：Phone differs: official site lists 909-464-2144 and 719-465-9614; Yellow Pages/Chamber of Commerce list 626-267-9321. Official site says 24 courts; a Yelp review summary says 20.
        BadmintonCourt(
            id: "v-us-ca-arena-badminton-sports-club",
            name: "Arena Badminton & Sports Club",
            aliases: ["Arena Badminton", "Arena Badminton and Sports Club"],
            location: Coordinate(latitude: 34.023665, longitude: -117.731345),
            address: PostalAddress(street: "2780 S Reservoir St", unit: nil, city: "Pomona", region: "CA", postalCode: "91766", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 24,
            pricing: .dropIn(perPerson: 16),
            pricingNote: "散客 $16/人次 · 包场 $42/场·时",
            phone: "(909) 464-2144",
            website: "https://www.arenabadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://www.sfsbadmintonclub.com/ https://www.yelp.com/biz/santa-fe-springs-badminton-club-santa-fe-springs https://maps.apple.com/place?place-id=I8BD5B9976F940FB5
        // 注意：Court count (14) is from badmintonjustin.com, not the official site.
        BadmintonCourt(
            id: "v-us-ca-santa-fe-springs-badminton-club",
            name: "Santa Fe Springs Badminton Club",
            aliases: ["SFSBC", "Santa Fe Springs BC"],
            location: Coordinate(latitude: 33.929024, longitude: -118.055270),
            address: PostalAddress(street: "11323 Shoemaker Ave", unit: nil, city: "Santa Fe Springs", region: "CA", postalCode: "90670", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 14,
            pricing: .dropIn(perPerson: 12),
            pricingNote: "散客 $12/人次",
            phone: "(562) 273-0945",
            website: "https://www.sfsbadmintonclub.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 6 个：https://ocbadmintonclub.com/ https://ocbadmintonclub.com/about/ https://ocbadmintonclub.com/reservations/
        // 注意：Official About page says 12 courts; one third-party listing says 18. Address written as '1432-A North Main Street' on SWBA.
        BadmintonCourt(
            id: "v-us-ca-orange-county-badminton-club",
            name: "Orange County Badminton Club",
            aliases: ["OCBC", "OC Badminton Club", "Orange County Badminton Club, Inc."],
            location: Coordinate(latitude: 33.811177, longitude: -117.867345),
            address: PostalAddress(street: "1432 N Main St", unit: "Ste A", city: "Orange", region: "CA", postalCode: "92867", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 12,
            pricing: .perCourtHour(42),
            pricingNote: "包场 $42/场·时",
            phone: "(714) 639-6222",
            website: "https://ocbadmintonclub.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 6 个：https://www.badmintoncentercourt.com/ https://dnasports.shop/pages/about https://www.yelp.com/biz/badminton-center-court-lakewood-2
        // 注意：Renamed from 'Badminton Center Court' and now shares the floor with pickleball (up to 6 badminton or 5 pickleball courts). Some listings place it in Long Beach (next to Long Beach Airport); a 2023 Yelp snippet mentions 20 courts. Census incorporated-place lookup confirms the coordinate is in the Cit
        BadmintonCourt(
            id: "v-us-ca-pickleball-badminton-center",
            name: "PickleBall Badminton Center",
            aliases: ["Badminton Center Court", "BCC", "BCC Sports Center", "PBC Lakewood"],
            location: Coordinate(latitude: 33.824362, longitude: -118.165499),
            address: PostalAddress(street: "3699 Industry Ave", unit: nil, city: "Lakewood", region: "CA", postalCode: "90712", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 6,
            pricing: .dropIn(perPerson: 15),
            pricingNote: "散客 $15/人次 · 包场 $38/场·时",
            phone: "(562) 426-9299",
            website: "https://www.badmintoncentercourt.com/",
            entranceNote: "与匹克球共用场地，羽毛球最多 6 片",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://mbbadmintonclub.com/contact-us/ https://www.mapquest.com/us/california/manhattan-beach-badminton-club-10886678 https://www.yelp.com/biz/manhattan-beach-badminton-club-manhattan-beach
        // 注意：Private members-only club (cap ~250 members, waitlist; guests only with a member). Phone differs: 310-545-9052 (directory) vs (310) 546-3652 (SWBA). Court count 5 from a directory listing.
        BadmintonCourt(
            id: "v-us-ca-manhattan-beach-badminton-club",
            name: "Manhattan Beach Badminton Club",
            aliases: ["MBBC"],
            location: Coordinate(latitude: 33.890185, longitude: -118.409269),
            address: PostalAddress(street: "516 18th St", unit: nil, city: "Manhattan Beach", region: "CA", postalCode: "90266", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 5,
            pricing: .unknown,
            phone: "(310) 545-9052",
            website: "https://mbbadmintonclub.com/",
            entranceNote: "会员制私人俱乐部，不接待散客",
            source: .curated,
            status: .verified
        ),
        // 来源 6 个：https://www.smashbsd.com/contact-us https://www.smashbsd.com/drop-in-pass https://www.yelp.com/biz/smash-badminton-san-diego-san-diego
        // 注意：Official site shows two phone numbers ((858) 397-2153 and (858) 876-2741) and two sets of hours.
        BadmintonCourt(
            id: "v-us-ca-smash-badminton-san-diego",
            name: "SMASH! Badminton San Diego",
            aliases: ["SMASH!", "Smash Badminton San Diego", "SmashBSD"],
            location: Coordinate(latitude: 32.881040, longitude: -117.163099),
            address: PostalAddress(street: "9586 Distribution Ave", unit: "Ste E", city: "San Diego", region: "CA", postalCode: "92121", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 7,
            pricing: .dropIn(perPerson: 14),
            pricingNote: "散客 $14/人次",
            phone: "(858) 397-2153",
            website: "https://www.smashbsd.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://www.mapquest.com/us/california/oc-smash-badminton-club-375070255 https://local.yahoo.com/info-193123423-oc-smash-badminton-club-anaheim/ https://www.yelp.com/biz/oc-smash-badminton-club-anaheim
        // 注意：Status uncertain: no official website found, not on the SCBA places-to-play list, and listed hours are limited (weekdays 9 AM-1 PM, Sunday afternoon; Sunday '3 AM' looks like a data error). A different club at the same address, OC High Badminton Club, is marked closed on Yelp. Korean-community club;
        BadmintonCourt(
            id: "v-us-ca-oc-smash-badminton-club",
            name: "OC SMASH Badminton Club",
            aliases: ["OC Smash", "OC SMASH Badminton club 배드민턴 클럽"],
            location: Coordinate(latitude: 33.810548, longitude: -117.905983),
            address: PostalAddress(street: "1500 S Anaheim Blvd", unit: "Ste 110", city: "Anaheim", region: "CA", postalCode: "92805", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 8,
            pricing: .unknown,
            phone: "(310) 995-5424",
            source: .curated,
            status: .unconfirmed
        ),
        // 来源 5 个：https://baybadminton.com/ https://baybadminton.com/rates/court_rental/ https://www.badmintonjustin.com/clubs/california/milpitas/bay-badminton-center-milpitas
        // 注意：Official site writes '1191 West Montague Expressway (inside Montague Court at Flemings Business Park)'; directories drop 'West'. Court count 13 from the club's (now 404) locations page via search; About page says 22 courts across both locations.
        BadmintonCourt(
            id: "v-us-ca-bay-badminton-center-milpitas",
            name: "Bay Badminton Center - Milpitas",
            aliases: ["Bay Badminton Center", "Bay Badminton", "BBC Milpitas"],
            location: Coordinate(latitude: 37.413597, longitude: -121.883504),
            address: PostalAddress(street: "1191 W Montague Expy", unit: nil, city: "Milpitas", region: "CA", postalCode: "95035", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 13,
            pricing: .perCourtHour(55),
            pricingNote: "包场 $55/场·时",
            phone: "(408) 942-2888",
            website: "https://baybadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://baybadminton.com/ https://baybadminton.com/rates/court_rental/ https://www.yelp.com/biz/bay-badminton-center-south-san-francisco
        // 注意：A Groupon listing cites 37 courts across 3 locations (outdated); 9 courts per club locations page and badmintonclubs.org.
        BadmintonCourt(
            id: "v-us-ca-bay-badminton-center-south-san-francisco",
            name: "Bay Badminton Center - South San Francisco",
            aliases: ["Bay Badminton Center", "Bay Badminton", "BBC South SF"],
            location: Coordinate(latitude: 37.645452, longitude: -122.409971),
            address: PostalAddress(street: "1404 San Mateo Ave", unit: nil, city: "South San Francisco", region: "CA", postalCode: "94080", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 9,
            pricing: .perCourtHour(55),
            pricingNote: "包场 $55/场·时",
            phone: "(650) 588-2088",
            website: "https://baybadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://elitebadmintoncenter.com/ https://www.yelp.com/biz/elite-badminton-center-union-city https://www.mapquest.com/us/california/elite-badminton-center-427897403
        BadmintonCourt(
            id: "v-us-ca-elite-badminton-center",
            name: "Elite Badminton Center",
            aliases: ["EBC", "Elite Badminton Center Union City"],
            location: Coordinate(latitude: 37.593428, longitude: -122.039043),
            address: PostalAddress(street: "33540 Central Ave", unit: nil, city: "Union City", region: "CA", postalCode: "94587", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 16,
            pricing: .dropIn(perPerson: 17),
            pricingNote: "散客 $17/人次",
            phone: "(510) 431-3130",
            website: "https://elitebadmintoncenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 6 个：https://bintangbadminton.org/ https://bintangbadminton.org/locations-3/ https://bintangbadminton.org/court-reservations/
        // 注意：Opened 8 Nov 2024 replacing the Milpitas location. Homepage soft-opening special ($15 lunch / $17 evenings & weekends) conflicts with the reservations page ($21 non-member door fee). Also has 6 pickleball courts. Official homepage currently carries injected gambling spam text (site may be compromise
        BadmintonCourt(
            id: "v-us-ca-bintang-badminton-fremont",
            name: "Bintang Badminton - Fremont",
            aliases: ["Bintang", "Bintang Badminton Academy", "Bintang Fremont"],
            location: Coordinate(latitude: 37.461195, longitude: -121.921851),
            address: PostalAddress(street: "48900 Milmont Dr", unit: nil, city: "Fremont", region: "CA", postalCode: "94538", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 54,
            pricing: .dropIn(perPerson: 21),
            pricingNote: "散客 $21/人次 · 包场 $35/场·时",
            phone: "(510) 270-8386",
            website: "https://bintangbadminton.org/",
            source: .curated,
            status: .verified
        ),
        // 来源 4 个：https://bintangbadminton.org/locations-3/ https://bintangbadminton.org/court-reservations/ https://www.yelp.com/biz/bintang-badminton-santa-clara-santa-clara
        BadmintonCourt(
            id: "v-us-ca-bintang-badminton-santa-clara",
            name: "Bintang Badminton - Santa Clara",
            aliases: ["Bintang", "Bintang Badminton Academy", "Bintang Santa Clara"],
            location: Coordinate(latitude: 37.371777, longitude: -121.979196),
            address: PostalAddress(street: "2911 Mead Ave", unit: nil, city: "Santa Clara", region: "CA", postalCode: "95051", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: nil,
            pricing: .dropIn(perPerson: 21),
            pricingNote: "散客 $21/人次 · 包场 $35/场·时",
            phone: "(408) 541-1837",
            website: "https://bintangbadminton.org/",
            source: .curated,
            status: .verified
        ),
        // 来源 4 个：https://www.bellevuebadminton.com/location-hours/ https://www.bellevuebadminton.com/reserve-a-court/ https://www.yelp.com/biz/bellevue-badminton-club-bellevue
        // 注意：Club reports 62 courts across 5 locations (Bellevue, Redmond, Mukilteo, Renton, Southcenter/Tukwila) but no per-site count. One old Yelp page still carries a 2020 closure notice.
        BadmintonCourt(
            id: "v-us-wa-bellevue-badminton-club-bellevue",
            name: "Bellevue Badminton Club - Bellevue",
            aliases: ["Bellevue Badminton Club", "BBC", "BBC Bellevue"],
            location: Coordinate(latitude: 47.583694, longitude: -122.160720),
            address: PostalAddress(street: "13405 SE 30th St", unit: "Ste 1C", city: "Bellevue", region: "WA", postalCode: "98005", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: nil,
            pricing: .perCourtHour(41),
            pricingNote: "包场 $41/场·时",
            phone: "(425) 562-2950",
            website: "https://www.bellevuebadminton.com/",
            entranceNote: "不接受散客 walk-in，需提前预约",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://www.bellevuebadminton.com/location-hours/ https://www.bellevuebadminton.com/reserve-a-court/ https://www.mapquest.com/us/washington/bellevue-badminton-club-779000897
        // 注意：Per-site court count not published (62 courts across 5 locations).
        BadmintonCourt(
            id: "v-us-wa-bellevue-badminton-club-redmond",
            name: "Bellevue Badminton Club - Redmond",
            aliases: ["Bellevue Badminton Club", "BBC", "BBC Redmond"],
            location: Coordinate(latitude: 47.684128, longitude: -122.136645),
            address: PostalAddress(street: "15340 NE 92nd St", unit: "Ste B", city: "Redmond", region: "WA", postalCode: "98052", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: nil,
            pricing: .perCourtHour(41),
            pricingNote: "包场 $41/场·时",
            phone: "(425) 522-4895",
            website: "https://www.bellevuebadminton.com/",
            entranceNote: "不接受散客 walk-in，需提前预约",
            source: .curated,
            status: .verified
        ),
        // 来源 4 个：https://seattlebadminton.com/sbc/ https://seattlebadminton.com/sbc/drop-in-play/ https://www.explorekirkland.com/directory/seattle-badminton-club/
        // 注意：Despite the name, located in Kirkland. Non-member drop-in hours differ across the club's own pages (weekdays 2-4 PM vs 4-6 PM).
        BadmintonCourt(
            id: "v-us-wa-seattle-badminton-club",
            name: "Seattle Badminton Club",
            aliases: ["SBC", "Seattle Badminton Club Kirkland"],
            location: Coordinate(latitude: 47.698813, longitude: -122.184475),
            address: PostalAddress(street: "10858 117th Pl NE", unit: nil, city: "Kirkland", region: "WA", postalCode: "98033", countryCode: "US"),
            timeZoneId: "America/Los_Angeles",
            courtCount: 10,
            pricing: .dropIn(perPerson: 20),
            pricingNote: "散客 $20/人次",
            phone: "(425) 889-5958",
            website: "https://seattlebadminton.com/sbc/",
            source: .curated,
            status: .verified
        ),
        // 来源 4 个：https://www.newyorkcitybadminton.com/flushing https://www.newyorkcitybadminton.com/book-court https://www.yelp.com/biz/new-york-badminton-center-flushing
        // 注意：Phone: front desk 347-955-7859; reservations/training 646-271-3228. Flushing is a USPS place name within Queens (New York City).
        BadmintonCourt(
            id: "v-us-ny-new-york-badminton-center-flushing",
            name: "New York Badminton Center - Flushing",
            aliases: ["NYBC", "NY Badminton Center", "NYBC Flushing"],
            location: Coordinate(latitude: 40.765378, longitude: -73.834821),
            address: PostalAddress(street: "132-70 34th Ave", unit: nil, city: "Flushing", region: "NY", postalCode: "11354", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 7,
            pricing: .dropIn(perPerson: 22),
            pricingNote: "散客 $22/人次 · 包场 $100/场·时",
            phone: "(347) 955-7859",
            website: "https://www.newyorkcitybadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 6 个：https://www.brooklynbadmintoncenter.com/contactus https://www.brooklynbadmintoncenter.com/make-a-reservation https://www.brooklynbadmintoncenter.com/multipassoption
        // 注意：Named 'Brooklyn' but the address is Ridgewood, Queens (11385); Yelp lists the city as 'New York'. Phones differ: front desk (516) 988-8955, reservations (646) 271-3228, Apple Maps (347) 460-4696.
        BadmintonCourt(
            id: "v-us-ny-brooklyn-badminton-center",
            name: "Brooklyn Badminton Center",
            aliases: ["BKBC", "BKBC Ridgewood"],
            location: Coordinate(latitude: 40.713308, longitude: -73.920088),
            address: PostalAddress(street: "14 Woodward Ave", unit: nil, city: "Ridgewood", region: "NY", postalCode: "11385", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 7,
            pricing: .dropIn(perPerson: 23),
            pricingNote: "散客 $23/人次 · 包场 $100/场·时",
            phone: "(516) 988-8955",
            website: "https://www.brooklynbadmintoncenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://longislandbadmintoncenter.com/ https://longislandbadmintoncenter.com/membership https://maps.apple.com/place?place-id=IA5A8021D463B0D04
        // 注意：Court count 20 is from a review site describing the winter 2024-25 reopening, not the official site. Facebook page describes the club as located in Westbury while listing the Melville address. Phones: front desk 516-916-3364, Ming 516-388-7821. Melville is a census-designated place in the Town of Hu
        BadmintonCourt(
            id: "v-us-ny-long-island-badminton-center",
            name: "Long Island Badminton Center",
            aliases: ["LIBC"],
            location: Coordinate(latitude: 40.761699, longitude: -73.437429),
            address: PostalAddress(street: "260 Spagnoli Rd", unit: nil, city: "Melville", region: "NY", postalCode: "11747", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 20,
            pricing: .unknown,
            phone: "(516) 916-3364",
            website: "https://longislandbadmintoncenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://www.njbadminton.com/ https://www.njbadminton.com/about https://www.njbadminton.com/open-play-challenge-court
        // 注意：Official site misspells the street 'Changebridage Rd'. Phones differ: text (201) 898-0382 (official), (201) 572-4993 (Yelp), (973) 265-0250 (Nextdoor). A Yelp review cites $18/person vs the official $15. Sister site 'NJBC Dream' (21 courts, Secaucus) not included because its street address is not on
        BadmintonCourt(
            id: "v-us-nj-new-jersey-badminton-club-montville",
            name: "New Jersey Badminton Club - Montville",
            aliases: ["NJBC", "NJ Badminton Club", "NJBC Montville"],
            location: Coordinate(latitude: 40.916254, longitude: -74.362422),
            address: PostalAddress(street: "2 Changebridge Rd", unit: "Unit JKL", city: "Montville", region: "NJ", postalCode: "07045", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 7,
            pricing: .dropIn(perPerson: 15),
            pricingNote: "散客 $15/人次",
            phone: "(201) 898-0382",
            website: "https://www.njbadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://www.ibcusa.org/location https://ibcusa.org/court-booking https://www.yellowpages.com/edison-nj/mip/international-badminton-center-472935314
        // 注意：Sister location in Pine Brook, NJ (10 New Maple Ave, Unit 302) not included; official page lists 4 courts there while a third-party summary says 9.
        BadmintonCourt(
            id: "v-us-nj-international-badminton-center-edison",
            name: "International Badminton Center - Edison",
            aliases: ["IBC", "IBC Edison"],
            location: Coordinate(latitude: 40.571585, longitude: -74.387420),
            address: PostalAddress(street: "3775 Park Ave", unit: "Unit 8A", city: "Edison", region: "NJ", postalCode: "08820", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 6,
            pricing: .unknown,
            phone: "(732) 549-7190",
            website: "https://www.ibcusa.org/",
            source: .curated,
            status: .verified
        ),
        // 来源 4 个：https://www.houstonbadminton.com/ https://www.houstonbadmintonclub.com/ https://communityimpact.com/local-news/houston-metro/news/2016/09/01/one-year-game-houston-badminton-center-stafford
        // 注意：In Stafford (Fort Bend County), southwest of Houston. 2015 coverage gives phone 832-331-7546 and domain houstonbadmintoncenter.com; current site uses 346-229-4921.
        BadmintonCourt(
            id: "v-us-tx-houston-badminton-center",
            name: "Houston Badminton Center",
            aliases: ["HBC", "Houston Badminton"],
            location: Coordinate(latitude: 29.641254, longitude: -95.563935),
            address: PostalAddress(street: "10550 W Airport Blvd", unit: nil, city: "Stafford", region: "TX", postalCode: "77477", countryCode: "US"),
            timeZoneId: "America/Chicago",
            courtCount: 12,
            pricing: .unknown,
            phone: "(346) 229-4921",
            website: "https://www.houstonbadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://planobadmintoncenter.com/contact-us/ https://pbc.pike13.com/locations https://www.loc8nearme.com/texas/plano/plano-badminton-center/5707825/
        // 注意：Court count: 5 per the center's X profile vs 4 on badmintonclubs.org. Phone (469) 677-7686 is text-preferred; central number (949) 436-8849.
        BadmintonCourt(
            id: "v-us-tx-plano-badminton-center",
            name: "Plano Badminton Center",
            aliases: ["PBC", "Plano Badminton"],
            location: Coordinate(latitude: 33.052588, longitude: -96.699816),
            address: PostalAddress(street: "4050 Premier Dr", unit: "Ste 250", city: "Plano", region: "TX", postalCode: "75023", countryCode: "US"),
            timeZoneId: "America/Chicago",
            courtCount: 5,
            pricing: .dropIn(perPerson: 11),
            pricingNote: "散客 $11/人次 · 包场 $48/场·时",
            phone: "(469) 677-7686",
            website: "https://planobadmintoncenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://dfwbadmintoncenter.com/ https://dfwbadmintoncenter.com/contact-us/ https://pbc.pike13.com/locations/dfw-badminton-center-irving
        // 注意：Phone: official (469) 200-0276 vs Yelp (469) 389-0771. A Zaubee review mentions 12 courts vs 13 on the official site.
        BadmintonCourt(
            id: "v-us-tx-dfw-badminton-center",
            name: "DFW Badminton Center",
            aliases: ["DFWBC", "DFW Badminton", "DFW Badminton Center Irving"],
            location: Coordinate(latitude: 32.874375, longitude: -96.974826),
            address: PostalAddress(street: "1800 Hurd Dr", unit: nil, city: "Irving", region: "TX", postalCode: "75038", countryCode: "US"),
            timeZoneId: "America/Chicago",
            courtCount: 13,
            pricing: .dropIn(perPerson: 11),
            pricingNote: "散客 $11/人次 · 包场 $48/场·时",
            phone: "(469) 200-0276",
            website: "https://dfwbadmintoncenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://badmintontrainingcenter.com/pages/location-hours https://badmintontrainingcenter.com/pages/contact-us https://badmintontrainingcenter.com/pages/walk-in-chicago-location
        // 注意：A WellnessLiving listing titled 'Chicago Egret Badminton Club' shows the Schaumburg address. Court count not published.
        BadmintonCourt(
            id: "v-us-il-egret-badminton-chicago",
            name: "Egret Badminton Chicago",
            aliases: ["Chicago Egret Badminton Club", "Egret Chicago", "Egret"],
            location: Coordinate(latitude: 41.858651, longitude: -87.674819),
            address: PostalAddress(street: "1936 W 17th St", unit: nil, city: "Chicago", region: "IL", postalCode: "60608", countryCode: "US"),
            timeZoneId: "America/Chicago",
            courtCount: nil,
            pricing: .dropIn(perPerson: 17),
            pricingNote: "散客 $17/人次",
            phone: "(312) 374-3022",
            website: "https://badmintontrainingcenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 4 个：https://badmintontrainingcenter.com/pages/location-hours https://badmintontrainingcenter.com/pages/walk-in-schaumburg-location https://www.yelp.com/biz/egret-badminton-club-schaumburg
        // 注意：Court count not published.
        BadmintonCourt(
            id: "v-us-il-egret-badminton-schaumburg",
            name: "Egret Badminton Schaumburg",
            aliases: ["Egret Badminton Club Schaumburg", "Egret Schaumburg", "Egret"],
            location: Coordinate(latitude: 42.052037, longitude: -88.065147),
            address: PostalAddress(street: "1251 Basswood Rd", unit: nil, city: "Schaumburg", region: "IL", postalCode: "60173", countryCode: "US"),
            timeZoneId: "America/Chicago",
            courtCount: nil,
            pricing: .dropIn(perPerson: 15),
            pricingNote: "散客 $15/人次",
            phone: "(847) 285-5788",
            website: "https://badmintontrainingcenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://badmintontrainingcenter.com/pages/location-hours https://badmintontrainingcenter.com/pages/walk-in https://www.badmintonjustin.com/clubs/illinois/naperville/egret-badminton-club-naperville
        // 注意：Unit written as '#191'. Court count 9 from a third-party listing, not the official site.
        BadmintonCourt(
            id: "v-us-il-egret-badminton-naperville",
            name: "Egret Badminton Naperville",
            aliases: ["Egret Badminton Club Naperville", "Egret Naperville", "Egret"],
            location: Coordinate(latitude: 41.776296, longitude: -88.198930),
            address: PostalAddress(street: "1811 High Grove Ln", unit: "Ste 191", city: "Naperville", region: "IL", postalCode: "60540", countryCode: "US"),
            timeZoneId: "America/Chicago",
            courtCount: 9,
            pricing: .dropIn(perPerson: 13),
            pricingNote: "散客 $13/人次",
            phone: "(630) 536-8032",
            website: "https://badmintontrainingcenter.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 4 个：https://ljbbc.com/ https://maps.apple.com/place?place-id=I48B4A99BFF347479 https://www.atly.com/location/LJBBadmintonClub
        // 注意：Unit: official site 'Unit B' vs a map listing 'unit c'. Court count: official 14 (after 2025 expansion approved by Woburn City Council) vs 5 on an older Atly listing.
        BadmintonCourt(
            id: "v-us-ma-ljb-badminton-club",
            name: "LJB Badminton Club",
            aliases: ["LJB", "LJBBC"],
            location: Coordinate(latitude: 42.499281, longitude: -71.138139),
            address: PostalAddress(street: "78 Olympia Ave", unit: "Unit B", city: "Woburn", region: "MA", postalCode: "01801", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 14,
            pricing: .dropIn(perPerson: 20),
            pricingNote: "散客 $20/人次 · 包场 $30/场·时",
            phone: "(339) 227-3580",
            website: "https://ljbbc.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 6 个：https://www.bostonbadminton.com/ https://www.bostonbadminton.com/membershipfees https://www.bostonbadminton.com/westborough/court-reservations
        // 注意：Official site labels 169 Flanders Road as a mailing address (it is also the facility address on Yelp and other listings). About 30 miles west of Boston.
        BadmintonCourt(
            id: "v-us-ma-boston-badminton-westborough",
            name: "Boston Badminton - Westborough",
            aliases: ["Boston Badminton", "Boston Badminton Westboro", "Boston Badminton Club"],
            location: Coordinate(latitude: 42.275408, longitude: -71.560047),
            address: PostalAddress(street: "169 Flanders Rd", unit: nil, city: "Westborough", region: "MA", postalCode: "01581", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 8,
            pricing: .dropIn(perPerson: 18),
            pricingNote: "散客 $18/人次 · 包场 $40/场·时",
            phone: "(508) 329-1710",
            website: "https://www.bostonbadminton.com/",
            source: .curated,
            status: .verified
        ),
        // 来源 5 个：https://www.bostonbadminton.com/harvard https://www.bostonbadminton.com/harvard/court-reservations https://www.harvard-ma.gov/247/Badminton-Facility-203-Ayer-Road-DEP-Num
        // 注意：Located in the town of Harvard, MA (off Route 2), not Harvard University. Opened 2025-2026; exact opening date not found.
        BadmintonCourt(
            id: "v-us-ma-boston-badminton-at-harvard",
            name: "Boston Badminton at Harvard",
            aliases: ["Boston Badminton Harvard", "Boston Badminton"],
            location: Coordinate(latitude: 42.528154, longitude: -71.578921),
            address: PostalAddress(street: "203 Ayer Rd", unit: nil, city: "Harvard", region: "MA", postalCode: "01451", countryCode: "US"),
            timeZoneId: "America/New_York",
            courtCount: 16,
            pricing: .dropIn(perPerson: 18),
            pricingNote: "散客 $18/人次 · 包场 $40/场·时",
            phone: "(978) 707-5203",
            website: "https://www.bostonbadminton.com/harvard",
            source: .curated,
            status: .verified
        )
    ]
}
