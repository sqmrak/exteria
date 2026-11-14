"""the second round of the library of the dex runtime: java.time, java.text, ciphers and signatures, atomics, pipes, jar manifests, handlers and
loopers, sqlite, android.util json and collections. values are the ones the jdk and android document (FIPS 197, NIST GCM, RFC 6070 vectors)"""

import os
import sys
import tempfile
import threading
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fakeapp  # noqa: E402,F401

sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import dexvm  # noqa: E402,F401
from dexvm import api, runtime  # noqa: E402
from dexvm.jio import to_java_bytes  # noqa: E402


def J(name):
    return api.lookup_host(name).py


def raw(array):
    return bytes(b & 0xFF for b in array)


class JavaTime(unittest.TestCase):
    def test_local_date_arithmetic_follows_java(self):
        LD = J("java.time.LocalDate")
        d = LD.of(2024, 1, 31)
        self.assertEqual((d.plusMonths(1).toString(), d.plusYears(1).toString(), d.getDayOfWeek().name(), d.getDayOfYear()),
                         ("2024-02-29", "2025-01-31", "WEDNESDAY", 31))
        self.assertEqual(LD.parse("2024-02-29").until(LD.of(2025, 3, 1)).toString(), "P1Y1D")
        self.assertEqual(J("java.time.temporal.ChronoUnit").MONTHS.between(LD.of(2024, 1, 31), LD.of(2024, 3, 30)), 1)
        with self.assertRaises(J("java.time.DateTimeException")) as caught:
            LD.of(2023, 2, 29)
        self.assertIn("not a leap year", caught.exception.getMessage())

    def test_zoned_and_instant_text(self):
        Z, ZD, LDT, I = J("java.time.ZoneId"), J("java.time.ZonedDateTime"), J("java.time.LocalDateTime"), J("java.time.Instant")
        moscow = ZD.of(LDT.of(2024, 6, 1, 12, 0), Z.of("Europe/Moscow"))
        self.assertEqual(moscow.toString(), "2024-06-01T12:00+03:00[Europe/Moscow]")
        self.assertEqual(moscow.toInstant().toString(), "2024-06-01T09:00:00Z")
        self.assertEqual(moscow.withZoneSameInstant(Z.of("UTC")).toString(), "2024-06-01T09:00Z[UTC]")
        self.assertEqual(I.ofEpochSecond(1700000000).toString(), "2023-11-14T22:13:20Z")
        self.assertEqual(I.parse("2023-11-14T22:13:20Z").toEpochMilli(), 1700000000000)

    def test_duration_period_and_formatter(self):
        D, P, F, LDT = J("java.time.Duration"), J("java.time.Period"), J("java.time.format.DateTimeFormatter"), J("java.time.LocalDateTime")
        self.assertEqual((D.ofSeconds(3725).toString(), D.ofMillis(-1500).toString(), D.parse("PT1H30M").toMinutes()), ("PT1H2M5S", "PT-1.5S", 90))
        self.assertEqual(P.of(1, 2, 3).toString(), "P1Y2M3D")
        f = F.ofPattern("yyyy-MM-dd HH:mm:ss EEE MMM a hh")
        self.assertEqual(f.format(LDT.of(2024, 3, 5, 15, 4, 9)), "2024-03-05 15:04:09 Tue Mar PM 03")
        self.assertEqual(LDT.parse("2024-03-05 15:04:09", F.ofPattern("yyyy-MM-dd HH:mm:ss")).toString(), "2024-03-05T15:04:09")
        with self.assertRaises(J("java.time.format.DateTimeParseException")):
            J("java.time.LocalDate").parse("05/03/2024", F.ofPattern("dd.MM.yyyy"))


class JavaText(unittest.TestCase):
    def test_decimal_format_rounds_half_even_on_the_exact_value(self):
        D = J("java.text.DecimalFormat")
        cases = (("#,##0.00", 1234567.891, "1,234,567.89"), ("0.00", 2.005, "2.00"), ("0.00", 1.005, "1.00"), ("#.##", 3.0, "3"),
                 ("000.0", 5.55, "005.5"), ("#,##0.00;(#,##0.00)", -12.3, "(12.30)"), ("0.0%", 0.256, "25.6%"), ("#", 2.5, "2"), ("#", 3.5, "4"))
        for pattern, value, expected in cases:
            self.assertEqual(D(pattern).format(value), expected, pattern)

    def test_message_format_and_choice(self):
        MF = J("java.text.MessageFormat")
        self.assertEqual(MF.static_format("{0} has {1,number,#.#} items and {2,choice,0#none|1#one|1<many {2}}", ["x", 3.14159, 5]),
                         "x has 3.1 items and many 5")
        self.assertEqual(MF("it''s {0}").format(["ok"]), "it's ok")

    def test_normalizer_collator_and_breaks(self):
        self.assertEqual(len(J("java.text.Normalizer").normalize("é", J("java.text.Normalizer$Form").NFD)), 2)
        self.assertLess(J("java.text.Collator").getInstance().compare("a", "B"), 0)
        bi = J("java.text.BreakIterator").getWordInstance()
        bi.setText("Hello, big world.")
        bounds = [bi.first()]
        while True:
            n = bi.next()
            if n < 0:
                break
            bounds.append(n)
        self.assertEqual(bounds, [0, 5, 6, 7, 10, 11, 16, 17])


class Crypto(unittest.TestCase):
    def cipher(self, transformation, mode, key, spec, data, aad=None):
        c = J("javax.crypto.Cipher").getInstance(transformation)
        c.init(mode, J("javax.crypto.spec.SecretKeySpec")(to_java_bytes(key), "AES"), spec)
        if aad:
            c.updateAAD(to_java_bytes(aad))
        return raw(c.doFinal(to_java_bytes(data)))

    def test_aes_block_matches_fips_197(self):
        from dexvm.jcrypto import _AES
        plain = bytes.fromhex("00112233445566778899aabbccddeeff")
        self.assertEqual(_AES(bytes(range(16))).encrypt_block(plain).hex(), "69c4e0d86a7b0430d8cdb78070b4c55a")
        self.assertEqual(_AES(bytes(range(32))).encrypt_block(plain).hex(), "8ea2b7ca516745bfeafc49904b496089")
        self.assertEqual(_AES(bytes(range(16))).decrypt_block(bytes.fromhex("69c4e0d86a7b0430d8cdb78070b4c55a")), plain)

    def test_gcm_matches_nist_test_case_4_and_rejects_a_bad_tag(self):
        key = bytes.fromhex("feffe9928665731c6d6a8f9467308308")
        iv = bytes.fromhex("cafebabefacedbaddecaf888")
        plain = bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")
        aad = bytes.fromhex("feedfacedeadbeeffeedfacedeadbeefabaddad2")
        spec = J("javax.crypto.spec.GCMParameterSpec")(128, to_java_bytes(iv))
        sealed = self.cipher("AES/GCM/NoPadding", 1, key, spec, plain, aad)
        self.assertEqual(sealed[-16:].hex(), "5bc94fbc3221a5db94fae95ae7121a47")
        self.assertEqual(self.cipher("AES/GCM/NoPadding", 2, key, spec, sealed, aad), plain)
        tampered = bytes([sealed[0] ^ 1]) + sealed[1:]
        with self.assertRaises(J("javax.crypto.AEADBadTagException")):
            self.cipher("AES/GCM/NoPadding", 2, key, spec, tampered, aad)

    def test_cbc_padding_and_ctr_round_trip(self):
        key = bytes(range(16))
        spec = J("javax.crypto.spec.IvParameterSpec")(to_java_bytes(bytes(range(16))))
        sealed = self.cipher("AES/CBC/PKCS5Padding", 1, key, spec, b"hello world")
        self.assertEqual((len(sealed), self.cipher("AES/CBC/PKCS5Padding", 2, key, spec, sealed)), (16, b"hello world"))
        with self.assertRaises(J("javax.crypto.BadPaddingException")):
            self.cipher("AES/CBC/PKCS5Padding", 2, bytes(16), spec, sealed)
        ctr = self.cipher("AES/CTR/NoPadding", 1, key, spec, b"hello world")
        self.assertEqual(self.cipher("AES/CTR/NoPadding", 2, key, spec, ctr), b"hello world")

    def test_pbkdf2_matches_rfc_6070_and_unknown_algorithms_are_named(self):
        chars = runtime.new_array("[C", 0)
        chars.extend(map(ord, "password"))
        factory = J("javax.crypto.SecretKeyFactory").getInstance("PBKDF2WithHmacSHA1")
        key = factory.generateSecret(J("javax.crypto.spec.PBEKeySpec")(chars, to_java_bytes(b"salt"), 2, 160))
        self.assertEqual(raw(key.getEncoded()).hex(), "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957")
        with self.assertRaises(J("java.security.NoSuchAlgorithmException")):
            J("javax.crypto.Cipher").getInstance("DES/CBC/PKCS5Padding")

    def test_rsa_sign_verify_and_encrypt(self):
        generator = J("java.security.KeyPairGenerator").getInstance("RSA")
        generator.initialize(1024)
        pair = generator.generateKeyPair()
        signer = J("java.security.Signature").getInstance("SHA256withRSA")
        signer.initSign(pair.getPrivate())
        signer.update(to_java_bytes(b"msg"))
        signature = signer.sign()
        verifier = J("java.security.Signature").getInstance("SHA256withRSA")
        verifier.initVerify(pair.getPublic())
        verifier.update(to_java_bytes(b"msg"))
        self.assertEqual(verifier.verify(signature), 1)
        verifier.initVerify(pair.getPublic())
        verifier.update(to_java_bytes(b"other"))
        self.assertEqual(verifier.verify(signature), 0)
        factory = J("java.security.KeyFactory").getInstance("RSA")
        public = factory.generatePublic(J("java.security.spec.X509EncodedKeySpec")(pair.getPublic().getEncoded()))
        private = factory.generatePrivate(J("java.security.spec.PKCS8EncodedKeySpec")(pair.getPrivate().getEncoded()))
        for padding in ("RSA/ECB/PKCS1Padding", "RSA/ECB/OAEPWithSHA-256AndMGF1Padding"):
            sealing = J("javax.crypto.Cipher").getInstance(padding)
            sealing.init(1, public)
            opening = J("javax.crypto.Cipher").getInstance(padding)
            opening.init(2, private)
            self.assertEqual(raw(opening.doFinal(sealing.doFinal(to_java_bytes(b"secret")))), b"secret")


class Concurrency(unittest.TestCase):
    def test_atomic_arrays_adders_and_accumulators(self):
        a = J("java.util.concurrent.atomic.AtomicIntegerArray")(3)
        self.assertEqual((a.incrementAndGet(1), a.getAndAdd(1, 5), a.toString()), (1, 1, "[0, 6, 0]"))
        adder = J("java.util.concurrent.atomic.LongAdder")()
        adder.increment()
        adder.add(4)
        self.assertEqual(adder.sum(), 5)

    def test_cyclic_barrier_releases_both_parties(self):
        barrier = J("java.util.concurrent.CyclicBarrier")(2)
        seen = []
        worker = threading.Thread(target=lambda: seen.append(barrier.await_()))
        worker.start()
        barrier.await_()
        worker.join(2)
        self.assertEqual(len(seen), 1)

    def test_piped_streams_and_sequence_streams(self):
        sink = J("java.io.PipedInputStream")()
        source = J("java.io.PipedOutputStream")(sink)
        source.write_byte(65)
        source.close()
        self.assertEqual((sink.read_byte(), sink.read_byte()), (65, -1))
        joined = J("java.io.SequenceInputStream")(J("java.io.ByteArrayInputStream")(to_java_bytes(b"ab")),
                                                  J("java.io.ByteArrayInputStream")(to_java_bytes(b"cd")))
        self.assertEqual(raw(joined.readAllBytes()), b"abcd")

    def test_jar_manifest_round_trip(self):
        manifest = J("java.util.jar.Manifest")()
        manifest.getMainAttributes().putValue("Manifest-Version", "1.0")
        manifest.getMainAttributes().putValue("Main-Class", "a.B")
        out = J("java.io.ByteArrayOutputStream")()
        manifest.write(out)
        self.assertEqual(raw(out.toByteArray()), b"Manifest-Version: 1.0\r\nMain-Class: a.B\r\n\r\n")
        again = J("java.util.jar.Manifest")(J("java.io.ByteArrayInputStream")(out.toByteArray()))
        self.assertEqual(again.getMainAttributes().getValue("main-class"), "a.B")


class AndroidRound2(unittest.TestCase):
    def test_handler_thread_runs_messages_and_runnables_in_order(self):
        from android.os import Handler, HandlerThread
        thread = HandlerThread("worker")
        thread.start()
        got = []

        class Echo(Handler):
            def handleMessage(self, message):
                got.append((message.what, message.arg1, message.obj, threading.current_thread().name))

        handler = Echo(thread.getLooper())
        handler.sendMessage(handler.obtainMessage(3, 7, 0, "x"))
        handler.post(lambda: got.append("run"))
        handler.sendEmptyMessageDelayed(4, 30)
        deadline = time.time() + 2
        while len(got) < 3 and time.time() < deadline:
            time.sleep(0.01)
        thread.quit()
        self.assertEqual(got, [(3, 7, "x", "worker"), "run", (4, 0, None, "worker")])

    def test_removed_messages_do_not_arrive(self):
        from android.os import Handler, HandlerThread
        thread = HandlerThread("w2")
        thread.start()
        got = []
        handler = Handler(thread.getLooper(), type("C", (), {"handleMessage": lambda self, m: got.append(m.what) or True})())
        handler.sendEmptyMessageDelayed(1, 100)
        self.assertTrue(handler.hasMessages(1))
        handler.removeMessages(1)
        time.sleep(0.2)
        thread.quit()
        self.assertEqual(got, [])

    def test_sqlite_helper_creates_upgrades_and_rolls_back(self):
        from android.app import activity
        from android.content import ContentValues
        from android.database.sqlite import SQLiteConstraintException, SQLiteOpenHelper

        class Helper(SQLiteOpenHelper):
            def onCreate(self, db):
                db.execSQL("create table t(id integer primary key, name text unique, n real)")

        helper = Helper(activity(), "round2-%d.db" % os.getpid(), None, 1)
        db = helper.getWritableDatabase()
        try:
            values = ContentValues()
            values.put("name", "a")
            values.put("n", 2.5)
            self.assertEqual(db.insert("t", None, values), 1)
            with self.assertRaises(SQLiteConstraintException):
                db.insertOrThrow("t", None, values)
            db.beginTransaction()
            other = ContentValues()
            other.put("name", "b")
            db.insert("t", None, other)
            db.endTransaction()
            cursor = db.query("t", ["id", "name", "n"], "name=?", ["a"], None, None, None)
            self.assertEqual((cursor.getCount(), cursor.moveToFirst(), cursor.getString(1), cursor.getDouble(2)), (1, True, "a", 2.5))
            self.assertEqual((db.getVersion(), db.delete("t", None, None)), (1, 1))
        finally:
            db.close()
            path = helper._context.getDatabasePath(helper.getDatabaseName()).getPath()
            if os.path.exists(path):
                os.remove(path)

    def test_json_reader_and_writer(self):
        from android.util import JsonReader, JsonWriter
        from dexvm.jio import StringReader, StringWriter
        reader = JsonReader(StringReader('{"a":[1,2,{"b":true}],"c":null}'))
        reader.beginObject()
        self.assertEqual(reader.nextName(), "a")
        reader.beginArray()
        self.assertEqual((reader.nextInt(), reader.nextInt()), (1, 2))
        reader.skipValue()
        reader.endArray()
        self.assertEqual(reader.nextName(), "c")
        reader.nextNull()
        reader.endObject()
        sink = StringWriter()
        writer = JsonWriter(sink)
        writer.beginObject().name("x").value(1).name("y").beginArray().value("s").value(True).endArray().endObject()
        self.assertEqual(sink.toString(), '{"x":1,"y":["s",true]}')

    def test_array_map_has_positions_and_static_layout_breaks_lines(self):
        from android.text import StaticLayout, TextPaint
        from android.util import ArrayMap
        m = ArrayMap()
        m.put("a", 1)
        m.put("b", 2)
        self.assertEqual((m.indexOfKey("b"), m.keyAt(1), m.removeAt(0), m.size()), (1, "b", 1, 1))
        paint = TextPaint()
        paint.setTextSize(10)
        layout = StaticLayout("hello big wide world of words", paint, 60)
        self.assertEqual([layout.getText()[layout.getLineStart(i):layout.getLineEnd(i)] for i in range(layout.getLineCount())],
                         ["hello big ", "wide world ", "of words"])


if __name__ == "__main__":
    unittest.main()
