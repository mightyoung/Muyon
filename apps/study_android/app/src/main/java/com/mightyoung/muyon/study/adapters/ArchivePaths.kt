package com.mightyoung.muyon.study.adapters

import java.io.File

/** Models are private app assets; reject archive paths rather than normalizing escape attempts. */
internal object ArchivePaths {
    fun destination(base: File, name: String): File? {
        require(!name.startsWith('/') && '\\' !in name && name.split('/').none { it == ".." || it == "." }) { "Unsafe archive path" }
        require(name.substringBefore('/') == "vosk-model-small-cn-0.22") { "Unexpected model archive root" }
        val relative = name.substringAfter('/', "")
        if(relative.isEmpty()) return null
        return File(base, relative).also { require(it.canonicalPath.startsWith(base.canonicalPath + File.separator)) { "Unsafe archive path" } }
    }
}
