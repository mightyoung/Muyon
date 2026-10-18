package com.mightyoung.muyon.ocr

import com.paddle.ocr.model.ModelConfig
import com.paddle.ocr.postprocess.CTCDecoder
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class UpstreamTest {
    @Test fun locked_dictionaries_match_full_yaml_parser_codepoints_and_model_classes() {
        val method=ModelConfig.Companion.javaClass.getDeclaredMethod("extractCharacterDict",String::class.java,String::class.java)
        method.isAccessible=true
        for((name,count,digest) in listOf(
            Triple("tiny",6906,"80a3093e08495cb5d5aadcfe6ee213aa9047b2ece5880ca36ecbe09de23c7bdb"),
            Triple("small",18710,"14966c40e5be1217ae7c05515103b8091a4beea7b5527f03fcbccf03b41b27df"))) {
            val file=File("fixtures/$name-rec.yml")
            @Suppress("UNCHECKED_CAST")
            val chars=(method.invoke(ModelConfig.Companion,file.readText(),file.name) as List<String>).toMutableList()
            if(chars.lastOrNull()!=" ") chars.add(" ")
            assertEquals(count,chars.size+1)
            assertEquals(digest,sha(chars.joinToString("\u0000").toByteArray(Charsets.UTF_8)))
        }
    }
    @Test fun official_ctc_preserves_blank_separated_repeats_and_unicode_characters() {
        val indices=listOf(1,1,0,1,2,3,3)
        val output=FloatArray(indices.size*4)
        indices.forEachIndexed { t,c -> output[t*4+c]=0.95f }
        val (text,score)=CTCDecoder.decode(output,longArrayOf(1,7,4),listOf("中","文","😀")).single()
        assertEquals("中中文😀",text);assertEquals(0.95f,score,0.00001f)
    }
}
