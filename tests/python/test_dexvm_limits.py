import os
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import dexvm  # noqa: E402
from dexvm import limits, runtime  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "dex")


def fixture(name):
    with open(os.path.join(FIXTURES, name + ".dex"), "rb") as handle:
        return handle.read()


def java_name(error):
    return runtime.class_of(error).getName()


class Budget(unittest.TestCase):
    def setUp(self):
        self.limits = dexvm.load(fixture("Limits")).load_class("Limits")

    def tearDown(self):
        limits.configure()

    def call(self, name, *args):
        return self.limits.call_static(name, *args)

    def test_a_loop_without_exit_stops_at_the_deadline(self):
        started = time.monotonic()
        with limits.budget(seconds=0.2):
            with self.assertRaises(limits.BudgetExceeded) as caught:
                self.call("spin")
        self.assertLess(time.monotonic() - started, 3)
        self.assertIn("time limit", str(caught.exception))

    def test_a_step_budget_counts_loop_passes_and_calls(self):
        with limits.budget(steps=100000):
            self.assertEqual(sum(range(1000)), self.call("finite", 1000))
        with limits.budget(steps=100):
            with self.assertRaises(limits.BudgetExceeded) as caught:
                self.call("finite", 1000)
        self.assertIn("step limit of 100", str(caught.exception))

    def test_exponential_recursion_without_a_loop_is_bounded_too(self):
        self.assertEqual(832040, self.call("fib", 30))
        with limits.budget(seconds=0.2):
            with self.assertRaises(limits.BudgetExceeded):
                self.call("fib", 45)

    def test_a_catch_throwable_of_the_program_does_not_swallow_the_budget(self):
        with limits.budget(seconds=0.2):
            with self.assertRaises(limits.BudgetExceeded):
                self.call("swallow")

    def test_the_vm_works_after_a_budget_ended_a_call(self):
        with limits.budget(steps=10):
            with self.assertRaises(limits.BudgetExceeded):
                self.call("spin")
        self.assertEqual(45, self.call("finite", 10))
        self.assertIsNone(limits.current())

    def test_a_call_without_a_budget_is_not_checked(self):
        self.assertEqual(sum(range(100000)) & 0xFFFFFFFF, self.call("finite", 100000) & 0xFFFFFFFF)

    def test_array_elements_are_counted_while_a_budget_runs(self):
        with limits.budget(elements=1000):
            self.assertEqual(500, len(self.call("allocate", 500)))
            with self.assertRaises(limits.BudgetExceeded) as caught:
                self.call("allocate", 600)
        self.assertIn("array element limit", str(caught.exception))
        self.assertEqual(5000, len(self.call("allocate", 5000)))

    def test_one_array_over_the_cap_is_an_out_of_memory_error(self):
        with self.assertRaises(runtime.api.lookup_host("java.lang.OutOfMemoryError").py) as caught:
            self.call("allocate", limits.MAX_ARRAY_LENGTH + 1)
        self.assertIn("Failed to allocate", caught.exception.getMessage())
        with self.assertRaises(runtime.api.lookup_host("java.lang.NegativeArraySizeException").py):
            self.call("allocate", -1)

    def test_a_default_budget_applies_to_calls_from_python(self):
        limits.configure(seconds=0.2)
        with self.assertRaises(limits.BudgetExceeded):
            self.call("spin")
        limits.configure(seconds=5)
        self.assertEqual(45, self.call("finite", 10))
        limits.configure()
        self.assertIsNone(limits.defaults())

    def test_a_nested_budget_cannot_widen_the_outer_one(self):
        started = time.monotonic()
        with limits.budget(seconds=0.2):
            with limits.budget(seconds=60):
                with self.assertRaises(limits.BudgetExceeded):
                    self.call("spin")
        self.assertLess(time.monotonic() - started, 3)

    def test_a_thread_the_program_starts_spends_the_budget_of_its_starter(self):
        started = time.monotonic()
        returned = []
        with self.assertRaises(limits.BudgetExceeded) as caught:
            with limits.budget(seconds=0.2):
                returned.append(self.call("spinInThread"))
        self.assertEqual([7], returned)
        self.assertIn("time limit", str(caught.exception))
        self.assertLess(time.monotonic() - started, 3)

    def test_the_budget_of_another_thread_does_not_apply(self):
        import threading
        result = []

        def other():
            result.append(self.call("finite", 2000))
        with limits.budget(steps=5):
            thread = threading.Thread(target=other)
            thread.start()
            thread.join()
        self.assertEqual([sum(range(2000))], result)


class Cache(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = os.path.join(self.tmp.name, "dex")
        dexvm.cache.configure(self.directory)

    def tearDown(self):
        dexvm.cache.configure(None)
        self.tmp.cleanup()

    def entries(self):
        return sorted(name for name in os.listdir(self.directory) if name.endswith(".dxm"))

    def expected(self, name):
        with open(os.path.join(FIXTURES, "expected", name + ".txt"), encoding="utf-8") as handle:
            return handle.read()

    def run_fixture(self, name):
        return dexvm.load(fixture(name), name=name).load_class(name).call_static("run")

    def test_a_second_load_runs_from_the_cache_and_prints_the_same(self):
        cache = dexvm.cache.current()
        for name in ("Arith", "Flow", "Arrs", "Strs", "Objs", "Fmt", "Indy", "CustomIndy"):
            first = self.run_fixture(name)
            self.assertEqual(self.expected(name), first, name)
            stores, hits = cache.stats["stores"], cache.stats["hits"]
            self.assertGreater(stores, 0)
            second = self.run_fixture(name)
            self.assertEqual(first, second, name)
            self.assertEqual(stores, cache.stats["stores"], "%s translated again" % name)
            self.assertGreater(cache.stats["hits"], hits, name)
        self.assertEqual(0, cache.stats["rejected"])
        self.assertEqual(0, cache.stats["errors"])

    def test_no_temporary_file_is_left_behind(self):
        self.run_fixture("Flow")
        self.assertFalse([name for name in os.listdir(self.directory) if name.startswith(".tmp-")])
        self.assertTrue(self.entries())

    def test_a_damaged_entry_is_dropped_and_translated_again(self):
        self.run_fixture("Flow")
        cache = dexvm.cache.current()
        victims = self.entries()[:3]
        for position, name in enumerate(victims):
            path = os.path.join(self.directory, name)
            with open(path, "rb") as handle:
                data = bytearray(handle.read())
            if position == 0:
                data = data[:len(data) // 2]
            elif position == 1:
                data[-5] ^= 0xFF
            else:
                data[:4] = b"NOPE"
            with open(path, "wb") as handle:
                handle.write(data)
        self.assertEqual(self.expected("Flow"), self.run_fixture("Flow"))
        self.assertEqual(len(victims), cache.stats["rejected"])
        self.assertEqual(self.expected("Flow"), self.run_fixture("Flow"))

    def test_an_entry_of_another_dex_is_never_used(self):
        self.run_fixture("Flow")
        self.run_fixture("Arith")
        cache = dexvm.cache.current()
        key_flow = dexvm.cache.method_key(dexvm.load(fixture("Flow")).load_class("Flow").dexfile.sha256, 5)
        key_arith = dexvm.cache.method_key(dexvm.load(fixture("Arith")).load_class("Arith").dexfile.sha256, 5)
        self.assertNotEqual(key_flow, key_arith)
        self.assertNotEqual(cache.path(key_flow), cache.path(key_arith))

    def test_the_key_holds_the_translator_and_the_python(self):
        key = dexvm.cache.method_key("abc", 3)
        self.assertEqual(dexvm.cache.fingerprint(), key.split(":")[2])
        self.assertEqual(64, len(dexvm.cache.fingerprint()))

    def test_an_entry_over_the_limit_is_not_stored(self):
        dexvm.cache.configure(self.directory, max_entry=64)
        self.run_fixture("Flow")
        cache = dexvm.cache.current()
        self.assertEqual([], self.entries())
        self.assertGreater(cache.stats["oversize"], 0)
        self.assertEqual(self.expected("Flow"), self.run_fixture("Flow"))

    def test_the_oldest_entries_go_when_the_total_is_over_the_limit(self):
        dexvm.cache.configure(self.directory, max_total=6000)
        self.run_fixture("Flow")
        self.run_fixture("Arith")
        cache = dexvm.cache.current()
        self.assertGreater(cache.stats["evicted"], 0)
        total = sum(os.stat(os.path.join(self.directory, name)).st_size for name in self.entries())
        self.assertLessEqual(total, 6000)

    def test_a_folder_that_cannot_be_written_costs_nothing_but_the_cache(self):
        if os.geteuid() == 0:
            self.skipTest("root writes anywhere")
        os.chmod(self.directory, 0o500)
        try:
            self.assertEqual(self.expected("Flow"), self.run_fixture("Flow"))
        finally:
            os.chmod(self.directory, 0o700)
        cache = dexvm.cache.current()
        self.assertGreater(cache.stats["errors"], 0)
        self.assertIn("write", cache.last_error)

    def test_temporaries_of_a_crashed_writer_are_swept_on_start(self):
        stale = os.path.join(self.directory, ".tmp-crashed")
        with open(stale, "wb") as handle:
            handle.write(b"half")
        dexvm.cache.configure(self.directory)
        self.assertFalse(os.path.exists(stale))

    def test_answers_about_the_surrounding_classes_are_checked_on_every_load(self):
        asked = dexvm.cache.RecordingEnv(dexvm.translate.Env())
        asked.dex_class("LFoo;")
        asked.instance_field("LFoo;", "x", "I")
        self.assertTrue(dexvm.cache.still_true(asked.log, dexvm.translate.Env()))

        class Changed(dexvm.translate.Env):
            def dex_class(self, descriptor):
                return True
        self.assertFalse(dexvm.cache.still_true(asked.log, Changed()))

        class Moved(dexvm.translate.Env):
            def instance_field(self, class_desc, name, type_desc):
                return "f_other"
        self.assertFalse(dexvm.cache.still_true(asked.log, Moved()))

    def test_clear_removes_every_entry(self):
        self.run_fixture("Flow")
        dexvm.cache.current().clear()
        self.assertEqual([], self.entries())


if __name__ == "__main__":
    unittest.main()
