import io
import os
import struct
import sys
import unittest
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python", "shim"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dexbuilder  # noqa: E402
import dexvm  # noqa: E402
from dexvm import api, classes, container, format as dexformat, jio, jloader, jnio, opcodes, runtime, translate  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "dex")


def fixture(name):
    with open(os.path.join(FIXTURES, name + ".dex"), "rb") as handle:
        return handle.read()


def expected(name):
    with open(os.path.join(FIXTURES, "expected", name + ".txt"), encoding="utf-8") as handle:
        return handle.read()


def java_name(error):
    return runtime.class_of(error).getName()


class Oracle(unittest.TestCase):
    """javac and d8 built these classes; the expected text is what a jvm printed for the same sources, so a line that
    differs is a difference between the runtime and java, not between two guesses"""

    def check(self, name):
        loader = dexvm.load(fixture(name), name=name)
        got = loader.load_class(name).call_static("run")
        want = expected(name)
        if got != want:
            got_lines = got.splitlines()
            want_lines = want.splitlines()
            for number, (a, b) in enumerate(zip(want_lines, got_lines), 1):
                if a != b:
                    self.fail("line %d of %s\n jvm:   %s\n dexvm: %s" % (number, name, a, b))
            self.assertEqual(len(want_lines), len(got_lines))
        self.assertEqual(want, got)

    def test_arithmetic_overflow_conversions_and_float_text(self):
        self.check("Arith")

    def test_control_flow_switches_exceptions_and_deep_recursion(self):
        self.check("Flow")

    def test_arrays_bounds_narrowing_and_payload_initialisers(self):
        self.check("Arrs")

    def test_strings_boxes_and_string_builder(self):
        self.check("Strs")

    def test_classes_inheritance_interfaces_overloads_static_init_and_enums(self):
        self.check("Objs")

    def test_threads_monitors_wait_notify(self):
        self.check("Sync")

    def test_reflection_proxies_and_runtime_annotations(self):
        self.check("Refl")

    def test_format_strings_and_regular_expressions(self):
        self.check("Fmt")

    def test_collections_hash_order_random_math_digests_and_executors(self):
        self.check("Util")

    def test_lambdas_method_references_and_string_concatenation_call_sites(self):
        self.check("Indy")

    def test_call_sites_with_bootstrap_methods_of_the_program(self):
        self.check("CustomIndy")

    def test_streams_run_their_stages_element_by_element_and_stop_early(self):
        self.check("Streams")

    def test_spliterators_scanner_sequential_lists_and_inheritable_locals(self):
        self.check("Api2")

    def test_executors_queues_synchronizers_field_updaters_zones_and_time_values(self):
        self.check("Api3")

    def test_permissions_key_specs_sni_names_and_destroyable(self):
        self.check("Api4")

    def test_certificates_principals_certificate_factory_and_key_store(self):
        self.check("Certs")

    def test_date_time_formatter_and_builder(self):
        self.check("TimeFmt")

    def test_chronologies_eras_chrono_dates_and_temporal_queries(self):
        self.check("Chrono")

    def test_bidi_levels_runs_lines_and_visual_order(self):
        self.check("BidiText")

    def test_collators_strengths_keys_element_iterators_and_rules(self):
        self.check("Collate")

    def test_date_time_formatter_and_builder(self):
        self.check("TimeFmt")

    def test_a_bootstrap_method_that_throws_is_a_bootstrap_method_error(self):
        error = self.assertRaises(runtime.api.lookup_host("java.lang.BootstrapMethodError").py)
        loader = dexvm.load(fixture("CustomIndy"))
        with error as caught:
            loader.load_class("CustomIndy").call_static("broken")
        cause = caught.exception.getCause()
        self.assertEqual("java.lang.IllegalStateException", java_name(cause))
        self.assertEqual("no bootstrap today", cause.getMessage())


class JavaLoaders(unittest.TestCase):
    """the java classes of dalvik.system over files, archives and buffers"""

    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def path(self, name, data):
        full = os.path.join(self.tmp.name, name)
        with open(full, "wb") as handle:
            handle.write(data)
        return full

    def test_dex_class_loader_reads_a_file_and_an_archive(self):
        flow = self.path("flow.dex", fixture("Flow"))
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("classes.dex", fixture("Arith"))
            archive.writestr("res/raw.txt", b"data")
        jar = self.path("app.jar", buffer.getvalue())
        loader = jloader.DexClassLoader(os.pathsep.join((flow, jar)), None, None, None)
        self.assertEqual(loader.loadClass("Flow").call_static("fib", 9), 34)
        self.assertEqual(loader.loadClass("Arith").call_static("run"), expected("Arith"))
        self.assertIs(loader.loadClass("Flow").getClassLoader(), loader)

    def test_path_class_loader_and_parent_delegation(self):
        flow = self.path("flow.dex", fixture("Flow"))
        parent = jloader.PathClassLoader(flow, None)
        child = jloader.PathClassLoader(self.path("c.dex", fixture("Flow")), parent)
        self.assertIs(child.loadClass("Flow"), parent.loadClass("Flow"))
        last = jloader.DelegateLastClassLoader(self.path("d.dex", fixture("Flow")), parent)
        self.assertIsNot(last.loadClass("Flow"), parent.loadClass("Flow"))
        self.assertIs(last.loadClass("Flow").getClassLoader(), last)

    def test_in_memory_loader_reads_buffers(self):
        buffer = jnio.ByteBuffer.wrap(jio.to_java_bytes(fixture("Strs")))
        loader = jloader.InMemoryDexClassLoader(buffer, None)
        self.assertEqual(loader.loadClass("Strs").call_static("run"), expected("Strs"))

    def test_unknown_class_is_class_not_found_with_the_path_in_the_message(self):
        loader = jloader.PathClassLoader(self.path("flow.dex", fixture("Flow")), None)
        with self.assertRaises(api.lookup_host("java.lang.ClassNotFoundException").py) as caught:
            loader.loadClass("no.such.Thing")
        self.assertIn("no.such.Thing", caught.exception.getMessage())
        self.assertIn("flow.dex", caught.exception.getMessage())

    def test_unreadable_dex_is_kept_as_the_reason_of_the_failed_lookup(self):
        missing = os.path.join(self.tmp.name, "absent.dex")
        broken = self.path("broken.dex", fixture("Flow")[:100])
        loader = jloader.DexClassLoader(os.pathsep.join((missing, broken)), None, None, None)
        self.assertEqual(len(loader.dex_errors()), 2)
        with self.assertRaises(api.lookup_host("java.lang.ClassNotFoundException").py) as caught:
            loader.loadClass("Flow")
        reasons = [java_name(r) for r in caught.exception._suppressed]
        self.assertEqual(reasons, ["java.io.IOException", "java.io.IOException"])

    def test_dex_file_lists_and_loads_classes(self):
        dexfile = jloader.DexFile(self.path("a.dex", fixture("Flow")))
        entries = dexfile.entries()
        names = []
        while entries.hasMoreElements():
            names.append(entries.nextElement())
        self.assertEqual(names, ["Flow"])
        self.assertEqual(dexfile.loadClass("Flow", None).call_static("fib", 8), 21)
        self.assertIsNone(dexfile.loadClass("Absent", None))
        with self.assertRaises(api.lookup_host("java.io.IOException").py):
            jloader.DexFile(os.path.join(self.tmp.name, "none.dex"))

    def test_class_for_name_uses_the_loader_it_is_given(self):
        loader = jloader.PathClassLoader(self.path("flow.dex", fixture("Flow")), None)
        jclass = api.lookup_host("java.lang.Class")
        found = classes.class_for_name("Flow", None, jloader._vm_of(loader), True)
        self.assertIs(found.loader, loader.vm_loader())
        with self.assertRaises(api.lookup_host("java.lang.ClassNotFoundException").py):
            classes.class_for_name("Flow", None, classes.BOOT, True)
        self.assertEqual(jclass.name, "java.lang.Class")

    def test_a_program_loader_is_asked_by_name_when_it_is_a_parent(self):
        flow = dexvm.load(fixture("Flow")).load_class("Flow")

        class Custom(jloader.ClassLoader):
            def loadClass(self, name, resolve=False):
                if name == "Flow":
                    return flow
                runtime.throw_new("java.lang.ClassNotFoundException", name)

        child = jloader.PathClassLoader(self.path("arith.dex", fixture("Arith")), Custom())
        self.assertIs(child.loadClass("Flow"), flow)
        self.assertEqual(child.loadClass("Arith").call_static("idiv", 9, 2), 4)

    def test_define_class_refuses_java_bytecode(self):
        with self.assertRaises(api.lookup_host("java.lang.UnsupportedClassVersionError").py):
            jloader.ClassLoader().defineClass("X", runtime.new_array("[B", 4), 0, 4)

    def test_file_policy_confines_java_io(self):
        from dexvm import policy
        inside = self.path("inside.bin", b"abc")
        try:
            policy.FILE_ROOTS = [self.tmp.name]
            stream = jio.FileInputStream(inside)
            self.addCleanup(stream.close)
            self.assertEqual(stream.readAllBytes()[:], [97, 98, 99])
            with self.assertRaises(api.lookup_host("java.lang.SecurityException").py):
                jio.FileInputStream("/etc/hostname")
            with self.assertRaises(api.lookup_host("java.lang.SecurityException").py):
                jio.File(os.path.join(self.tmp.name, "..", "x")).exists()
        finally:
            policy.FILE_ROOTS = None


class Entry(unittest.TestCase):
    def test_plugin_imports_loaders_and_loads_from_its_byte_buffer(self):
        from dalvik.system import InMemoryDexClassLoader, DexClassLoader
        from java import jclass
        from java.lang import Class
        from java.nio import ByteBuffer

        self.assertIs(jclass("dalvik.system.DexClassLoader"), DexClassLoader)
        data = fixture("Flow")
        buffer = ByteBuffer.wrap(b"xx" + data + b"yy")
        buffer.position(2).limit(len(data) + 2)
        loader = InMemoryDexClassLoader(buffer, None)
        flow = Class.forName("Flow", True, loader)
        self.assertEqual(flow.call_static("fib", 9), 34)
        self.assertEqual(buffer.position(), 2)
        self.assertIs(flow, loader.loadClass("Flow"))

    def test_archive_rejects_duplicate_and_invalid_dex_names(self):
        for names in (("classes.dex", "classes.dex"), ("classes01.dex",)):
            buffer = io.BytesIO()
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(buffer, "w") as archive:
                    for name in names:
                        archive.writestr(name, fixture("Flow"))
            with self.assertRaises(dexformat.DexFormatError):
                dexvm.load(buffer.getvalue())

    def test_damaged_zip_entry_is_a_format_error(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("classes.dex", fixture("Flow"))
        data = bytearray(buffer.getvalue())
        data[41] ^= 1
        with self.assertRaises(dexformat.DexFormatError):
            dexvm.load(data)


class JavaZip(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = os.path.join(self.tmp.name, "data.zip")
        with zipfile.ZipFile(self.path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("dir/", b"")
            archive.writestr("dir/data.bin", b"\x00\x80\xffdata")

    def test_zip_file_entries_and_streams(self):
        from dexvm import jzip
        archive = jzip.ZipFile(self.path)
        self.addCleanup(archive.close)
        self.assertEqual(archive.size(), 2)
        self.assertTrue(archive.getEntry("dir").isDirectory())
        entry = archive.getEntry("dir/data.bin")
        self.assertEqual(entry.getSize(), 7)
        self.assertIsNone(archive.getEntry("missing"))
        entries = archive.entries()
        self.assertEqual([entries.nextElement().getName(), entries.nextElement().getName()], ["dir/", "dir/data.bin"])
        self.assertFalse(entries.hasMoreElements())
        stream = archive.getInputStream(entry)
        host = api.host_for_pytype(type(stream))
        read_one = classes.host_virtual(host, "read", "()I")
        read_many = classes.host_virtual(host, "read", "([BII)I")
        self.assertEqual(read_one(stream), 0)
        data = runtime.new_array("[B", 6)
        self.assertEqual(read_many(stream, data, 0, 6), 6)
        self.assertEqual(list(data), [-128, -1, 100, 97, 116, 97])
        self.assertEqual(read_one(stream), -1)
        archive.close()
        with self.assertRaises(api.lookup_host("java.io.IOException").py):
            read_one(stream)
        with self.assertRaises(api.lookup_host("java.lang.IllegalStateException").py):
            archive.size()

    def test_missing_bad_and_oversized_files_are_errors(self):
        from dexvm import jzip
        with self.assertRaises(api.lookup_host("java.io.FileNotFoundException").py):
            jzip.ZipFile(self.path + ".missing")
        bad = os.path.join(self.tmp.name, "bad.zip")
        with open(bad, "wb") as handle:
            handle.write(b"not a zip")
        with self.assertRaises(api.lookup_host("java.util.zip.ZipException").py):
            jzip.ZipFile(bad)
        from unittest.mock import patch
        with patch.object(jzip, "MAX_ARCHIVE", 4):
            with self.assertRaises(api.lookup_host("java.util.zip.ZipException").py):
                jzip.ZipFile(self.path)
        with patch.object(jzip, "MAX_ENTRIES", 1):
            with self.assertRaises(api.lookup_host("java.util.zip.ZipException").py):
                jzip.ZipFile(self.path)
        archive = jzip.ZipFile(self.path)
        self.addCleanup(archive.close)
        with patch.object(jzip, "MAX_ENTRY", 4):
            with self.assertRaises(api.lookup_host("java.util.zip.ZipException").py):
                archive.getInputStream(archive.getEntry("dir/data.bin"))

    def test_zip_file_obeys_file_policy(self):
        from dexvm import jzip, policy
        previous = policy.FILE_ROOTS
        try:
            policy.FILE_ROOTS = [os.path.join(self.tmp.name, "other")]
            with self.assertRaises(api.lookup_host("java.lang.SecurityException").py):
                jzip.ZipFile(self.path)
        finally:
            policy.FILE_ROOTS = previous

    def test_corrupt_entry_fails_during_read(self):
        from dexvm import jzip
        path = os.path.join(self.tmp.name, "corrupt.zip")
        with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
            archive.writestr("data", b"hello")
        with open(path, "r+b") as handle:
            handle.seek(34)
            handle.write(b"X")
        archive = jzip.ZipFile(path)
        self.addCleanup(archive.close)
        stream = archive.getInputStream(archive.getEntry("data"))
        with self.assertRaises(api.lookup_host("java.util.zip.ZipException").py):
            stream.readAllBytes()

    def test_dex_opens_archive_and_reads_entry(self):
        builder = dexbuilder.DexBuilder()
        zip_class = builder.add_class("Ljava/util/zip/ZipFile;")
        zip_class.method("<init>", "(Ljava/lang/String;)V", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_CONSTRUCTOR)
        zip_class.method("getEntry", "(Ljava/lang/String;)Ljava/util/zip/ZipEntry;", dexbuilder.ACC_PUBLIC)
        zip_class.method("getInputStream", "(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;", dexbuilder.ACC_PUBLIC)
        stream_class = builder.add_class("Ljava/io/InputStream;")
        stream_class.method("read", "()I", dexbuilder.ACC_PUBLIC)
        stream_class.method("close", "()V", dexbuilder.ACC_PUBLIC)
        zip_class.method("close", "()V", dexbuilder.ACC_PUBLIC)
        cls = builder.add_class("LT;")
        cls.method("read", "(Ljava/lang/String;Ljava/lang/String;)I", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC,
                   registers=5, ins=2, insns=[
                       0x22, 0, 0x2070, 0, 0x30, 0x206e, 0, 0x40, 0x010c,
                       0x206e, 0, 0x10, 0x010c, 0x106e, 0, 0x01, 0x020a,
                       0x106e, 0, 0x01, 0x106e, 0, 0x00, 0x020f])
        data = bytearray(builder.build())
        dex = dexformat.DexFile(data)
        zip_type = next(i for i in range(dex.type_count()) if dex.type(i) == "Ljava/util/zip/ZipFile;")
        indices = {(dex.method(i).class_type, dex.method(i).name): i for i in range(dex.method_count())}
        target = next(c for c in dex.class_defs() if dex.type(c.type_idx) == "LT;")
        code = dex.class_data(target).direct_methods[0].code_off + 16
        for unit, value in ((1, zip_type), (3, indices[("Ljava/util/zip/ZipFile;", "<init>")]),
                            (6, indices[("Ljava/util/zip/ZipFile;", "getEntry")]),
                            (10, indices[("Ljava/util/zip/ZipFile;", "getInputStream")]),
                            (14, indices[("Ljava/io/InputStream;", "read")]),
                            (18, indices[("Ljava/io/InputStream;", "close")]),
                            (21, indices[("Ljava/util/zip/ZipFile;", "close")])):
            struct.pack_into("<H", data, code + unit * 2, value)
        loader = dexvm.load(dexbuilder.fix_checksums(data))
        self.assertEqual(loader.load_class("T").call_static("read", self.path, "dir/data.bin"), 0)


class EntryCalls(unittest.TestCase):
    def test_static_call_and_object_call_from_python(self):
        loader = dexvm.load(fixture("Objs"))
        counter = loader.load_class("Objs$Counter")
        counter_obj = counter.new_instance()
        for _ in range(5):
            counter_obj.inc()
        self.assertEqual(counter_obj.get(), 5)
        objs = loader.load_class("Objs")
        self.assertIsInstance(objs.call_static("run"), str)

    def test_constructor_overloads_and_argument_conversion(self):
        loader = dexvm.load(fixture("Objs"))
        rect = loader.load_class("Objs$Rect")
        shape = rect.new_instance(4.0, 5.0)
        self.assertEqual(shape.area(), 20.0)
        self.assertEqual(rect.new_instance().area(), 6.0)

    def test_overloaded_name_needs_a_descriptor(self):
        loader = dexvm.load(fixture("Objs"))
        base = loader.load_class("Objs$Base")
        with self.assertRaises(AttributeError):
            base.method("over")
        self.assertEqual(base.method("over", "(I)Ljava/lang/String;").owner, base)

    def test_missing_class_gives_none(self):
        loader = dexvm.load(fixture("Arith"))
        self.assertIsNone(loader.load_class("does.not.Exist"))

    def test_dex_object_is_usable_by_host_code(self):
        loader = dexvm.load(fixture("Objs"))
        obj = loader.load_class("Objs$Rect").new_instance()
        self.assertTrue(obj.toString().startswith("Rect#"))
        self.assertEqual(runtime.class_of(obj).getName(), "Objs$Rect")


class Containers(unittest.TestCase):
    def test_bare_dex_zip_and_memory_views(self):
        data = fixture("Flow")
        for source in (data, bytearray(data), memoryview(data)):
            loader = dexvm.load(source)
            self.assertEqual(loader.load_class("Flow").call_static("fib", 10), 55)
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("classes.dex", fixture("Flow"))
            archive.writestr("classes2.dex", fixture("Arith"))
            archive.writestr("AndroidManifest.xml", b"ignored")
        loader = dexvm.load(buffer.getvalue())
        self.assertEqual(loader.load_class("Flow").call_static("fib", 10), 55)
        self.assertEqual(loader.load_class("Arith").call_static("run"), expected("Arith"))

    def test_zip_order_is_numeric(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("classes10.dex", fixture("Flow"))
            archive.writestr("classes2.dex", fixture("Arith"))
            archive.writestr("classes.dex", fixture("Strs"))
        names = [dex.name for dex in container.load_container(buffer.getvalue())]
        self.assertEqual(names, ["classes.dex", "classes2.dex", "classes10.dex"])

    def test_zip_without_dex_and_garbage_are_refused(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("readme.txt", b"x")
        with self.assertRaisesRegex(dexformat.DexFormatError, "no classes.dex"):
            dexvm.load(buffer.getvalue())
        with self.assertRaisesRegex(dexformat.DexFormatError, "neither"):
            dexvm.load(b"hello world")
        with self.assertRaisesRegex(dexformat.DexFormatError, "bad zip"):
            dexvm.load(b"PK\x03\x04" + b"\0" * 40)

    def test_zip_limits(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for index in range(container.MAX_ENTRIES + 1):
                archive.writestr("f%d" % index, b"")
        with self.assertRaisesRegex(dexformat.DexFormatError, "entries"):
            dexvm.load(buffer.getvalue())
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for index in range(container.MAX_DEX_FILES + 1):
                archive.writestr("classes%d.dex" % (index + 2), fixture("Flow"))
        with self.assertRaisesRegex(dexformat.DexFormatError, "dex files"):
            dexvm.load(buffer.getvalue())

    def test_dex_larger_than_the_limit_is_refused_before_parsing(self):
        data = b"dex\n035\0" + bytes(dexformat.MAX_FILE_SIZE)
        with self.assertRaisesRegex(dexformat.DexFormatError, "larger than"):
            dexformat.DexFile(data)


class Corruption(unittest.TestCase):
    """every offset and count of the header is checked: a damaged file raises DexFormatError and nothing else"""

    def parse(self, data, verify=True):
        return dexformat.DexFile(dexbuilder.fix_checksums(data) if verify else data)

    def mutate(self, offset, value, fmt="<I"):
        data = bytearray(fixture("Flow"))
        struct.pack_into(fmt, data, offset, value)
        return bytes(data)

    def test_bad_magic_and_version(self):
        data = bytearray(fixture("Flow"))
        data[0] = ord("x")
        with self.assertRaisesRegex(dexformat.DexFormatError, "magic"):
            dexformat.DexFile(bytes(data))
        data = bytearray(fixture("Flow"))
        data[4:7] = b"999"
        with self.assertRaisesRegex(dexformat.DexFormatError, "version 999"):
            dexformat.DexFile(bytes(data))

    def test_checksum_size_and_endian(self):
        data = bytearray(fixture("Flow"))
        data[200] ^= 0xFF
        with self.assertRaisesRegex(dexformat.DexFormatError, "checksum"):
            dexformat.DexFile(bytes(data))
        with self.assertRaisesRegex(dexformat.DexFormatError, "file size"):
            dexformat.DexFile(fixture("Flow")[:-8])
        with self.assertRaisesRegex(dexformat.DexFormatError, "byte order"):
            self.parse(self.mutate(40, dexformat.REVERSE_ENDIAN_CONSTANT))
        with self.assertRaisesRegex(dexformat.DexFormatError, "shorter"):
            dexformat.DexFile(fixture("Flow")[:0x40])

    def test_tables_that_leave_the_file(self):
        # header fields: string_ids_size 56, string_ids_off 60, type_ids 64/68, proto 72/76, field 80/84, method 88/92, class 96/100
        for offset, value, text in ((56, 0x10000000, "string_ids"), (60, 0x7FFFFFF0, "string_ids"),
                                    (64, 0x10000000, "type_ids"), (72, 0x10000000, "proto_ids"),
                                    (80, 0x10000000, "field_ids"), (88, 0x10000000, "method_ids"),
                                    (96, 0x10000000, "class_defs"), (68, 4, "header")):
            with self.subTest(field=offset):
                with self.assertRaisesRegex(dexformat.DexFormatError, text):
                    self.parse(self.mutate(offset, value))

    def test_indices_that_leave_their_tables(self):
        data = fixture("Flow")
        dex = dexformat.DexFile(data)
        type_off = struct.unpack_from("<I", data, 68)[0]
        with self.assertRaisesRegex(dexformat.DexFormatError, "type descriptor index"):
            self.parse(self.mutate(type_off, 0x7FFFFFF))
        method_off = struct.unpack_from("<I", data, 92)[0]
        with self.assertRaisesRegex(dexformat.DexFormatError, "method id index"):
            self.parse(self.mutate(method_off, 0x7FFF, "<H"))
        class_off = struct.unpack_from("<I", data, 100)[0]
        with self.assertRaisesRegex(dexformat.DexFormatError, "superclass index"):
            self.parse(self.mutate(class_off + 8, 0x7FFFFFF))
        self.assertGreater(dex.class_count(), 0)

    def test_string_data_errors(self):
        data = fixture("Flow")
        string_off = struct.unpack_from("<I", data, 60)[0]
        with self.assertRaisesRegex(dexformat.DexFormatError, "string data offset"):
            self.parse(self.mutate(string_off, len(data) + 10))
        # a string whose bytes are not modified utf-8
        dex = dexformat.DexFile(data)
        first = struct.unpack_from("<I", data, string_off)[0]
        broken = bytearray(data)
        size, pos = dexformat.uleb128(data, first, len(data))
        broken[pos] = 0xFF
        damaged = dexformat.DexFile(dexbuilder.fix_checksums(bytes(broken)))
        with self.assertRaisesRegex(dexformat.DexFormatError, "lead byte|length"):
            damaged.string(0)
        self.assertTrue(dex.string(0))

    def test_class_data_and_code_offsets(self):
        data = fixture("Flow")
        class_off = struct.unpack_from("<I", data, 100)[0]
        damaged = self.parse(self.mutate(class_off + 24, len(data) - 1))
        with self.assertRaisesRegex(dexformat.DexFormatError, "class data|leb128"):
            damaged.class_data(damaged.class_defs()[0])
        dex = dexformat.DexFile(data)
        with self.assertRaisesRegex(dexformat.DexFormatError, "code item"):
            dex.code(len(data) - 4)
        with self.assertRaisesRegex(dexformat.DexFormatError, "misaligned"):
            dex.code(dex.data_off + 2)

    def test_leb128_limits(self):
        with self.assertRaisesRegex(dexformat.DexFormatError, "longer than five"):
            dexformat.uleb128(b"\xff\xff\xff\xff\xff\x01", 0, 6)
        with self.assertRaisesRegex(dexformat.DexFormatError, "runs out"):
            dexformat.uleb128(b"\x80", 0, 1)
        self.assertEqual(dexformat.sleb128(b"\x7f", 0, 1)[0], -1)

    def test_mutf8_round_trip_and_refusals(self):
        for text in ("", "plain", "caf" + chr(0xE9), chr(0x4E2D) + chr(0x6587), "nul\0inside", chr(0xD83D) + chr(0xDE00), chr(0xD800)):
            raw = dexformat.encode_mutf8(text)
            self.assertEqual(dexformat.decode_mutf8(raw + b"\0", 0, len(raw) + 1, len(text)), text)
        for raw, text in ((b"\xf0\x9f\x98\x80\0", "four byte"), (b"\xc0\x41\0", "continuation"),
                          (b"\xc1\x81\0", "overlong"), (b"\xe0\x80\x80\0", "overlong"), (b"\x80\0", "lead")):
            with self.assertRaisesRegex(dexformat.DexFormatError, text):
                dexformat.decode_mutf8(raw, 0, len(raw), 1)
        with self.assertRaisesRegex(dexformat.DexFormatError, "not terminated"):
            dexformat.decode_mutf8(b"ab", 0, 2, 2)


class Decoder(unittest.TestCase):
    def test_invoke_custom_uses_call_site_table(self):
        class Dex:
            def call_site(self, index):
                self.index = index
                return [(0x16, 0), (0x17, 0), (0x15, 0)]

            def proto(self, index):
                return dexformat.Proto("V", "V", ())

            def method(self, index):
                raise AssertionError("invoke-custom does not refer to the method table")

        dex = Dex()
        translator = translate.Translator(dex, None, "test", dex.proto(0), dexformat.ACC_STATIC, "LT;")
        instruction = opcodes.decode_one([0xfc, 9, 0], 0)
        translator._invoke(instruction, None)
        self.assertEqual(dex.index, 9)
        self.assertIn(("invoke-custom", 9), translator.sites.values())

    def test_every_format_decodes_in_a_real_file(self):
        dex = dexformat.DexFile(fixture("Arith"))
        seen = set()
        for class_def in dex.class_defs():
            data = dex.class_data(class_def)
            for method in data.direct_methods + data.virtual_methods:
                code = dex.code(method.code_off)
                if code:
                    seen.update(insn.fmt for insn in opcodes.decode_all(code.insns))
        self.assertTrue({"12x", "23x", "21c", "35c", "22b", "payload"} <= seen | {"payload"})

    def test_unknown_and_cut_instructions(self):
        with self.assertRaisesRegex(opcodes.DecodeError, "unknown opcode 0x3e"):
            opcodes.decode_one([0x3E], 0)
        with self.assertRaisesRegex(opcodes.DecodeError, "cut"):
            opcodes.decode_one([0x14], 0)
        with self.assertRaisesRegex(opcodes.DecodeError, "payload"):
            opcodes.decode_one([0x0100, 0xFFFF, 0, 0], 0)
        with self.assertRaisesRegex(opcodes.DecodeError, "registers"):
            opcodes.decode_one([0x6E | 0x6 << 12, 0, 0], 0)

    def test_literals_are_sign_extended(self):
        self.assertEqual(opcodes.decode_one([0x12 | 0xF0 << 8], 0).lit, -1)
        self.assertEqual(opcodes.decode_one([0x13, 0x8000], 0).lit, -32768)
        self.assertEqual(opcodes.decode_one([0x19, 0x8000], 0).lit, -(1 << 63))
        self.assertEqual(opcodes.decode_one([0x15, 0x4000], 0).lit, 0x40000000)
        wide = struct.unpack("<q", struct.pack("<4H", 1, 2, 3, 0x8004))[0]
        self.assertEqual(opcodes.decode_one([0x18, 1, 2, 3, 0x8004], 0).lit, wide)


class Hostile(unittest.TestCase):
    """inputs the runtime must refuse with a java error naming the cause"""

    def build_loader(self, builder):
        return dexvm.load(builder.build())

    def raises(self, java, function, *args):
        try:
            function(*args)
        except runtime.api.lookup_host("java.lang.Throwable").py as error:
            self.assertEqual(java_name(error), java, str(error))
            return error
        self.fail("no %s" % java)

    def test_working_method_from_the_builder(self):
        builder = dexbuilder.DexBuilder()
        cls = builder.add_class("LT;")
        cls.method("add", "(II)I", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=3, ins=2,
                   insns=dexbuilder.op_add_int(0, 1, 2) + dexbuilder.op_return(0))
        loader = self.build_loader(builder)
        add = loader.load_class("T").method("add")
        self.assertEqual(add.invoke(2, 3), 5)
        self.assertEqual(add.invoke(2147483647, 1), -2147483648)

    def test_const_method_type_resolves_the_prototype(self):
        builder = dexbuilder.DexBuilder(version=b"039")
        cls = builder.add_class("LT;")
        cls.method("type", "()Ljava/lang/invoke/MethodType;", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC,
                   registers=1, insns=[0xff, 0, 0x11])
        loader = self.build_loader(builder)
        method_type = loader.load_class("T").call_static("type")
        self.assertEqual(method_type.parameterCount(), 0)
        self.assertEqual(method_type.returnType().getName(), "java.lang.invoke.MethodType")
        self.assertEqual(method_type.toMethodDescriptorString(), "()Ljava/lang/invoke/MethodType;")
        self.assertTrue(method_type.equals(loader.load_class("T").call_static("type")))
        with self.assertRaises(api.lookup_host("java.lang.IndexOutOfBoundsException").py):
            method_type.parameterType(-1)

    def test_static_method_handle_constant_and_exact_call(self):
        builder = dexbuilder.DexBuilder(version=b"039")
        cls = builder.add_class("LT;")
        cls.method("add", "(II)I", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=3, ins=2,
                   insns=dexbuilder.op_add_int(0, 1, 2) + dexbuilder.op_return(0))
        cls.method("handle", "()Ljava/lang/invoke/MethodHandle;", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC,
                   registers=1, insns=[0xfe, 0, 0x11])
        cls.method("call", "(Ljava/lang/invoke/MethodHandle;II)I", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC,
                   registers=4, ins=3, insns=[0x30fa, 0, 0x0321, 0, 0x0a, 0x0f])
        mh = builder.add_class("Ljava/lang/invoke/MethodHandle;")
        mh.method("invokeExact", "([Ljava/lang/Object;)Ljava/lang/Object;", dexbuilder.ACC_PUBLIC)
        data = bytearray(builder.build())
        dex = dexformat.DexFile(data)
        index = next(i for i in range(dex.method_count()) if dex.method(i).name == "add")
        invoke = next(i for i in range(dex.method_count()) if dex.method(i).name == "invokeExact")
        proto = next(i for i in range(dex.proto_count()) if dex.proto(i).descriptor() == "(II)I")
        target = next(c for c in dex.class_defs() if dex.type(c.type_idx) == "LT;")
        call_method = next(m for m in dex.class_data(target).direct_methods if dex.method(m.method_idx).name == "call")
        struct.pack_into("<H", data, call_method.code_off + 18, invoke)
        struct.pack_into("<H", data, call_method.code_off + 22, proto)
        map_offset = dex.map_off
        count = struct.unpack_from("<I", data, map_offset)[0]
        handle_offset = len(data) + 12
        data += struct.pack("<HHII", dexformat.TYPE_METHOD_HANDLE_ITEM, 0, 1, handle_offset)
        data += struct.pack("<4H", dexformat.METHOD_HANDLE_INVOKE_STATIC, 0, index, 0)
        struct.pack_into("<I", data, map_offset, count + 1)
        struct.pack_into("<I", data, 32, len(data))
        struct.pack_into("<I", data, 104, len(data) - dex.data_off)
        loader = dexvm.load(dexbuilder.fix_checksums(data))
        owner = loader.load_class("T")
        handle = owner.call_static("handle")
        self.assertEqual(handle.type().toMethodDescriptorString(), "(II)I")
        self.assertEqual(owner.call_static("call", handle, 19, 23), 42)
        call, _ = classes.bind(owner, ("invoke-polymorphic", "Ljava/lang/invoke/MethodHandle;", "invokeExact", "(II)I"))
        self.assertEqual(call(handle, 2, 3), 5)
        widen, _ = classes.bind(owner, ("invoke-polymorphic", "Ljava/lang/invoke/MethodHandle;", "invoke", "(BB)J"))
        self.assertEqual(widen(handle, 2, 3), 5)
        narrow, _ = classes.bind(owner, ("invoke-polymorphic", "Ljava/lang/invoke/MethodHandle;", "invoke", "(JI)I"))
        with self.assertRaises(api.lookup_host("java.lang.invoke.WrongMethodTypeException").py):
            narrow(handle, 2, 3)
        wrong, _ = classes.bind(owner, ("invoke-polymorphic", "Ljava/lang/invoke/MethodHandle;", "invokeExact", "(JI)I"))
        with self.assertRaises(api.lookup_host("java.lang.invoke.WrongMethodTypeException").py):
            wrong(handle, 2, 3)
        with self.assertRaises(api.lookup_host("java.lang.NullPointerException").py):
            call(None, 2, 3)

    def test_field_and_virtual_method_handles(self):
        from types import SimpleNamespace
        loader = dexvm.load(fixture("Objs"))
        owner = loader.load_class("Objs")
        dex = owner.dexfile

        def handle(kind, index):
            proxy = SimpleNamespace(method_handle=lambda _: dexformat.MethodHandleItem(kind, index),
                                    field=dex.field, method=dex.method)
            wrapper = SimpleNamespace(loader=loader, dexfile=proxy)
            return classes._bind_handle_const(wrapper, 0)[0]()

        static_index = next(i for i in range(dex.field_count()) if dex.field(i).class_type == "LObjs;"
                            and dex.field(i).name == "counter")
        get_static = handle(dexformat.METHOD_HANDLE_STATIC_GET, static_index)
        put_static = handle(dexformat.METHOD_HANDLE_STATIC_PUT, static_index)
        put_static._target(123)
        self.assertEqual(get_static._target(), 123)
        self.assertEqual(get_static.type().toMethodDescriptorString(), "()I")
        field_index = next(i for i in range(dex.field_count()) if dex.field(i).class_type == "LObjs$Base;"
                           and dex.field(i).name == "x")
        get_field = handle(dexformat.METHOD_HANDLE_INSTANCE_GET, field_index)
        put_field = handle(dexformat.METHOD_HANDLE_INSTANCE_PUT, field_index)
        obj = loader.load_class("Objs$Derived").new_instance()
        put_field._target(obj, 42)
        self.assertEqual(get_field._target(obj), 42)
        with self.assertRaises(api.lookup_host("java.lang.NullPointerException").py):
            get_field._target(None)
        method_index = next(i for i in range(dex.method_count()) if dex.method(i).class_type == "LObjs$Base;"
                            and dex.method(i).name == "me")
        method = handle(dexformat.METHOD_HANDLE_INVOKE_INSTANCE, method_index)
        self.assertEqual(method._target(obj), "Derived")
        ctor_index = next(i for i in range(dex.method_count()) if dex.method(i).class_type == "LObjs$Counter;"
                          and dex.method(i).name == "<init>" and dex.method(i).proto.descriptor() == "()V")
        constructor = handle(dexformat.METHOD_HANDLE_INVOKE_CONSTRUCTOR, ctor_index)
        counter = constructor._target()
        counter.inc()
        self.assertEqual(counter.get(), 1)
        self.assertEqual(constructor.type().toMethodDescriptorString(), "()LObjs$Counter;")

    def test_method_type_factories_check_parameters_and_preserve_class_identity(self):
        from dexvm.jinvoke import MethodType
        integer = api.PRIMITIVES["I"]
        void = api.PRIMITIVES["V"]
        first = MethodType.methodTypeArray(void, [integer])
        second = MethodType.methodTypeOne(void, integer)
        self.assertTrue(first.equals(second))
        self.assertEqual(first.hashCode(), second.hashCode())
        self.assertEqual(first.toMethodDescriptorString(), "(I)V")
        self.assertIs(first.parameterType(0), integer)
        copy = first.parameterArray()
        copy[0] = void
        self.assertIs(first.parameterType(0), integer)
        with self.assertRaises(api.lookup_host("java.lang.IllegalArgumentException").py):
            MethodType.methodTypeOne(void, void)
        with self.assertRaises(api.lookup_host("java.lang.NullPointerException").py):
            MethodType.methodTypeArray(void, None)
        a = dexvm.load(fixture("Flow")).load_class("Flow")
        b = dexvm.load(fixture("Flow")).load_class("Flow")
        self.assertFalse(MethodType.methodTypeOne(void, a).equals(MethodType.methodTypeOne(void, b)))

    def test_dex_calls_android_system_clock(self):
        builder = dexbuilder.DexBuilder()
        clock = builder.add_class("Landroid/os/SystemClock;")
        clock.method("uptimeMillis", "()J", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC)
        cls = builder.add_class("LT;")
        cls.method("now", "()J", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=2,
                   insns=[0x71, 1, 0, 0x0b, 0x10])
        loader = self.build_loader(builder)
        from android.os import SystemClock
        before = SystemClock.uptimeMillis()
        value = loader.load_class("T").call_static("now")
        self.assertGreaterEqual(value, before)
        self.assertLessEqual(value, SystemClock.uptimeMillis())

    def test_bundle_defaults_through_dex_method_resolution(self):
        from android.os import Bundle
        bundle_class = api.lookup_host("android.os.Bundle")
        bundle = bundle_class.py()
        get_int, _ = classes._bind_virtual(None, "Landroid/os/Bundle;", "getInt", "(Ljava/lang/String;)I")
        put_bool, _ = classes._bind_virtual(None, "Landroid/os/Bundle;", "putBoolean", "(Ljava/lang/String;Z)V")
        get_bool, _ = classes._bind_virtual(None, "Landroid/os/Bundle;", "getBoolean", "(Ljava/lang/String;)Z")
        self.assertEqual(get_int(bundle, "absent"), 0)
        put_bool(bundle, "enabled", 1)
        self.assertEqual(get_bool(bundle, "enabled"), 1)
        self.assertEqual(get_int(bundle, "enabled"), 0)

    def test_unknown_opcode_is_a_verify_error_at_the_first_call(self):
        builder = dexbuilder.DexBuilder()
        cls = builder.add_class("LT;")
        cls.method("bad", "()V", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=1, insns=[0x3E, 0x0E])
        cls.method("fine", "()I", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=1,
                   insns=dexbuilder.op_const4(0, 7) + dexbuilder.op_return(0))
        loader = self.build_loader(builder)
        klass = loader.load_class("T")
        error = self.raises("java.lang.VerifyError", klass.method("bad").invoke)
        self.assertIn("unknown opcode 0x3e", error.getMessage())
        self.assertEqual(klass.method("fine").invoke(), 7)

    def test_method_that_runs_off_its_end(self):
        builder = dexbuilder.DexBuilder()
        cls = builder.add_class("LT;")
        cls.method("open", "()V", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=1,
                   insns=dexbuilder.op_const4(0, 1))
        error = self.raises("java.lang.VerifyError", self.build_loader(builder).load_class("T").method("open").invoke)
        self.assertIn("runs off its end", error.getMessage())

    def test_branch_into_the_middle_of_an_instruction(self):
        builder = dexbuilder.DexBuilder()
        cls = builder.add_class("LT;")
        # const/16 v0, 1 (two units) then goto -1 lands on its second unit
        cls.method("jump", "()V", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=1,
                   insns=[0x13, 0x0001, 0x28 | 0xFF << 8])
        self.raises("java.lang.VerifyError", self.build_loader(builder).load_class("T").method("jump").invoke)

    def test_register_beyond_the_frame(self):
        builder = dexbuilder.DexBuilder()
        cls = builder.add_class("LT;")
        cls.method("wide", "()I", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=1,
                   insns=dexbuilder.op_const4(5, 1) + dexbuilder.op_return(0))
        error = self.raises("java.lang.VerifyError", self.build_loader(builder).load_class("T").method("wide").invoke)
        self.assertIn("register v5", error.getMessage())

    def test_inheritance_cycle(self):
        builder = dexbuilder.DexBuilder()
        builder.add_class("LA;", superclass="LB;")
        builder.add_class("LB;", superclass="LA;")
        loader = self.build_loader(builder)
        self.raises("java.lang.ClassCircularityError", loader.load_class, "A")

    def test_missing_superclass_and_interface(self):
        builder = dexbuilder.DexBuilder()
        builder.add_class("LChild;", superclass="Lgone/Parent;")
        builder.add_class("LImpl;", interfaces=("Lgone/Iface;",))
        loader = self.build_loader(builder)
        error = self.raises("java.lang.NoClassDefFoundError", loader.load_class, "Child")
        self.assertIn("gone.Parent", error.getMessage())
        self.raises("java.lang.NoClassDefFoundError", loader.load_class, "Impl")

    def test_class_hierarchy_violations(self):
        builder = dexbuilder.DexBuilder()
        builder.add_class("LIface;", access=dexbuilder.ACC_INTERFACE | dexbuilder.ACC_ABSTRACT)
        builder.add_class("LExtendsInterface;", superclass="LIface;")
        builder.add_class("LImplementsClass;", interfaces=("Ljava/lang/Object;",))
        builder.add_class("LFinalBase;", access=dexbuilder.ACC_FINAL | dexbuilder.ACC_PUBLIC)
        builder.add_class("LExtendsFinal;", superclass="LFinalBase;")
        loader = self.build_loader(builder)
        self.raises("java.lang.IncompatibleClassChangeError", loader.load_class, "ExtendsInterface")
        self.raises("java.lang.IncompatibleClassChangeError", loader.load_class, "ImplementsClass")
        self.raises("java.lang.IncompatibleClassChangeError", loader.load_class, "ExtendsFinal")

    def test_final_host_superclass(self):
        builder = dexbuilder.DexBuilder()
        builder.add_class("LMyString;", superclass="Ljava/lang/String;")
        self.raises("java.lang.VerifyError", self.build_loader(builder).load_class, "MyString")

    def test_method_that_does_not_exist(self):
        loader = dexvm.load(fixture("Flow"))
        with self.assertRaises(AttributeError):
            loader.load_class("Flow").call_static("nothing")

    def test_abstract_class_cannot_be_instantiated(self):
        loader = dexvm.load(fixture("Objs"))
        self.raises("java.lang.InstantiationError", loader.load_class("Objs$Shape").new_instance)


class Deps(unittest.TestCase):
    def test_missing_class_is_reported_at_its_own_instruction(self):
        loader = dexvm.load(fixture("Deps"))
        deps = loader.load_class("Deps")
        self.assertEqual(deps.call_static("works"), 42)
        self.assertEqual(deps.call_static("run"), "ncdfe;ncdfe2;ncdfe3;skip;ncdfe4;ncdfe5;")

    def test_late_added_dex_resolves_the_class(self):
        loader = dexvm.load(fixture("Deps"))
        self.assertEqual(loader.load_class("Deps").call_static("run"), "ncdfe;ncdfe2;ncdfe3;skip;ncdfe4;ncdfe5;")
        self.assertIsNone(loader.load_class("Flow"))
        loader.add_dex(dexformat.DexFile(fixture("Flow")))
        self.assertIsNotNone(loader.load_class("Flow"))


class Loaders(unittest.TestCase):
    def test_parent_first_and_delegate_last(self):
        parent = dexvm.load(fixture("Flow"), name="parent")
        child_first = classes.VMLoader([dexformat.DexFile(fixture("Flow"))], parent=parent)
        child_last = classes.VMLoader([dexformat.DexFile(fixture("Flow"))], parent=parent, delegate_last=True)
        in_parent = parent.load_class("Flow")
        self.assertIs(child_first.load_class("Flow"), in_parent)
        own = child_last.load_class("Flow")
        self.assertIsNot(own, in_parent)
        self.assertIs(own.loader, child_last)
        self.assertEqual(own.call_static("fib", 12), 144)

    def test_host_classes_come_before_the_dex_of_a_delegate_last_loader(self):
        loader = classes.VMLoader([], delegate_last=True)
        self.assertIs(loader.load_class("java.lang.String"), api.lookup_host("java.lang.String"))

    def test_classes_of_two_loaders_are_distinct_types(self):
        a = dexvm.load(fixture("Objs"))
        b = dexvm.load(fixture("Objs"))
        rect_a = a.load_class("Objs$Rect")
        rect_b = b.load_class("Objs$Rect")
        self.assertIsNot(rect_a, rect_b)
        obj = rect_a.new_instance()
        self.assertTrue(rect_a.isInstance(obj))
        self.assertFalse(rect_b.isInstance(obj))

    def test_loaded_classes_are_remembered(self):
        loader = dexvm.load(fixture("Objs"))
        self.assertIs(loader.load_class("Objs"), loader.load_class("Objs"))

    def test_array_and_primitive_descriptors(self):
        loader = dexvm.load(fixture("Objs"))
        array = loader.load_or_none("[I")
        self.assertTrue(array.isArray())
        self.assertIs(array.getComponentType(), api.PRIMITIVES["I"])
        own = loader.load_or_none("[LObjs;")
        self.assertIs(own.getComponentType(), loader.load_class("Objs"))
        self.assertIs(loader.load_or_none("[LObjs;"), own)


class Initialisation(unittest.TestCase):
    def test_static_initialiser_runs_once_at_first_use(self):
        loader = dexvm.load(fixture("Objs"))
        lazy = loader.load_class("Objs$Lazy")
        self.assertEqual(lazy.state, classes.UNINITIALIZED)
        objs = loader.load_class("Objs")
        counter = objs.pytype.__dict__[api.field_attr("LObjs;", "counter", True)]
        self.assertEqual(counter, 0)
        objs.call_static("run")
        self.assertEqual(lazy.state, classes.INITIALIZED)

    def test_failed_initialiser_poisons_the_class(self):
        loader = dexvm.load(fixture("Objs"))
        boom = loader.load_class("Objs$Boom")
        for expected_error in ("java.lang.ExceptionInInitializerError", "java.lang.NoClassDefFoundError"):
            with self.assertRaises(api.lookup_host("java.lang.Error").py) as caught:
                boom.ensure_initialized()
            self.assertEqual(java_name(caught.exception), expected_error)
        self.assertEqual(boom.state, classes.ERRONEOUS)


class Numbers(unittest.TestCase):
    def test_float_text_matches_java(self):
        from dexvm import jlang
        cases = ((1.0, False, "1.0"), (1e7, False, "1.0E7"), (9999999.0, False, "9999999.0"), (0.001, False, "0.001"),
                 (0.0001, False, "1.0E-4"), (123456789.0, False, "1.23456789E8"), (5e-324, False, "4.9E-324"),
                 (1.7976931348623157e308, False, "1.7976931348623157E308"), (-0.0, False, "-0.0"),
                 (2e23, False, "2.0E23"), (100.0, False, "100.0"), (1.0e21, False, "1.0E21"))
        for value, single, text in cases:
            self.assertEqual(jlang.float_to_string(value, single), text)
        single = ((16777216.0, "1.6777216E7"), (0.1, None), (3.4028235e38, "3.4028235E38"), (1e-45, "1.4E-45"),
                  (1.17549435e-38, "1.1754944E-38"))
        for value, text in single:
            value = runtime.f32(value)
            if text is not None:
                self.assertEqual(jlang.float_to_string(value, True), text)
        self.assertEqual(jlang.float_to_string(runtime.f32(0.1), True), "0.1")

    def test_division_and_remainder_follow_java(self):
        self.assertEqual(runtime.idiv(-7, 2), -3)
        self.assertEqual(runtime.irem(-7, 2), -1)
        self.assertEqual(runtime.idiv(runtime.INT_MIN, -1), runtime.INT_MIN)
        self.assertEqual(runtime.ldiv(runtime.LONG_MIN, -1), runtime.LONG_MIN)
        self.assertEqual(runtime.irem(7, -2), 1)
        with self.assertRaises(api.lookup_host("java.lang.ArithmeticException").py):
            runtime.idiv(1, 0)

    def test_float_to_integer_saturates(self):
        self.assertEqual(runtime.d2i(1e20), runtime.INT_MAX)
        self.assertEqual(runtime.d2i(-1e20), runtime.INT_MIN)
        self.assertEqual(runtime.d2i(float("nan")), 0)
        self.assertEqual(runtime.d2l(1e30), runtime.LONG_MAX)
        self.assertEqual(runtime.d2i(-3.99), -3)

    def test_float32_rounding(self):
        self.assertEqual(runtime.f32(0.1), 0.10000000149011612)
        self.assertEqual(runtime.f32(1e39), float("inf"))
        self.assertEqual(runtime.f32(-1e39), float("-inf"))

    def test_remainder_of_floats(self):
        self.assertTrue(runtime.drem(5.0, 0.0) != runtime.drem(5.0, 0.0))
        self.assertEqual(runtime.drem(5.0, float("inf")), 5.0)
        self.assertEqual(runtime.drem(-5.5, 2.0), -1.5)

    def test_const_bits_read_as_float(self):
        self.assertEqual(runtime.bits_to_float(0x3F800000), 1.0)
        self.assertEqual(runtime.bits_to_double(0x3FF0000000000000), 1.0)
        self.assertEqual(runtime.as_float(0), 0.0)
        self.assertEqual(runtime.as_float(2.5), 2.5)


class Translation(unittest.TestCase):
    def test_straight_line_method_has_no_dispatch_loop(self):
        dex = dexformat.DexFile(fixture("Arith"))
        for class_def in dex.class_defs():
            for method in dex.class_data(class_def).direct_methods:
                if dex.method(method.method_idx).name == "idiv":
                    code = dex.code(method.code_off)
                    mid = dex.method(method.method_idx)
                    result = translate.translate(dex, code, mid.name, mid.proto, method.access, "LArith;")
                    self.assertNotIn("while True", result.source)
                    self.assertIn("_idiv", result.source)

    def test_loops_use_the_block_dispatcher_and_exceptions_a_handler_table(self):
        dex = dexformat.DexFile(fixture("Flow"))
        found = {}
        for class_def in dex.class_defs():
            data = dex.class_data(class_def)
            for method in data.direct_methods:
                mid = dex.method(method.method_idx)
                code = dex.code(method.code_off)
                if code:
                    found[mid.name] = translate.translate(dex, code, mid.name, mid.proto, method.access, "LFlow;")
        self.assertIn("while True", found["collatz"].source)
        self.assertEqual(found["collatz"].handlers, {})
        self.assertTrue(found["fin"].handlers)
        self.assertIn("except Exception", found["fin"].source)

    def test_generated_code_is_cached_per_method_and_used_again(self):
        loader = dexvm.load(fixture("Flow"))
        flow = loader.load_class("Flow")
        method = flow.method("fib")
        self.assertIsNone(method._function)
        first = method.function()
        self.assertIs(method.function(), first)

    def test_register_pairs_of_wide_arguments(self):
        loader = dexvm.load(fixture("Arith"))
        arith = loader.load_class("Arith")
        self.assertEqual(arith.call_static("ldiv", 100, 7), 14)
        self.assertEqual(arith.call_static("lrem", -100, 7), -2)
        self.assertEqual(arith.call_static("idiv", -7, 2), -3)


class Real(unittest.TestCase):
    """files this repository does not hold; the tests run where the paths are given"""

    def test_every_method_of_a_real_application_translates(self):
        path = os.environ.get("EXTERIA_DEXVM_APK")
        if not path or not os.path.exists(path):
            self.skipTest("EXTERIA_DEXVM_APK is not set")
        with open(path, "rb") as handle:
            files = container.load_container(handle.read())
        problems = []
        total = 0
        for dex in files:
            for class_def in dex.class_defs():
                descriptor = dex.type(class_def.type_idx)
                data = dex.class_data(class_def)
                for method in data.direct_methods + data.virtual_methods:
                    code = dex.code(method.code_off)
                    if code is None:
                        continue
                    mid = dex.method(method.method_idx)
                    total += 1
                    try:
                        result = translate.translate(dex, code, mid.name, mid.proto, method.access, descriptor,
                                                     uid=str(method.method_idx))
                        compile(result.source, "<test>", "exec")
                    except Exception as error:
                        problems.append("%s.%s: %s" % (descriptor, mid.name, error))
        self.assertGreater(total, 0)
        self.assertEqual(problems[:5], [], "%d of %d methods failed" % (len(problems), total))


if __name__ == "__main__":
    unittest.main()
