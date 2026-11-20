package com.follow.clash.service

import com.follow.clash.service.modules.NekoNetstatSwitch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class NekoNetstatSwitchTest {
    private fun enabledBy(text: String?): Boolean {
        val file = File.createTempFile("neko_netstat_cell", ".json")
        try {
            if (text == null) file.delete() else file.writeText(text)
            return NekoNetstatSwitch.enabled(file)
        } finally {
            file.delete()
        }
    }

    @Test
    fun `reads the switch the app wrote`() {
        assertTrue(enabledBy("""{"enabled":true}"""))
        assertTrue(enabledBy("""{ "enabled" : true }"""))
        assertFalse(enabledBy("""{"enabled":false}"""))
        assertFalse(enabledBy(null))
        assertFalse(enabledBy("not json"))
    }

    @Test
    fun `the location type only for a VPN started in front, switched on and allowed`() {
        val foreground = 100
        val visible = 200
        val foregroundService = 125
        val cached = 400
        fun wants(
            sdk: Int = 34,
            enabled: Boolean = true,
            permitted: Boolean = true,
            importance: Int = foreground,
        ) = NekoNetstatSwitch.wantsLocation(sdk, enabled, permitted, importance)

        assertTrue(wants())
        assertTrue(wants(sdk = 29, importance = visible))
        assertFalse(wants(importance = foregroundService))
        assertFalse(wants(importance = cached))
        assertFalse(wants(sdk = 28))
        assertFalse(wants(enabled = false))
        assertFalse(wants(permitted = false))
    }

    @Test
    fun `special use always, location only on request`() {
        assertEquals(0x40000000, NekoNetstatSwitch.type(location = false))
        assertEquals(0x40000008, NekoNetstatSwitch.type(location = true))
    }
}
