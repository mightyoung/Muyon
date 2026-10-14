package muyon.rd.p05c

import java.nio.file.Files
import java.nio.file.Path

fun main(args:Array<String>) {
    require(args.size==4 && args[0]=="--input" && args[2]=="--output"){"--input fixture --output external-report"}
    val input=Path.of(args[1]).toAbsolutePath().normalize()
    val output=Path.of(args[3]).toAbsolutePath().normalize()
    require(output.startsWith(Path.of("/tmp")) || output.startsWith(Path.of("/workspace/reports"))){"External output required"}
    require(Files.size(input)<=1048576){"Input bound"}
    val fixture=Json.parse(Files.readString(input)).objectValue()
    require(fixture.keys==setOf("scenario_id","seed","steps")){"Input-only fixture fields"}
    val seed=when(fixture["seed"]){"baseline"->LabSeed.NORMAL;"lost-reply"->LabSeed.LOST_REPLY;else->error("Unknown owned seed")}
    val fixtures=input.parent
    val seedDocument=Json.parse(Files.readString(fixtures.resolve(seed.file))).objectValue()
    val domain=Domain.from(seedDocument["domain"])
    val steps=fixture["steps"] as? List<*> ?: error("Steps array");require(steps.size<=1000)
    val replies=mutableListOf<Map<String,Any?>>()
    Files.createDirectories(output.parent)
    CorePort.open(seed,fixtures,output.parent.resolve(output.fileName.toString()+".core-stderr.log")).use {port->
        steps.forEachIndexed {index,value->
            val step=value.objectValue();require(step.keys.all {it in setOf("request","plan_id_from")})
            val request=linkedMapOf<String,Any?>("protocol" to 0,"request_id" to "step-$index","domain" to domain.wire(),"display_epoch" to "epoch-0")
            request.putAll(step["request"].objectValue())
            if(step.containsKey("plan_id_from")) {
                require(!request.containsKey("plan_id")){"Ambiguous plan reference"}
                val token=(step["plan_id_from"] as? JsonNumber)?.token ?: error("Plan index integer")
                val from=token.toIntOrNull() ?: error("Plan index integer");require(token==from.toString() && from in 0 until index)
                val plan=replies[from]["plan"].objectValue();request["plan_id"]=plan.text("id")
            }
            replies.add(port.sendFrame(request).wire)
        }
    }
    Files.writeString(output,Json.stringify(mapOf("scenario_id" to fixture.text("scenario_id"),"replies" to replies))+"\n")
}
