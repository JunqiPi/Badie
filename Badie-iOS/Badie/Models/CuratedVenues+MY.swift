import Foundation

// MARK: - 马来西亚：吉隆坡 / 巴生谷（来自 OpenStreetMap）
//
// 取 OSM 中标注为羽毛球、且有正式名称的场馆，人工去掉商店、泛称（“Gelanggang Badminton”）、
// 学校与大学体育馆、协会办公室和国家队训练中心；地址由 Nominatim 反查。
// 未经实地核实，状态为“待确认”，球友确认或签到后转为“球友确认”。
// 数据 © OpenStreetMap contributors，ODbL 1.0（球馆详情页注明来源）。

extension BadmintonCourt {
    static let curatedMY: [BadmintonCourt] = [
        // OSM node/4077599771
        BadmintonCourt(
            id: "v-my-tropicana-badminton-academy",
            name: "Tropicana Badminton Academy",
            location: Coordinate(latitude: 3.209715, longitude: 101.569830),
            address: PostalAddress(street: "Jalan Nautika B U20/B", city: "Shah Alam", region: "Selangor", postalCode: "47830", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM node/11042634871
        BadmintonCourt(
            id: "v-my-megah-rise-badminton-club",
            name: "Megah Rise Badminton Club",
            location: Coordinate(latitude: 3.114488, longitude: 101.611053),
            address: PostalAddress(street: "3 Jalan SS 24/8", city: "Petaling Jaya", region: "Selangor", postalCode: "47301", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM node/12954753939
        BadmintonCourt(
            id: "v-my-bch-badminton-court",
            name: "BCH Badminton Court",
            location: Coordinate(latitude: 3.336657, longitude: 101.522539),
            address: PostalAddress(street: "Jalan Desa Mas 1", city: "Selayang", region: "Selangor", postalCode: "48000", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM node/13008762817
        BadmintonCourt(
            id: "v-my-lavana-3-badminton-centre",
            name: "Lavana 3 Badminton Centre",
            location: Coordinate(latitude: 3.208715, longitude: 101.639824),
            address: PostalAddress(street: "Jalan Kuang Bertam 6", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "52100", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM node/13436942801
        BadmintonCourt(
            id: "v-my-cps-subang-badminton",
            name: "CPS Subang Badminton",
            location: Coordinate(latitude: 3.059256, longitude: 101.594863),
            address: PostalAddress(street: "Jalan SS 13/1K", city: "Subang Jaya", region: "Selangor", postalCode: "47610", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM node/14007712356
        BadmintonCourt(
            id: "v-my-sports-complex-cheras-selatan",
            name: "Sports Complex Cheras Selatan",
            location: Coordinate(latitude: 3.033599, longitude: 101.761449),
            address: PostalAddress(street: "Jalan Dutamas", city: "Kajang", region: "Selangor", postalCode: "43200", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/183816642
        BadmintonCourt(
            id: "v-my-new-vision-badminton-academy",
            name: "New Vision Badminton Academy",
            location: Coordinate(latitude: 3.113106, longitude: 101.637295),
            address: PostalAddress(street: "Jalan 13/1", city: "Petaling Jaya", region: "Selangor", postalCode: "46200", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/189016048
        BadmintonCourt(
            id: "v-my-pro-one-badminton-court",
            name: "Pro One Badminton Court",
            location: Coordinate(latitude: 3.063234, longitude: 101.757942),
            address: PostalAddress(street: "Persiaran Tun Perak", city: "Kajang", region: "Selangor", postalCode: "43200", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/210337473
        BadmintonCourt(
            id: "v-my-pro-one-badminton-centre",
            name: "Pro One Badminton Centre",
            location: Coordinate(latitude: 3.068189, longitude: 101.624641),
            address: PostalAddress(street: "Jalan Pipit", city: "Subang Jaya", region: "Selangor", postalCode: "46150", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/210983315
        BadmintonCourt(
            id: "v-my-sunway-extreme-park-badminton-court",
            name: "Sunway Extreme Park Badminton Court",
            location: Coordinate(latitude: 3.060309, longitude: 101.602920),
            address: PostalAddress(street: "Jalan Tasik Selatan", city: "Subang Jaya", region: "Selangor", postalCode: "46150", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/219753721
        BadmintonCourt(
            id: "v-my-usj-23-badminton-centre",
            name: "USJ 23 Badminton Centre",
            location: Coordinate(latitude: 3.024958, longitude: 101.588441),
            address: PostalAddress(street: "Persiaran Subang Damai", city: "Subang Jaya", region: "Selangor", postalCode: "47640", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/222972261
        BadmintonCourt(
            id: "v-my-usj-badminton-hall",
            name: "USJ Badminton Hall",
            location: Coordinate(latitude: 3.045372, longitude: 101.597435),
            address: PostalAddress(street: "Jalan Subang 4", city: "Subang Jaya", region: "Selangor", postalCode: "47610", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/232852209
        BadmintonCourt(
            id: "v-my-reflexworld-badminton-hall",
            name: "RefleXworld Badminton Hall",
            location: Coordinate(latitude: 3.024829, longitude: 101.602381),
            address: PostalAddress(street: "Jalan TPP 6/6", city: "Subang Jaya", region: "Selangor", postalCode: "47160", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/369963230
        BadmintonCourt(
            id: "v-my-ksl-sports",
            name: "KSL Sports",
            location: Coordinate(latitude: 2.989190, longitude: 101.615746),
            address: PostalAddress(street: "Jalan PU 4", city: "Subang Jaya", region: "Selangor", postalCode: "47140", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/491848315
        BadmintonCourt(
            id: "v-my-supercourt",
            name: "Supercourt",
            location: Coordinate(latitude: 3.034956, longitude: 101.594598),
            address: PostalAddress(street: "Jalan Subang 6", city: "Subang Jaya", region: "Selangor", postalCode: "47630", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/506774312
        BadmintonCourt(
            id: "v-my-pro-one-badminton-centre-kuala-lumpur",
            name: "Pro One Badminton Centre",
            location: Coordinate(latitude: 3.200516, longitude: 101.725466),
            address: PostalAddress(street: "Wangsa Maju", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "53300", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/546837861
        BadmintonCourt(
            id: "v-my-kompleks-d-star-arena",
            name: "Kompleks D'Star Arena",
            location: Coordinate(latitude: 3.140673, longitude: 101.780963),
            address: PostalAddress(street: "Lorong Dagang Permai 5", city: "Ampang Jaya", region: "Selangor", postalCode: "43100", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/559242780
        BadmintonCourt(
            id: "v-my-dewan-serbaguna-taman-segar",
            name: "Dewan Serbaguna Taman Segar",
            location: Coordinate(latitude: 3.095437, longitude: 101.746759),
            address: PostalAddress(street: "Jalan 1a", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "56100", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/804857546
        BadmintonCourt(
            id: "v-my-lavana-sport-centre",
            name: "Lavana Sport Centre",
            location: Coordinate(latitude: 3.202641, longitude: 101.718247),
            address: PostalAddress(street: "Jalan Danau Niaga 1", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "53300", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/919070111
        BadmintonCourt(
            id: "v-my-pusat-sukan-desa-petaling",
            name: "Pusat Sukan Desa Petaling",
            location: Coordinate(latitude: 3.082331, longitude: 101.705129),
            address: PostalAddress(street: "1036 Jalan 3/125D", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "56000", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/1036299476
        BadmintonCourt(
            id: "v-my-victor-arena-rawang",
            name: "Victor Arena Rawang",
            location: Coordinate(latitude: 3.311462, longitude: 101.578840),
            address: PostalAddress(street: "Jalan LKS 1", city: "Selayang", region: "Selangor", postalCode: "48000", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/1193317630
        BadmintonCourt(
            id: "v-my-setapak-badminton-center",
            name: "Setapak Badminton Center",
            aliases: ["GYM Box"],
            location: Coordinate(latitude: 3.197497, longitude: 101.723694),
            address: PostalAddress(street: "Jalan Usahawan 6", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "53300", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/1246812256
        BadmintonCourt(
            id: "v-my-ara-courts-badminton-hall",
            name: "Ara Courts Badminton Hall",
            location: Coordinate(latitude: 3.127686, longitude: 101.610109),
            address: PostalAddress(street: "997 Jalan Dahlia", city: "Petaling Jaya", region: "Selangor", postalCode: "47400", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/1246812260
        BadmintonCourt(
            id: "v-my-arena-sukan-champion",
            name: "Arena Sukan Champion",
            location: Coordinate(latitude: 3.126601, longitude: 101.609421),
            address: PostalAddress(street: "Lot 1020, Jalan Cempaka", city: "Petaling Jaya", region: "Selangor", postalCode: "47400", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/1279824084
        BadmintonCourt(
            id: "v-my-x-park-pj-south",
            name: "X Park PJ South",
            location: Coordinate(latitude: 3.078429, longitude: 101.639794),
            address: PostalAddress(street: "Jalan PJS 3/25", city: "Petaling Jaya", region: "Selangor", postalCode: "46050", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/1304541385
        BadmintonCourt(
            id: "v-my-w-badminton-pickleball-centre",
            name: "W Badminton Pickleball Centre",
            location: Coordinate(latitude: 3.200982, longitude: 101.689209),
            address: PostalAddress(street: "Jalan Sentul Harmoni", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "51100", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM way/1545111667
        BadmintonCourt(
            id: "v-my-arena-badminton-dbkl-cheras",
            name: "Arena Badminton DBKL Cheras",
            location: Coordinate(latitude: 3.119686, longitude: 101.726539),
            address: PostalAddress(street: "Jalan 92C", city: "Kuala Lumpur", region: "Kuala Lumpur", postalCode: "51500", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        ),
        // OSM relation/17228533
        BadmintonCourt(
            id: "v-my-tt-sports-centre",
            name: "TT Sports Centre",
            location: Coordinate(latitude: 3.085859, longitude: 101.626064),
            address: PostalAddress(street: "Lot 29E, Lorong Tandang B", city: "Petaling Jaya", region: "Selangor", postalCode: "46050", countryCode: "MY"),
            timeZoneId: "Asia/Kuala_Lumpur",
            source: .openStreetMap,
            status: .unconfirmed
        )
    ]
}
