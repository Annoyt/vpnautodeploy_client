package com.follow.clash.plugins

internal object NekoNetstat {
    const val WIFI = "wifi"
    const val CELL = "cell"
    const val OTHER = "other"
    const val GSM = "gsm"
    const val UMTS = "umts"
    const val LTE = "lte"
    const val NR = "nr"
    const val UNKNOWN = "unknown"
    const val RU_URL = "https://ya.ru/"
    const val PROBE_TIMEOUT_MILLIS = 5_000
    const val MAX_LOCATION_AGE_MILLIS = 30 * 60 * 1000L

    private val RANK = listOf(WIFI, CELL, OTHER)
    private val NEWEST_FIRST = listOf(NR, LTE, UMTS, GSM)

    data class Candidate(val index: Int, val net: String, val validated: Boolean)

    data class Cell(
        val rat: String,
        val registered: Boolean,
        val tac: Long?,
        val cid: Long?,
        val pci: Long?,
        val channel: Long?,
        val mcc: String?,
        val mnc: String?,
        val level: Int?,
    )

    private data class Limits(val tac: Long, val cid: Long, val pci: Long, val channel: Long)

    // Android marks a missing number with Int.MAX_VALUE (Long.MAX_VALUE for
    // NR's cell identity), which these maxima turn into null.
    private val LIMITS = mapOf(
        GSM to Limits(tac = 0xFFFFL, cid = 0xFFFFL, pci = 63L, channel = 1023L),
        UMTS to Limits(tac = 0xFFFFL, cid = 0xFFFFFFFL, pci = 511L, channel = 16383L),
        LTE to Limits(tac = 0xFFFFL, cid = 0xFFFFFFFL, pci = 503L, channel = 262143L),
        NR to Limits(tac = 0xFFFFFFL, cid = 0xFFFFFFFFFL, pci = 1007L, channel = 3279165L),
    )

    fun net(wifi: Boolean, cellular: Boolean): String = when {
        wifi -> WIFI
        cellular -> CELL
        else -> OTHER
    }

    fun pick(candidates: List<Candidate>, carried: Set<String>): Candidate? =
        candidates.sortedWith(
            compareByDescending<Candidate> { it.validated }
                .thenByDescending { it.net in carried }
                .thenBy { RANK.indexOf(it.net) },
        ).firstOrNull()

    fun operator(numeric: String?): Pair<String?, String?> {
        if (numeric == null || numeric.length !in 5..6 || !numeric.all { it in '0'..'9' }) {
            return null to null
        }
        return numeric.substring(0, 3) to numeric.substring(3)
    }

    fun signalLevel(raw: Int?): Int? = if (raw == null || raw < 0) null else minOf(raw, 4)

    // Android's own steps for Wi-Fi, from -100 dBm up to -55 dBm.
    fun wifiLevel(rssi: Int?): Int? = when {
        rssi == null || rssi == Int.MIN_VALUE || rssi >= 0 -> null
        rssi <= -100 -> 0
        rssi >= -55 -> 4
        else -> (rssi + 100) * 4 / 45
    }

    fun ratOf(rats: Collection<String>): String = NEWEST_FIRST.firstOrNull { it in rats } ?: UNKNOWN

    fun cell(
        rat: String,
        registered: Boolean,
        tac: Long,
        cid: Long,
        pci: Long,
        channel: Long,
        mcc: String?,
        mnc: String?,
        level: Int?,
    ): Cell? {
        val limits = LIMITS[rat] ?: return null
        return Cell(
            rat = rat,
            registered = registered,
            tac = tac.takeIf { it in 0..limits.tac },
            cid = cid.takeIf { it in 0..limits.cid },
            pci = pci.takeIf { it in 0..limits.pci },
            channel = channel.takeIf { it in 0..limits.channel },
            mcc = mcc?.takeIf { it.length == 3 && it.all { c -> c in '0'..'9' } },
            mnc = mnc?.takeIf { it.length in 2..3 && it.all { c -> c in '0'..'9' } },
            level = signalLevel(level),
        )
    }

    fun serving(cells: List<Cell>, mcc: String?, mnc: String?): Cell? {
        val registered = cells.filter { it.registered }
        return registered.firstOrNull { mcc != null && it.mcc == mcc && it.mnc == mnc }
            ?: registered.firstOrNull()
    }

    fun fresh(ageMillis: Long): Boolean = ageMillis in 0..MAX_LOCATION_AGE_MILLIS

    // lib/neko/netstat.dart reads this map: one set of cell names for every radio.
    fun snapshot(
        net: String,
        level: Int?,
        mcc: String?,
        mnc: String?,
        rat: String,
        cell: Cell?,
        lat: Double?,
        lon: Double?,
    ): Map<String, Any?> = mapOf(
        "net" to net,
        "level" to level,
        "mcc" to mcc,
        "mnc" to mnc,
        "rat" to rat,
        "cell" to cell?.let {
            mapOf("tac" to it.tac, "cid" to it.cid, "pci" to it.pci, "earfcn" to it.channel)
        },
        "lat" to lat,
        "lon" to lon,
    )
}
