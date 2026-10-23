"""Compiler-only CI. No exclusions, model/native inputs, APKs or runtime tasks."""
import json
import os
from pathlib import Path
import re
import subprocess


TARGETS = (
    ":app:compileDebugKotlin",
    ":app:compileDebugAndroidTestKotlin",
    ":app:compileDebugUnitTestKotlin",
)
# Positive list of standard AGP/Kotlin compiler prerequisites. Unknown tasks HOLD.
# package*Resources/ManifestForPackage are resource intermediates, never APK tasks.
ALLOWED = {
    ":app:" + name
    for name in (
        "preBuild", "preDebugBuild", "preDebugAndroidTestBuild", "preDebugUnitTestBuild",
        "checkKotlinGradlePluginConfigurationErrors", "checkDebugAarMetadata",
        "checkDebugAndroidTestAarMetadata", "generateDebugBuildConfig",
        "generateDebugAndroidTestBuildConfig", "compileDebugAidl",
        "compileDebugAndroidTestAidl", "generateDebugResValues",
        "generateDebugAndroidTestResValues", "mapDebugSourceSetPaths",
        "mapDebugAndroidTestSourceSetPaths", "generateDebugResources",
        "generateDebugAndroidTestResources", "mergeDebugResources",
        "mergeDebugAndroidTestResources", "packageDebugResources",
        "packageDebugAndroidTestResources", "parseDebugLocalResources",
        "parseDebugAndroidTestLocalResources", "createDebugCompatibleScreenManifests",
        "extractDeepLinksDebug", "processDebugMainManifest", "processDebugManifest",
        "processDebugManifestForPackage", "processDebugAndroidTestManifest",
        "processDebugResources", "processDebugAndroidTestResources",
        "generateDebugRFile", "generateDebugAndroidTestRFile", "javaPreCompileDebug",
        "javaPreCompileDebugAndroidTest", "javaPreCompileDebugUnitTest",
        "compileDebugKotlin", "compileDebugJavaWithJavac",
        "bundleDebugClassesToCompileJar", "compileDebugAndroidTestKotlin",
        "compileDebugUnitTestKotlin",
    )
}


def validate_graph(paths, target):
    if not isinstance(paths, list) or not paths or target not in paths:
        raise ValueError("missing actual requested target in task graph")
    unknown = [path for path in paths if path not in ALLOWED]
    if unknown:
        raise ValueError("HOLD: forbidden or unreviewed tasks: " + repr(unknown))


def run(command, log, env):
    print("COMMAND " + json.dumps(command), flush=True)
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, env=env)
        for line in process.stdout:
            print(line, end="", flush=True)
            output.write(line)
        return process.wait()


def main():
    root = Path(__file__).resolve().parents[2]
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or sha != os.environ["GITHUB_SHA"]:
        raise ValueError("checkout does not equal immutable event SHA")
    temporary = Path(os.environ["RUNNER_TEMP"])
    directory = temporary / "android-compile-evidence"
    directory.mkdir(exist_ok=True)
    status_path = temporary / "android-compile-status.json"
    status = {"source_sha": sha, "compile_only": True,
              "targets": {target: {"dry_run": "NOT_RUN", "online": "NOT_RUN", "offline": "NOT_RUN"}
                          for target in TARGETS}}

    def save():
        status_path.write_text(json.dumps(status, indent=2) + "\n")

    save()
    guard = directory / "task-graph-guard.gradle"
    # Runs before any task action, for both dry run and actual compilation. The
    # actual graph must equal the previously reviewed dry-run graph exactly.
    guard.write_text('''import groovy.json.JsonOutput
import groovy.json.JsonSlurper
gradle.taskGraph.whenReady { graph ->
    def paths = graph.allTasks.collect { it.path }
    println('COMPILE_ONLY_GRAPH ' + JsonOutput.toJson(paths))
    new File(System.getenv('MUYON_GRAPH_OUT')).text = JsonOutput.toJson(paths)
    def allowed = new JsonSlurper().parseText(System.getenv('MUYON_GRAPH_ALLOWED'))
    def unknown = paths.findAll { !allowed.contains(it) }
    if (!unknown.isEmpty()) throw new GradleException('COMPILE_ONLY_HOLD: ' + unknown)
    def expected = System.getenv('MUYON_GRAPH_EXPECTED')
    if (expected && paths != new JsonSlurper().parse(new File(expected)))
        throw new GradleException('COMPILE_ONLY_HOLD: graph changed after dry run')
}
''')
    base = [os.environ["MUYON_UI_GRADLE"], "--no-daemon", "--console=plain", "--max-workers=2",
            "-Pandroid.builder.sdkDownload=false", "-p", str(root / "apps/muyon_android"),
            "--init-script", str(guard)]
    for target in TARGETS:
        entry = status["targets"][target]
        name = target.rsplit(":", 1)[1]
        graph_path = directory / (name + "-graph.json")
        env = dict(os.environ, MUYON_GRAPH_OUT=str(graph_path),
                   MUYON_GRAPH_ALLOWED=json.dumps(sorted(ALLOWED)))
        env.pop("MUYON_GRAPH_EXPECTED", None)
        entry["dry_run"] = run(base + ["--dry-run", target], directory / (name + "-dry-run.log"), env)
        save()
        if entry["dry_run"] != 0:
            return 1
        paths = json.loads(graph_path.read_text())
        print("REVIEWED_GRAPH " + json.dumps(paths), flush=True)
        validate_graph(paths, target)
        env["MUYON_GRAPH_EXPECTED"] = str(graph_path)
        # Actual runs emit their graph elsewhere so they cannot overwrite the
        # dry-run witness before the equality check.
        env["MUYON_GRAPH_OUT"] = str(directory / (name + "-actual-graph.json"))
        online_log = directory / (name + "-online.log")
        entry["online"] = run(base + [target], online_log, env)
        save()
        text = online_log.read_text()
        # Do not retry an unprovisioned plugin/dependency cache offline. A source
        # compiler error may still permit a truthful same-cache offline failure.
        resolved = entry["online"] == 0 or (
            ("> Task " + target) in text and
            not any(error in text for error in ("Could not resolve", "Could not GET", "Could not find")))
        if resolved:
            entry["offline"] = run(base + ["--offline", "--rerun-tasks", target],
                                   directory / (name + "-offline.log"), env)
            save()
        if entry["online"] != 0 or entry["offline"] != 0:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
