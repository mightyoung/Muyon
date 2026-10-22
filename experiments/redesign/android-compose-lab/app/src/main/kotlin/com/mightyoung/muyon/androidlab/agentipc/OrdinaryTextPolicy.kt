package com.mightyoung.muyon.androidlab.agentipc

/** Finite USER-TEXT-v1/MODEL-TEXT-v1 mirror for trusted owner proofs.
 * Exact UTF-8, no silent normalization, no claim to detect arbitrary unlabeled secrets.
 */
internal fun ordinaryTextSupported(text:String):Boolean {
    if(text.isBlank() || text.toByteArray(Charsets.UTF_8).size>4096)return false
    if(text.any{(it.isISOControl() && it!='\n' && it!='\t') || it.code in 0x300..0x36f || it.code in 0x200b..0x200f || it.code in 0x202a..0x202e || it.code in 0x2060..0x206f || it.code in 0xfffe..0xffff || it.isSurrogate()})return false
    val lower=text.lowercase(java.util.Locale.ROOT)
    return listOf("sk-","bearer ","api_key","api-key","apikey","password","private key","secret","token=","token:","密钥","密码").none{lower.contains(it)}
}
