"""Task policy regression checks; these never start Gradle or an Android task."""
import unittest

from tools.ci.android_compile_only import TARGETS, validate_graph


class CompileOnlyGraphTests(unittest.TestCase):
    def test_resource_intermediates_are_not_apk_packaging(self):
        validate_graph([":app:preBuild", ":app:packageDebugResources",
                        ":app:processDebugManifestForPackage", TARGETS[0]], TARGETS[0])

    def test_forbidden_product_gates_packaging_and_runtime_stop_the_route(self):
        for name in ("verifyModelAssets", "verifyProductNativeInputs", "mergeDebugAssets",
                     "mergeDebugNativeLibs", "packageDebug", "assembleDebug", "installDebug",
                     "connectedDebugAndroidTest", "testDebugUnitTest", "customRun", "worker"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                validate_graph([":app:" + name, TARGETS[0]], TARGETS[0])

    def test_unknown_tasks_and_missing_actual_target_fail_closed(self):
        for paths in ([], [":app:preBuild"], [":other:compileDebugKotlin", TARGETS[0]],
                      [":app:packageDebugResourcesExtra", TARGETS[0]]):
            with self.subTest(paths=paths), self.assertRaises(ValueError):
                validate_graph(paths, TARGETS[0])


if __name__ == "__main__":
    unittest.main()
