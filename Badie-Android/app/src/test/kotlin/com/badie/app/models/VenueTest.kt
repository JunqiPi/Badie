package com.badie.app.models

import com.badie.app.remote.RemoteJSON
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** 球馆：地址格式、营业时间、价格、确认升级、国家、金额、手机号。对应 iPhone 的 VenueTests 里只用模型的部分 */
class VenueTest {
    private val la = Coordinate(34.0686, -118.0276)

    private fun venue(id: String, status: VenueStatus = VenueStatus.Verified) = Venue(
        id, "Test", lat = la.latitude, lon = la.longitude, street = "1 Main St", city = "El Monte", region = "CA",
        postalCode = "91731", countryCode = "US", timeZoneId = "America/Los_Angeles", status = status,
    )

    // MARK: Address

    @Test
    fun usAddressFormatting() {
        val address = PostalAddress.create("4800 Rivergrade Rd", "Unit B", "Baldwin Park", "CA", "91706", "us")
        assertEquals("4800 Rivergrade Rd, Unit B", address.streetLine)
        assertEquals("Baldwin Park, CA 91706", address.cityLine)
        assertEquals("4800 Rivergrade Rd, Unit B, Baldwin Park, CA", address.compactLine)
        assertEquals("4800 Rivergrade Rd, Unit B, Baldwin Park, CA 91706", address.singleLine)
        assertEquals("US", address.countryCode)
        assertTrue(address.isComplete)
        assertNull("空白的单元算没有", PostalAddress.create(" 1 Main St ", "  ", "El Monte", "CA", countryCode = "US").unit)
    }

    @Test
    fun chineseAddressIsLargeToSmall() {
        val address = PostalAddress.create("工体北路4号", city = "朝阳区", region = "北京市", countryCode = "CN")
        assertEquals("北京市朝阳区工体北路4号", address.singleLine)
        assertEquals("朝阳区工体北路4号", address.compactLine)
    }

    @Test
    fun incompleteAddressIsRejected() {
        assertFalse(PostalAddress.create("", city = "El Monte", region = "CA", countryCode = "US").isComplete)
    }

    // MARK: Country, money, phone

    @Test
    fun moneyFormatting() {
        assertEquals("$17", Money.format(17, "USD"))
        assertEquals("¥80", Money.format(80, "CNY"))
        assertEquals("RM15", Money.format(15, "MYR"))
        assertEquals("XYZ 5", Money.format(5, "XYZ"))
    }

    @Test
    fun phoneNumbersPerCountry() {
        val us = CountryInfo.info("US")
        val typed = PhoneNumber(us, "(626) 555-0123")
        assertTrue(typed.isValid)
        assertEquals("+16265550123", typed.e164)
        assertEquals("+1 626 555 0123", typed.display)
        assertEquals("+1 626 *** 0123", typed.masked)
        assertEquals("允许带国家码 1 输入", "+16265550123", PhoneNumber(us, "1 626 555 0123").e164)
        assertFalse(PhoneNumber(us, "026 555 0123").isValid)

        val cn = CountryInfo.info("CN")
        assertTrue(PhoneNumber(cn, "13800001234").isValid)
        assertEquals("CN", PhoneNumber.parse("+8613800001234")?.country?.code)
        assertEquals("+86 138 0000 1234", PhoneNumber(cn, "13800001234").display)

        val japanese = PhoneNumber(CountryInfo.info("JP"), "090-1234-5678")
        assertEquals("去掉国内前缀 0", "+819012345678", japanese.e164)
        assertTrue(japanese.isValid)

        assertEquals("最长国家码优先", "HK", PhoneNumber.parse("+85251234567")?.country?.code)
        assertNull(PhoneNumber.parse("+999123"))
        assertEquals("旧数据：不带国家码的大陆手机号", "CN", PhoneNumber.parse("13800001234")?.country?.code)
    }

    @Test
    fun countryInfo() {
        assertEquals("🇺🇸", CountryInfo.info("us").flag)
        assertEquals("美国", CountryInfo.info(null).nameZh)
        assertEquals(AddressStyle.LargeToSmall, AddressStyle.of("JP"))
        val generic = CountryInfo.info("BR")
        assertEquals("BRL", generic.currencyCode)
        assertEquals("", generic.callingCode)
        assertTrue(generic.phone.isValid("123456"))
        assertEquals(15, CountryInfo.info("CN").shuttleFee(GameMode.Doubles))
        assertEquals(0, CountryInfo.info("JP").shuttleFee(GameMode.Singles))
    }

    @Test
    fun venueCurrencyAndShuttleFollowCountry() {
        val us = venue("us")
        assertEquals("USD", us.currency)
        assertEquals(NavigationApp.AppleMaps, us.country.navigationApps.first())
        assertTrue(NavigationApp.GoogleMaps in us.country.navigationApps)
        val beijing = Venue("cn", "北京", lat = 39.9, lon = 116.4, countryCode = "CN")
        assertEquals("CNY", beijing.currency)
        assertEquals(NavigationApp.Amap, beijing.country.navigationApps.first())
        assertEquals("1 Main St, El Monte, CA 91731", us.address)
    }

    @Test
    fun confirmationsPromoteStatus() {
        var added = venue("new", VenueStatus.Unconfirmed)
        added = added.addingConfirmation("a", 1).addingConfirmation("a", 2).addingConfirmation("b", 3)
        assertEquals(VenueStatus.Unconfirmed, added.status)
        added = added.addingConfirmation("c", 4)
        assertEquals(VenueStatus.Confirmed, added.status)
        assertEquals(listOf("a", "b", "c"), added.confirmedBy)
        assertEquals(4L, added.lastConfirmedAt)
    }

    // MARK: 营业时间、价格

    @Test
    fun operatingHoursCoverSlotsInVenueTime() {
        val zone = ZoneId.of("America/Los_Angeles")
        val hours = OperatingHours(8, 0, 22, 0, listOf(2, 3, 4, 5, 6))
        val wednesday = ZonedDateTime.of(2026, 11, 11, 0, 0, 0, 0, zone).toInstant().toEpochMilli()
        assertTrue(hours.covers(TimeSlot.on(wednesday, startHour = 19, endHour = 21, zone = zone)!!, zone))
        assertFalse("关门以后", hours.covers(TimeSlot.on(wednesday, startHour = 21, endHour = 23, zone = zone)!!, zone))
        assertFalse("跨午夜", hours.covers(TimeSlot.on(wednesday, startHour = 21, endHour = 24, zone = zone)!!, zone))
        val saturday = addingDays(wednesday, 3, zone)
        assertFalse("周末不开", hours.covers(TimeSlot.on(saturday, startHour = 10, endHour = 12, zone = zone)!!, zone))
        assertEquals("周一至周五", hours.formattedDaysOpen)
        assertEquals("08:00 – 22:00", hours.formattedTimeRange)
        assertEquals("每天", OperatingHours.standard.formattedDaysOpen)
        assertEquals("周二、周四和周六", OperatingHours(8, 0, 22, 0, listOf(7, 3, 5)).formattedDaysOpen)
        val venue = venue("v").copy(operatingHours = hours)
        assertTrue(venue.isOpen(TimeSlot.on(wednesday, startHour = 19, endHour = 21, zone = zone)!!))
        assertEquals("营业时间未知", venue("x").hoursText)
    }

    @Test
    fun pricingText() {
        assertEquals("$28/场·时", VenuePricing.PerCourtHour(28).text("USD"))
        assertEquals("免费", VenuePricing.DropIn(0).text("USD"))
        assertEquals("¥30/人次", VenuePricing.DropIn(30).text("CNY"))
        assertEquals("价格未知", VenuePricing.Unknown.text("USD"))
        assertFalse(VenuePricing.Unknown.isKnown)
    }

    @Test
    fun decodesServerRows() {
        val row = """{"id":"v-1","name":"Sun","lat":34.1,"lon":-118.1,"country_code":"US","status":"unconfirmed",
            "source":"apple_maps","pricing":{"perPerson":14.5},"created_at":"2026-10-17T23:17:25+00","court_count":6}"""
        val venue = RemoteJSON.decode<Venue>(row.toByteArray())
        assertEquals(VenueStatus.Unconfirmed, venue.status)
        assertEquals(VenueSource.AppleMaps, venue.source)
        assertEquals("按人次取整", VenuePricing.DropIn(15), venue.pricing)
        assertEquals(1_792_279_045_000L, venue.createdAt)
        assertEquals(6, venue.courtCount)
        val court = RemoteJSON.decode<Venue>("""{"id":"v","name":"x","lat":0,"lon":0,"country_code":"CN","status":"odd","source":"player","pricing":{"perCourtHour":80}}""".toByteArray())
        assertEquals("不认识的状态按待确认", VenueStatus.Unconfirmed, court.status)
        assertEquals(VenuePricing.PerCourtHour(80), court.pricing)
        assertEquals(VenuePricing.Unknown, RemoteJSON.decode<Venue>("""{"id":"v","name":"x","lat":0,"lon":0,"country_code":"US","pricing":null}""".toByteArray()).pricing)
        assertEquals("open_data", VenueSource.OpenData.serverValue)
        assertEquals(VenueSource.Player, VenueSource.ofServer("whatever"))
    }

    @Test
    fun nearestPrefersListedVenues() {
        val near = venue("near", VenueStatus.Unconfirmed)
        val listed = venue("listed").copy(lat = la.latitude + 2.0 / 111)
        assertEquals("listed", Venue.nearest(listOf(near, listed), la, 10.0)?.id)
        assertNotNull(Venue.nearest(listOf(near), la, 10.0))
        assertTrue(UserPreferences.default.isValidTravelRadius(10.0))
        assertFalse(UserPreferences.default.isValidTravelRadius(60.0))

        val park = venue("v-park", VenueStatus.Unconfirmed).copy(facility = VenueFacility.Outdoor)
        val hall = venue("v-hall", VenueStatus.Unconfirmed).copy(lat = la.latitude + 3.0 / 111)
        assertEquals("都待确认时先选室内的", "v-hall", Venue.nearest(listOf(park, hall), la, 10.0)?.id)
        assertEquals("只有露天场地就用它", "v-park", Venue.nearest(listOf(park), la, 10.0)?.id)
    }

    @Test
    fun facilityComesFromTheKindColumn() {
        assertEquals(VenueFacility.MultiSport, VenueFacility.ofServer("multi_sport"))
        assertEquals(VenueFacility.Outdoor, VenueFacility.ofServer("outdoor"))
        assertNull(VenueFacility.ofServer("whatever"))
        fun decode(kind: String) = RemoteJSON.decode<Venue>("""{"id":"v","name":"x","lat":0,"lon":0,"country_code":"US","kind":$kind}""".toByteArray())
        assertEquals(VenueFacility.Outdoor, decode("\"outdoor\"").facility)
        assertEquals(VenueFacility.CommunityHall, decode("\"community_hall\"").facility)
        assertNull("不认识的类型不影响读这家球馆", decode("\"rooftop\"").facility)
        assertNull(decode("null").facility)
        assertEquals("露天场地", VenueFacility.Outdoor.title)
    }
}
