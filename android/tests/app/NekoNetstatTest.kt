package com.follow.clash.plugins

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NekoNetstatTest {
    private fun lte(
        registered: Boolean = true,
        tac: Long = 7701,
        cid: Long = 123456789,
        mcc: String? = "250",
        mnc: String? = "01",
    ) = NekoNetstat.cell(
        rat = NekoNetstat.LTE,
        registered = registered,
        tac = tac,
        cid = cid,
        pci = 301,
        channel = 1850,
        mcc = mcc,
        mnc = mnc,
        level = 2,
    )!!

    @Test
    fun `the operator splits into MCC and MNC`() {
        assertEquals("250" to "01", NekoNetstat.operator("25001"))
        assertEquals("250" to "020", NekoNetstat.operator("250020"))
        for (junk in listOf(null, "", "2500", "2500123", "25a01", "２５００１")) {
            assertEquals(null to null, NekoNetstat.operator(junk))
        }
    }

    @Test
    fun `the network type`() {
        assertEquals("wifi", NekoNetstat.net(wifi = true, cellular = false))
        assertEquals("wifi", NekoNetstat.net(wifi = true, cellular = true))
        assertEquals("cell", NekoNetstat.net(wifi = false, cellular = true))
        assertEquals("other", NekoNetstat.net(wifi = false, cellular = false))
    }

    @Test
    fun `the network under the VPN`() {
        val wifi = NekoNetstat.Candidate(index = 0, net = "wifi", validated = true)
        val cell = NekoNetstat.Candidate(index = 1, net = "cell", validated = true)
        val brokenWifi = NekoNetstat.Candidate(index = 2, net = "wifi", validated = false)
        val ethernet = NekoNetstat.Candidate(index = 3, net = "other", validated = true)
        assertEquals(wifi, NekoNetstat.pick(listOf(cell, wifi), emptySet()))
        assertEquals(cell, NekoNetstat.pick(listOf(wifi, cell), setOf("cell")))
        assertEquals(cell, NekoNetstat.pick(listOf(brokenWifi, cell), setOf("wifi")))
        assertEquals(cell, NekoNetstat.pick(listOf(ethernet, cell), emptySet()))
        assertNull(NekoNetstat.pick(emptyList(), setOf("wifi")))
    }

    @Test
    fun `signal levels stay within 0 to 4`() {
        assertNull(NekoNetstat.signalLevel(null))
        assertNull(NekoNetstat.signalLevel(-1))
        assertEquals(0, NekoNetstat.signalLevel(0))
        assertEquals(4, NekoNetstat.signalLevel(4))
        assertEquals(4, NekoNetstat.signalLevel(5))
        assertNull(NekoNetstat.wifiLevel(null))
        assertNull(NekoNetstat.wifiLevel(Int.MIN_VALUE))
        assertNull(NekoNetstat.wifiLevel(0))
        assertEquals(0, NekoNetstat.wifiLevel(-120))
        assertEquals(0, NekoNetstat.wifiLevel(-100))
        assertEquals(1, NekoNetstat.wifiLevel(-78))
        assertEquals(3, NekoNetstat.wifiLevel(-56))
        assertEquals(4, NekoNetstat.wifiLevel(-55))
        assertEquals(4, NekoNetstat.wifiLevel(-30))
    }

    @Test
    fun `the newest radio with a signal names the rat`() {
        assertEquals("nr", NekoNetstat.ratOf(listOf("lte", "nr")))
        assertEquals("lte", NekoNetstat.ratOf(listOf("gsm", "lte")))
        assertEquals("umts", NekoNetstat.ratOf(listOf("umts")))
        assertEquals("gsm", NekoNetstat.ratOf(listOf("gsm")))
        assertEquals("unknown", NekoNetstat.ratOf(emptyList()))
    }

    @Test
    fun `a cell keeps what is in range and drops Android's unavailable`() {
        assertEquals(
            NekoNetstat.Cell("lte", true, 7701, 123456789, 301, 1850, "250", "01", 2),
            lte(),
        )
        val unavailable = Int.MAX_VALUE.toLong()
        val lost = NekoNetstat.cell(
            rat = NekoNetstat.LTE,
            registered = true,
            tac = unavailable,
            cid = unavailable,
            pci = unavailable,
            channel = unavailable,
            mcc = null,
            mnc = null,
            level = null,
        )!!
        assertNull(lost.tac)
        assertNull(lost.cid)
        assertNull(lost.pci)
        assertNull(lost.channel)
        val nr = NekoNetstat.cell(
            rat = NekoNetstat.NR,
            registered = true,
            tac = 0xFFFFFF,
            cid = (1L shl 36) - 1,
            pci = 1007,
            channel = 3279165,
            mcc = "2500",
            mnc = "1",
            level = 9,
        )!!
        assertEquals(0xFFFFFFL, nr.tac)
        assertEquals((1L shl 36) - 1, nr.cid)
        assertEquals(1007L, nr.pci)
        assertEquals(3279165L, nr.channel)
        assertNull(nr.mcc)
        assertNull(nr.mnc)
        assertEquals(4, nr.level)
        assertNull(NekoNetstat.cell("nr", true, 1, Long.MAX_VALUE, 1, 1, null, null, null)!!.cid)
        val gsm = NekoNetstat.cell("gsm", true, 7701, 70000, 64, 1024, null, null, null)!!
        assertEquals(7701L, gsm.tac)
        assertNull(gsm.cid)
        assertNull(gsm.pci)
        assertNull(gsm.channel)
        assertNull(NekoNetstat.cell("umts", true, -1, 1, 1, 1, null, null, null)!!.tac)
        assertNull(NekoNetstat.cell("cdma", true, 1, 1, 1, 1, null, null, null))
    }

    @Test
    fun `the serving cell is a registered one on the data SIM's network`() {
        val other = lte(mcc = "250", mnc = "99")
        val ours = lte(cid = 42)
        val neighbour = lte(registered = false, cid = 7)
        assertEquals(ours, NekoNetstat.serving(listOf(neighbour, other, ours), "250", "01"))
        assertEquals(other, NekoNetstat.serving(listOf(neighbour, other), "250", "01"))
        assertEquals(other, NekoNetstat.serving(listOf(other, ours), null, null))
        assertNull(NekoNetstat.serving(listOf(neighbour), "250", "01"))
    }

    @Test
    fun `a location older than half an hour is not the area`() {
        assertTrue(NekoNetstat.fresh(0))
        assertTrue(NekoNetstat.fresh(30 * 60 * 1000L))
        assertFalse(NekoNetstat.fresh(30 * 60 * 1000L + 1))
        assertFalse(NekoNetstat.fresh(-1))
    }

    @Test
    fun `the snapshot is the map lib neko netstat dart reads`() {
        assertEquals(
            mapOf(
                "net" to "cell",
                "level" to 2,
                "mcc" to "250",
                "mnc" to "01",
                "rat" to "lte",
                "cell" to mapOf("tac" to 7701L, "cid" to 123456789L, "pci" to 301L, "earfcn" to 1850L),
                "lat" to 55.7558,
                "lon" to 37.6173,
            ),
            NekoNetstat.snapshot("cell", 2, "250", "01", "lte", lte(), 55.7558, 37.6173),
        )
        assertEquals(
            mapOf(
                "net" to "wifi",
                "level" to null,
                "mcc" to null,
                "mnc" to null,
                "rat" to "unknown",
                "cell" to null,
                "lat" to null,
                "lon" to null,
            ),
            NekoNetstat.snapshot("wifi", null, null, null, "unknown", null, null, null),
        )
    }
}
