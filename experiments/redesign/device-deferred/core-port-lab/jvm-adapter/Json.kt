package muyon.rd.p05c

/** Transport-only JSON. Business counters are never converted to JSON numbers. */
data class JsonNumber(val token: String)
object Json {
    private val number=Regex("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
    fun parse(text: String): Any? = Parser(text).parse()
    fun stringify(value: Any?): String = when(value) {
        null->"null"
        is String->buildString {
            append('"');value.forEach { c->when(c) {
                '"'->append("\\\"");'\\'->append("\\\\");'\n'->append("\\n");'\r'->append("\\r");'\t'->append("\\t")
                else->if(c.code<32 || c.isSurrogate()) append("\\u"+c.code.toString(16).padStart(4,'0')) else append(c)
            }};append('"')
        }
        is Boolean->value.toString()
        is Int->value.toString()
        is Long->value.toString()
        is JsonNumber->{require(number.matches(value.token));value.token}
        is List<*>->value.joinToString(prefix="[",postfix="]",separator=",") {stringify(it)}
        is Map<*,*>->value.entries.joinToString(prefix="{",postfix="}",separator=",") {require(it.key is String);stringify(it.key)+":"+stringify(it.value)}
        else->error("Unsupported JSON transport type")
    }
    private class Parser(private val text:String) {
        private var at=0
        fun parse():Any? {val result=value(0);space();require(at==text.length){"Trailing JSON"};return result}
        private fun space(){while(at<text.length && text[at] in " \n\r\t") at++}
        private fun take(char:Char):Boolean {space();if(at<text.length && text[at]==char){at++;return true};return false}
        private fun value(depth:Int):Any? {
            require(depth<=32){"JSON nesting limit"};space();require(at<text.length){"Missing JSON"}
            return when(text[at]) {
                '"'->string()
                '{'->{at++;val map=linkedMapOf<String,Any?>();if(!take('}')){do {space();require(at<text.length && text[at]=='"');val key=string();require(!map.containsKey(key)){"Duplicate JSON key"};require(take(':'));map[key]=value(depth+1)} while(take(','));require(take('}'))};map}
                '['->{at++;val items=mutableListOf<Any?>();if(!take(']')){do {items.add(value(depth+1))}while(take(','));require(take(']'))};items}
                't'->{literal("true");true};'f'->{literal("false");false};'n'->{literal("null");null}
                else->{val start=at;while(at<text.length && text[at] in "-+0123456789.eE") at++;val token=text.substring(start,at);require(number.matches(token)){"Invalid JSON number"};JsonNumber(token)}
            }
        }
        private fun literal(word:String){require(text.startsWith(word,at));at+=word.length}
        private fun string():String {
            require(text[at++]=='"');val out=StringBuilder()
            while(at<text.length){val c=text[at++];when {
                c=='"'->return out.toString()
                c=='\\'->{require(at<text.length);when(val escaped=text[at++]) {
                    '"','\\','/'->out.append(escaped);'b'->out.append('\b');'f'->out.append('\u000c');'n'->out.append('\n');'r'->out.append('\r');'t'->out.append('\t')
                    'u'->{require(at+4<=text.length);val hex=text.substring(at,at+4);require(hex.all {it in "0123456789abcdefABCDEF"});out.append(hex.toInt(16).toChar());at+=4}
                    else->error("Invalid JSON escape")
                }}
                c.code<32->error("Unescaped JSON control")
                else->out.append(c)
            }}
            error("Unterminated JSON string")
        }
    }
}
