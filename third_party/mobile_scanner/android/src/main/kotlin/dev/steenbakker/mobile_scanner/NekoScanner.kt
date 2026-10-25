// NekoVPN (Annoyt/vpnautodeploy_client), 2026-10-25: barcodes are decoded
// with zxing-cpp (Apache-2.0) instead of Google ML Kit, which is closed source
// and ships Google's telemetry transport (client plan E36). The Dart side
// still speaks ML Kit's format and value-type numbers, so they are kept here.
package dev.steenbakker.mobile_scanner

import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.Rect
import androidx.camera.core.ImageProxy
import zxingcpp.BarcodeReader

/** ML Kit's barcode format values, as the Dart side sends and reads them. */
object NekoFormats {
    const val UNKNOWN = -1
    const val CODE_128 = 1
    const val CODE_39 = 2
    const val CODE_93 = 4
    const val CODABAR = 8
    const val DATA_MATRIX = 16
    const val EAN_13 = 32
    const val EAN_8 = 64
    const val ITF = 128
    const val QR_CODE = 256
    const val UPC_A = 512
    const val UPC_E = 1024
    const val PDF417 = 2048
    const val AZTEC = 4096

    private val toZxing = mapOf(
        CODE_128 to BarcodeReader.Format.CODE_128,
        CODE_39 to BarcodeReader.Format.CODE_39,
        CODE_93 to BarcodeReader.Format.CODE_93,
        CODABAR to BarcodeReader.Format.CODABAR,
        DATA_MATRIX to BarcodeReader.Format.DATA_MATRIX,
        EAN_13 to BarcodeReader.Format.EAN_13,
        EAN_8 to BarcodeReader.Format.EAN_8,
        ITF to BarcodeReader.Format.ITF,
        QR_CODE to BarcodeReader.Format.QR_CODE,
        UPC_A to BarcodeReader.Format.UPC_A,
        UPC_E to BarcodeReader.Format.UPC_E,
        PDF417 to BarcodeReader.Format.PDF_417,
        AZTEC to BarcodeReader.Format.AZTEC,
    )

    /** zxing-cpp formats for the Dart side's list; empty reads every format. */
    fun zxing(formats: List<Int>?): Set<BarcodeReader.Format> =
        formats.orEmpty().mapNotNull { toZxing[it] }.toSet()

    /** The ML Kit value of a zxing-cpp result format. */
    fun mlKit(format: BarcodeReader.Format): Int = when (format) {
        BarcodeReader.Format.CODE_128 -> CODE_128
        BarcodeReader.Format.CODE_39,
        BarcodeReader.Format.CODE_39_STD,
        BarcodeReader.Format.CODE_39_EXT -> CODE_39
        BarcodeReader.Format.CODE_93 -> CODE_93
        BarcodeReader.Format.CODABAR -> CODABAR
        BarcodeReader.Format.DATA_MATRIX -> DATA_MATRIX
        BarcodeReader.Format.EAN_13 -> EAN_13
        BarcodeReader.Format.EAN_8 -> EAN_8
        BarcodeReader.Format.ITF, BarcodeReader.Format.ITF_14 -> ITF
        BarcodeReader.Format.UPC_A -> UPC_A
        BarcodeReader.Format.UPC_E -> UPC_E
        BarcodeReader.Format.PDF_417,
        BarcodeReader.Format.COMPACT_PDF_417,
        BarcodeReader.Format.MICRO_PDF_417 -> PDF417
        BarcodeReader.Format.AZTEC,
        BarcodeReader.Format.AZTEC_CODE,
        BarcodeReader.Format.AZTEC_RUNE -> AZTEC
        // Every QR symbology (model 1/2, micro, rMQR) ends in 'Q' (0x51).
        else -> if (format.value and 0xFF == 0x51) QR_CODE else UNKNOWN
    }
}

/** One decoded barcode, serialized the way the Dart side parses ML Kit's. */
class NekoBarcode(private val result: BarcodeReader.Result) {
    val rawValue: String? get() = result.text

    val cornerPoints: List<Point>
        get() = with(result.position) { listOf(topLeft, topRight, bottomRight, bottomLeft) }

    val boundingBox: Rect
        get() {
            val xs = cornerPoints.map { it.x }
            val ys = cornerPoints.map { it.y }
            return Rect(xs.min(), ys.min(), xs.max(), ys.max())
        }

    val data: Map<String, Any?>
        get() {
            val box = boundingBox
            val text = result.text
            val isUrl = text != null && (text.startsWith("https://") || text.startsWith("http://"))
            return mapOf(
                "calendarEvent" to null,
                "contactInfo" to null,
                "corners" to cornerPoints.map { mapOf("x" to it.x.toDouble(), "y" to it.y.toDouble()) },
                "displayValue" to text,
                "driverLicense" to null,
                "email" to null,
                "format" to NekoFormats.mlKit(result.format),
                "geoPoint" to null,
                "phone" to null,
                "rawBytes" to result.bytes,
                "rawValue" to text,
                "size" to mapOf("width" to box.width().toDouble(), "height" to box.height().toDouble()),
                "sms" to null,
                // ML Kit's value types: 7 = text, 8 = url.
                "type" to if (isUrl) 8 else 7,
                "url" to if (isUrl) mapOf("title" to null, "url" to text) else null,
                "wifi" to null,
            )
        }
}

/** The decoder behind the camera and analyzeImage: zxing-cpp, synchronous. */
class NekoBarcodeScanner(formats: List<Int>?) {
    private val reader = BarcodeReader(
        BarcodeReader.Options(formats = NekoFormats.zxing(formats), tryRotate = true),
    )

    /** Also try the colors inverted (light code on a dark screen). */
    var tryInvert: Boolean
        get() = reader.options.tryInvert
        set(value) {
            reader.options.tryInvert = value
        }

    fun read(image: ImageProxy): List<NekoBarcode> = decoded(reader.read(image))

    fun read(bitmap: Bitmap): List<NekoBarcode> = decoded(reader.read(bitmap))

    private fun decoded(results: List<BarcodeReader.Result>): List<NekoBarcode> =
        results.filter { it.error == null && it.text != null }.map(::NekoBarcode)
}
