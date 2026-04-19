import os
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parent / "one_click_process.sh"


class OneClickProcessLockTest(unittest.TestCase):
    def run_bash(self, command: str, *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        return subprocess.run(
            ["bash", "-lc", command],
            text=True,
            capture_output=True,
            env=merged_env,
        )

    def test_script_can_be_sourced_without_running_main(self) -> None:
        result = self.run_bash(f"source '{SCRIPT_PATH}'")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_second_process_cannot_acquire_same_network_lock(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            env = {"LOVE20_SYNC_LOCK_ROOT": temp_dir}
            holder = subprocess.Popen(
                [
                    "bash",
                    "-lc",
                    (
                        f"export LOVE20_SYNC_LOCK_ROOT='{temp_dir}'; "
                        f"source '{SCRIPT_PATH}'; "
                        "trap 'release_sync_lock' EXIT INT TERM; "
                        "acquire_sync_lock thinkium70001_public; "
                        "sleep 30"
                    ),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, **env},
                preexec_fn=os.setsid,
            )
            try:
                time.sleep(0.5)
                contender = self.run_bash(
                    f"source '{SCRIPT_PATH}'; acquire_sync_lock thinkium70001_public",
                    env=env,
                )
                self.assertNotEqual(contender.returncode, 0, contender.stdout)
            finally:
                os.killpg(holder.pid, signal.SIGTERM)
                holder.communicate(timeout=5)

    def test_different_networks_can_acquire_lock_in_parallel(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            env = {"LOVE20_SYNC_LOCK_ROOT": temp_dir}
            first = self.run_bash(
                (
                    f"source '{SCRIPT_PATH}'; "
                    "acquire_sync_lock thinkium70001_public; "
                    "release_sync_lock"
                ),
                env=env,
            )
            second = self.run_bash(
                (
                    f"source '{SCRIPT_PATH}'; "
                    "acquire_sync_lock thinkium70001_public_test; "
                    "release_sync_lock"
                ),
                env=env,
            )
            self.assertEqual(first.returncode, 0, first.stderr or first.stdout)
            self.assertEqual(second.returncode, 0, second.stderr or second.stdout)


if __name__ == "__main__":
    unittest.main()
