import os
import subprocess
import tempfile
import unittest
from pathlib import Path


WRAPPER_PATH = Path(__file__).resolve().parent / "launchd_sync" / "sync_events_db.sh"


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

    def test_wrapper_requires_existing_script_log_dir(self) -> None:
        result = self.run_wrapper(env={"LOVE20_SYNC_SCRIPT_LOG_DIR": "/tmp/love20-missing-script-log-dir"})
        self.assertNotEqual(result.returncode, 0)

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
                    "LOVE20_SYNC_RUNTIME_DIR": str(fake_log_dir),
                    "LOVE20_SYNC_SCRIPT_LOG_DIR": str(fake_log_dir),
                }
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertEqual(marker_path.read_text(encoding="utf-8").strip(), "thinkium70001_public")


if __name__ == "__main__":
    unittest.main()
