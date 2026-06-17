import os
import subprocess
import tempfile
import unittest
from pathlib import Path


WRAPPER_PATH = Path(__file__).resolve().parent / "launchd_sync" / "sync_events_db.sh"
INSTALL_PATH = Path(__file__).resolve().parent / "launchd_sync" / "install.sh"


class LaunchdSyncWrapperTest(unittest.TestCase):
    def run_wrapper(self, *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        return subprocess.run(
            ["bash", str(WRAPPER_PATH)],
            text=True,
            capture_output=True,
            env=merged_env,
        )

    def run_install(self, *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        return subprocess.run(
            ["bash", str(INSTALL_PATH)],
            text=True,
            capture_output=True,
            env=merged_env,
        )

    def test_wrapper_requires_existing_script_log_dir(self) -> None:
        result = self.run_wrapper(env={"LOVE20_SYNC_SCRIPT_LOG_DIR": "/tmp/love20-missing-script-log-dir"})
        self.assertNotEqual(result.returncode, 0)

    def test_install_sets_source_log_dir_in_plist(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_home = temp_path / "home"
            fake_home.mkdir()
            fake_bin = temp_path / "bin"
            fake_bin.mkdir()
            launchctl_stub = fake_bin / "launchctl"
            launchctl_stub.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            launchctl_stub.chmod(0o755)

            result = self.run_install(
                env={
                    "HOME": str(fake_home),
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                }
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            plist_path = fake_home / "Library" / "LaunchAgents" / "com.love20.events-sync.plist"
            plist = plist_path.read_text(encoding="utf-8")
            self.assertIn("<key>LOVE20_SYNC_SOURCE_LOG_DIR</key>", plist)
            self.assertIn(f"<string>{Path(__file__).resolve().parent}</string>", plist)

    def test_wrapper_runs_one_click_process_with_default_network(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_home = temp_path / "home"
            fake_home.mkdir()
            fake_log_dir = temp_path / "script-log"
            fake_log_dir.mkdir()
            marker_path = fake_log_dir / "network.txt"
            stub_path = fake_log_dir / "one_click_process.sh"
            stub_path.write_text(
                "#!/usr/bin/env bash\n"
                "main() {\n"
                f"  printf '%s\\n' \"$1\" > '{marker_path}'\n"
                "}\n",
                encoding="utf-8",
            )

            result = self.run_wrapper(
                env={
                    "HOME": str(fake_home),
                    "LOVE20_SYNC_SCRIPT_LOG_DIR": str(fake_log_dir),
                }
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertEqual(marker_path.read_text(encoding="utf-8").strip(), "thinkium70001_public")

    def test_wrapper_falls_back_to_staged_runtime_when_source_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_home = temp_path / "home"
            fake_home.mkdir()
            staged_runtime = temp_path / "staged"
            staged_runtime.mkdir()
            network_root = staged_runtime / "network"
            network_dir = network_root / "thinkium70001_public"
            network_dir.mkdir(parents=True)
            marker_path = staged_runtime / "network.txt"
            stub_path = staged_runtime / "one_click_process.sh"
            stub_path.write_text(
                "#!/usr/bin/env bash\n"
                "main() {\n"
                f"  printf '%s\\n' \"$1\" > '{marker_path}'\n"
                "}\n",
                encoding="utf-8",
            )
            init_path = staged_runtime / "000_init.sh"
            init_path.write_text(
                "#!/usr/bin/env bash\n"
                "return 0\n",
                encoding="utf-8",
            )

            result = self.run_wrapper(
                env={
                    "HOME": str(fake_home),
                    "LOVE20_SYNC_RUNTIME_DIR": str(staged_runtime),
                    "LOVE20_SYNC_SOURCE_LOG_DIR": "/tmp/love20-missing-source-log-dir",
                    "LOVE20_LOG_NETWORK_ROOT": str(network_root),
                }
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertEqual(marker_path.read_text(encoding="utf-8").strip(), "thinkium70001_public")

    def test_wrapper_does_not_partially_refresh_from_incomplete_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_home = temp_path / "home"
            fake_home.mkdir()
            source_log_dir = temp_path / "source-log"
            source_log_dir.mkdir()
            staged_runtime = temp_path / "staged"
            staged_runtime.mkdir()
            network_root = staged_runtime / "network"
            (network_root / "thinkium70001_public").mkdir(parents=True)
            marker_path = staged_runtime / "network.txt"
            (source_log_dir / "one_click_process.sh").write_text(
                "#!/usr/bin/env bash\n"
                "main() {\n"
                "  printf 'source\\n'\n"
                "}\n",
                encoding="utf-8",
            )
            (source_log_dir / "000_init.sh").write_text("#!/usr/bin/env bash\nreturn 0\n", encoding="utf-8")
            (staged_runtime / "one_click_process.sh").write_text(
                "#!/usr/bin/env bash\n"
                "main() {\n"
                f"  printf '%s\\n' \"$1\" > '{marker_path}'\n"
                "}\n",
                encoding="utf-8",
            )

            result = self.run_wrapper(
                env={
                    "HOME": str(fake_home),
                    "LOVE20_SYNC_RUNTIME_DIR": str(staged_runtime),
                    "LOVE20_SYNC_SOURCE_LOG_DIR": str(source_log_dir),
                    "LOVE20_LOG_NETWORK_ROOT": str(network_root),
                }
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertEqual(marker_path.read_text(encoding="utf-8").strip(), "thinkium70001_public")


if __name__ == "__main__":
    unittest.main()
