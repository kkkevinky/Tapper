"""Run installer branches with fake apps/processes; never touch /Applications or UI."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class ScriptWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tapper script tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        self.apps = self.root / "Applications"
        self.apps.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "actions"
        for name in ["test-and-install.sh", "install-final.sh", "quick-test.sh", "debug-run.sh"]:
            text = (REPO / name).read_text().replace("/Applications", str(self.apps))
            text = text.replace("/usr/libexec/PlistBuddy", str(self.bin / "PlistBuddy"))
            # Quote the fixture path as the real absolute tool path has no spaces.
            text = text.replace(str(self.bin / "PlistBuddy"), '"' + str(self.bin / "PlistBuddy") + '"')
            (self.project / name).write_text(text)
        self.command("PlistBuddy", "echo 1.2")
        self.command("codesign", 'echo verify >> "$ACTION_LOG"; if [[ "${FAIL_VERIFY:-}" == yes && "$*" == *Tapper-install* ]]; then exit 1; fi')
        self.command("pgrep", '[[ -f "$PROCESS_STATE/$2" ]]')
        self.command("killall", 'echo "stop $1" >> "$ACTION_LOG"; if [[ "${HOLD_PROCESS:-}" != yes ]]; then rm -f "$PROCESS_STATE/$1"; fi')
        self.command("sleep", ":")
        self.command("open", 'echo "open $*" >> "$ACTION_LOG"')
        self.command("ditto", 'cp -R "$1" "$2"')
        self.command("mv", 'if [[ "${FAIL_MOVE:-}" == yes && "$1" == *Tapper-install*/Tapper.app ]]; then exit 1; fi; /bin/mv "$@"')
        for script, app, executable in [("build.sh", "Tapper", "Tapper"), ("build-debug.sh", "Tapper_Debug", "Tapper_Debug")]:
            (self.project / script).write_text(f"""#!/bin/bash
set -e
echo build >> "$ACTION_LOG"
if [[ "${{FAIL_BUILD:-}}" == yes ]]; then exit 1; fi
mkdir -p "build/{app}.app/Contents/MacOS"
printf fresh > "build/{app}.app/Contents/MacOS/{executable}"
""")
        self.installed = self.apps / "Tapper.app/Contents/MacOS/Tapper"
        self.installed.parent.mkdir(parents=True)
        self.installed.write_text("old")
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        ACTION_LOG=str(self.log), PROCESS_STATE=str(self.root))

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -e\n" + body + "\n")
        path.chmod(0o755)

    def run_script(self, *args, answer="", **env):
        return subprocess.run(["bash", str(self.project / args[0]), *args[1:]],
                              cwd=self.root, env=dict(self.env, **env), input=answer,
                              text=True, capture_output=True)

    def actions(self):
        return self.log.read_text() if self.log.exists() else ""

    def test_build_only_refreshes_stale_bundle_from_another_directory(self):
        stale = self.project / "build/Tapper.app/Contents/MacOS/Tapper"
        stale.parent.mkdir(parents=True)
        stale.write_text("stale")
        result = self.run_script("test-and-install.sh", "--build-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stale.read_text(), "fresh")
        self.assertEqual(self.installed.read_text(), "old")
        self.assertNotIn("open", self.actions())
        self.assertNotIn("stop", self.actions())

    def test_failed_build_preserves_running_and_installed_app(self):
        (self.root / "Tapper").touch()
        result = self.run_script("test-and-install.sh", FAIL_BUILD="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.installed.read_text(), "old")
        self.assertTrue((self.root / "Tapper").exists())
        self.assertEqual(self.actions(), "build\n")

    def test_declining_install_keeps_old_app_and_launches_exact_fresh_bundle(self):
        for app in ["Tapper", "Tapper_Debug"]:
            (self.root / app).touch()
        result = self.run_script("test-and-install.sh", answer="n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.installed.read_text(), "old")
        for app in ["Tapper", "Tapper_Debug"]:
            self.assertFalse((self.root / app).exists())
        self.assertIn(f"open -n {self.project}/build/Tapper.app", self.actions())
        self.assertFalse(list(self.apps.glob("*backup*")))

    def test_install_wrapper_rebuilds_and_preserves_backup(self):
        result = self.run_script("install-final.sh", answer="n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.installed.read_text(), "fresh")
        backups = list(self.apps.glob("*backup*.app/Contents/MacOS/Tapper"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old")
        self.assertFalse(list(self.apps.glob(".Tapper-install.*")))

    def test_failed_staging_does_not_replace_old_app(self):
        result = self.run_script("install-final.sh", FAIL_VERIFY="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.installed.read_text(), "old")
        self.assertFalse(list(self.apps.glob(".Tapper-install.*")))

    def test_failed_replacement_restores_backup(self):
        result = self.run_script("install-final.sh", FAIL_MOVE="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.installed.read_text(), "old")
        self.assertFalse(list(self.apps.glob(".Tapper-install.*")))

    def test_unstoppable_process_aborts_before_launch(self):
        (self.root / "Tapper").touch()
        result = self.run_script("test-and-install.sh", "--test-only", HOLD_PROCESS="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("open", self.actions())
        self.assertEqual(self.installed.read_text(), "old")

    def test_debug_selection_build_failure_preserves_running_app(self):
        (self.root / "Tapper").touch()
        result = self.run_script("quick-test.sh", answer="2\n", FAIL_BUILD="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "Tapper").exists())
        self.assertEqual(self.actions(), "build\n")

    def test_quick_test_rebuilds_release(self):
        result = self.run_script("quick-test.sh", answer="1\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("build\n", self.actions())
        self.assertIn("open -n", self.actions())
        self.assertEqual(self.installed.read_text(), "old")


if __name__ == "__main__":
    unittest.main()
