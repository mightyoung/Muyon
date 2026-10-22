package com.mightyoung.muyon.product.agentipc

import java.io.File

/** Debug-only, non-exported fixture. Same Service/Runtime/FFI/owner; separate synthetic DB.
 * No intent or model parameter can enable this on the normal ProductService. */
class BotNativeAcceptanceService : ProductService() {
    override val workspace: String get() = "bot-native-acceptance"
    override fun nativeStorageRoot(): File = File(filesDir, "bot-native-acceptance-fixture")
    override fun localDraftPortVerifiedForBuild(): Boolean = true
}
