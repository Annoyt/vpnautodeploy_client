package com.follow.clash.service

import com.follow.clash.service.modules.NekoMultipath
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class NekoMultipathTest {
    private fun modeOf(text: String?): String {
        val file = File.createTempFile("neko_multipath", ".json")
        try {
            if (text == null) file.delete() else file.writeText(text)
            return NekoMultipath.readMode(file)
        } finally {
            file.delete()
        }
    }

    @Test
    fun `reads the mode the app wrote`() {
        assertEquals("distribute", modeOf("""{"mode":"distribute"}"""))
        assertEquals("failover", modeOf("""{ "mode" : "failover" }"""))
        assertEquals("off", modeOf("""{"mode":"off"}"""))
    }

    @Test
    fun `anything else is off`() {
        assertEquals("off", modeOf(null))
        assertEquals("off", modeOf(""))
        assertEquals("off", modeOf("""{"mode":"turbo"}"""))
        assertEquals("off", modeOf("not json"))
    }

    @Test
    fun `the report is what the core reads`() {
        val report = NekoMultipath.report(
            "distribute",
            listOf(
                NekoMultipath.Entry(handle = 431L, transport = "wifi", validated = true),
                NekoMultipath.Entry(handle = 862L, transport = "cellular", validated = false),
            ),
        )
        assertEquals(
            """{"mode":"distribute","networks":[""" +
                """{"handle":431,"transport":"wifi","validated":true},""" +
                """{"handle":862,"transport":"cellular","validated":false}]}""",
            report,
        )
        assertEquals("""{"mode":"off","networks":[]}""", NekoMultipath.report("turbo", emptyList()))
    }
}
