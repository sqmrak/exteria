"""subprocess over the posix_spawn shim of _posixsubprocess: the device bundle has no fork, so python/shim/_posixsubprocess.py starts
the program. the real module of the host is replaced for the length of each test, and the shim is loaded from its file"""

import errno
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_shim():
    spec = importlib.util.spec_from_file_location("exteria_posixsubprocess_shim", os.path.join(ROOT, "python", "shim", "_posixsubprocess.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SHIM = load_shim()
CHILD_WRITES = "import os, sys; os.write(int(sys.argv[1]), b'x')"


class SpawnSubprocess(unittest.TestCase):
    def setUp(self):
        self.saved = subprocess._fork_exec
        subprocess._fork_exec = SHIM.fork_exec

    def tearDown(self):
        subprocess._fork_exec = self.saved

    def test_runs_a_program_and_reads_its_output(self):
        result = subprocess.run([sys.executable, "-c", "print('hi')"], capture_output=True)
        self.assertEqual((result.returncode, result.stdout), (0, b"hi\n"))

    def test_returns_the_exit_code(self):
        self.assertEqual(subprocess.run([sys.executable, "-c", "raise SystemExit(3)"]).returncode, 3)

    def test_feeds_standard_input(self):
        result = subprocess.run([sys.executable, "-c", "import sys; sys.stdout.write(sys.stdin.read().upper())"], input=b"abc", capture_output=True)
        self.assertEqual(result.stdout, b"ABC")

    def test_joins_standard_error_to_output(self):
        result = subprocess.run([sys.executable, "-c", "import sys; sys.stderr.write('e')"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.stdout, b"e")

    def test_passes_the_environment_it_is_given(self):
        env = {"PATH": os.environ.get("PATH", ""), "EXTERIA_PROBE": "seen"}
        result = subprocess.run([sys.executable, "-c", "import os; print(os.environ['EXTERIA_PROBE'])"], env=env, capture_output=True)
        self.assertEqual(result.stdout, b"seen\n")

    def test_searches_the_path(self):
        result = subprocess.run([os.path.basename(sys.executable), "-c", "print(1)"], env={"PATH": os.path.dirname(sys.executable)}, capture_output=True)
        self.assertEqual(result.stdout, b"1\n")

    def test_a_missing_program_raises_with_its_name(self):
        with self.assertRaises(FileNotFoundError) as caught:
            subprocess.run(["/nonexistent/exteria-probe"])
        self.assertEqual(caught.exception.filename, "/nonexistent/exteria-probe")

    def test_a_file_that_cannot_run_raises_permission_error(self):
        with tempfile.NamedTemporaryFile() as plain:
            with self.assertRaises(PermissionError):
                subprocess.run([plain.name])

    def test_a_descriptor_that_was_not_asked_for_is_closed(self):
        read, write = os.pipe()
        os.set_inheritable(write, True)
        try:
            result = subprocess.run([sys.executable, "-c", CHILD_WRITES, str(write)], capture_output=True, close_fds=True)
        finally:
            os.close(write)
            os.close(read)
        self.assertNotEqual(result.returncode, 0)

    def test_a_descriptor_in_pass_fds_reaches_the_child(self):
        read, write = os.pipe()
        try:
            subprocess.run([sys.executable, "-c", CHILD_WRITES, str(write)], pass_fds=(write,), check=True)
            os.close(write)
            write = None
            self.assertEqual(os.read(read, 1), b"x")
            self.assertFalse(os.get_inheritable(read))
        finally:
            if write is not None:
                os.close(write)
            os.close(read)

    def test_pass_fds_leaves_the_flag_of_the_parent_as_it_was(self):
        read, write = os.pipe()
        try:
            subprocess.run([sys.executable, "-c", "pass"], pass_fds=(write,), check=True)
            self.assertFalse(os.get_inheritable(write))
        finally:
            os.close(read)
            os.close(write)

    def test_a_pipe_on_a_low_descriptor_is_not_overwritten(self):
        saved = os.dup(0)
        os.close(0)
        try:
            result = subprocess.run([sys.executable, "-c", "import sys; print(sys.stdin.read())"], input=b"low", capture_output=True)
        finally:
            os.dup2(saved, 0)
            os.close(saved)
        self.assertEqual(result.stdout, b"low\n")

    def test_the_parent_keeps_no_descriptor_after_a_run(self):
        before = set(os.listdir("/dev/fd"))
        subprocess.run([sys.executable, "-c", "pass"], capture_output=True)
        self.assertEqual(set(os.listdir("/dev/fd")) - before, set())

    def test_refuses_what_posix_spawn_cannot_do(self):
        cases = [{"preexec_fn": lambda: None}, {"start_new_session": True}, {"umask": 0o22}]
        for options in cases:
            with self.subTest(options=sorted(options)):
                with self.assertRaises(OSError) as caught:
                    subprocess.run([sys.executable, "-c", "pass"], **options)
                self.assertEqual(caught.exception.errno, errno.ENOSYS)

    def test_runs_in_a_working_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run([sys.executable, "-c", "import os; print(os.getcwd())"], cwd=folder, capture_output=True)
            self.assertEqual(result.stdout.decode().strip(), os.path.realpath(folder))

    def test_a_relative_program_is_looked_up_in_the_working_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            tool = os.path.join(folder, "tool.sh")
            with open(tool, "w") as handle:
                handle.write("#!/bin/sh\necho from-tool\n")
            os.chmod(tool, 0o755)
            result = subprocess.run(["./tool.sh"], cwd=folder, capture_output=True)
            self.assertEqual(result.stdout, b"from-tool\n")

    def test_a_missing_working_directory_raises_with_its_name(self):
        with self.assertRaises(FileNotFoundError) as caught:
            subprocess.run([sys.executable, "-c", "pass"], cwd="/nonexistent/exteria-dir")
        self.assertEqual(caught.exception.filename, "/nonexistent/exteria-dir")

    def test_a_file_as_working_directory_raises_not_a_directory(self):
        with tempfile.NamedTemporaryFile() as plain:
            with self.assertRaises(NotADirectoryError):
                subprocess.run([sys.executable, "-c", "pass"], cwd=plain.name)

    def test_a_working_directory_without_a_shell_names_the_shell(self):
        saved = SHIM.SHELL
        SHIM.SHELL = "/nonexistent/exteria-sh"
        try:
            with self.assertRaises(FileNotFoundError) as caught:
                subprocess.run([sys.executable, "-c", "pass"], cwd="/")
        finally:
            SHIM.SHELL = saved
        self.assertEqual(caught.exception.filename, "/nonexistent/exteria-sh")

    def test_a_process_group_can_be_set(self):
        result = subprocess.run([sys.executable, "-c", "import os; print(os.getpgrp() == os.getpid())"], process_group=0, capture_output=True)
        self.assertEqual(result.stdout, b"True\n")


class System(unittest.TestCase):
    def setUp(self):
        self.saved = subprocess._fork_exec
        subprocess._fork_exec = SHIM.fork_exec
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import fakeapp  # noqa: F401
        sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]
        import exteria_host
        self.system = exteria_host._system

    def tearDown(self):
        subprocess._fork_exec = self.saved

    def test_answers_with_a_wait_status(self):
        self.assertEqual(self.system("exit 3"), 3 << 8)
        self.assertEqual(self.system("true"), 0)

    def test_reports_the_audit_event(self):
        seen = []
        sys.addaudithook(lambda event, args: seen.append((event, args)) if event == "os.system" else None)
        self.system("true")
        self.assertIn(("os.system", ("true",)), seen)


if __name__ == "__main__":
    unittest.main()
