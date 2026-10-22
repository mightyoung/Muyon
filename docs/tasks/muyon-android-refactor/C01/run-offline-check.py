"""Compile/run the product transport's memory-stream checks, without Gradle/network."""
import glob
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
BASE = pathlib.Path.home() / ".gradle/caches/modules-2/files-2.1"
PATTERNS = [
    "org.jetbrains.kotlin/kotlin-compiler-embeddable/2.2.20/*/*.jar",
    "org.jetbrains.kotlin/kotlin-stdlib/2.2.20/*/*.jar",
    "org.jetbrains.kotlin/kotlin-script-runtime/2.2.20/*/*.jar",
    "org.jetbrains.kotlin/kotlin-reflect/1.6.10/*/*.jar",
    "org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.8.0/*/*.jar",
    "org.jetbrains/annotations/13.0/*/*.jar",
]
jars = [path for pattern in PATTERNS for path in glob.glob(str(BASE / pattern))]
stdlib = next(path for path in jars if "/kotlin-stdlib/" in path)
java = "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java"
output = "/private/tmp/muyon-chat-offline-check.jar"
source = "apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/"
compiler = [java, "--enable-native-access=ALL-UNNAMED", "-cp", ":".join(jars),
            "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler", "-no-stdlib", "-no-reflect"]
result = subprocess.run(compiler + ["-classpath", stdlib, "-d", output,
    source + "ProductHttpsTransport.kt", source + "ProductSendGate.kt", "docs/tasks/muyon-android-refactor/C01/ProductChatOfflineCheck.kt"], cwd=ROOT)
print("transport_compile_exit", result.returncode, flush=True)
if result.returncode:
    sys.exit(result.returncode)
result = subprocess.run([java, "-cp", output + ":" + stdlib,
    "com.mightyoung.muyon.product.chat.ProductChatOfflineCheckKt"] + sys.argv[1:], cwd=ROOT)
print("transport_run_exit", result.returncode, flush=True)
if result.returncode:
    sys.exit(result.returncode)
sdk = str(pathlib.Path.home() / "Library/Android/sdk/platforms/android-36/android.jar")
result = subprocess.run(compiler + ["-jvm-target", "17", "-classpath", stdlib + ":" + sdk,
    "-d", "/private/tmp/muyon-chat-runtime-check.jar", source + "ProductHttpsTransport.kt",
    source + "ProductChatRuntime.kt", source + "ProductSendGate.kt"], cwd=ROOT)
print("runtime_compile_exit", result.returncode, flush=True)
sys.exit(result.returncode)
