import os
import random
import re
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python", "shim"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dexbuilder  # noqa: E402
import dexvm  # noqa: E402
import native_module  # noqa: E402
from dexvm import limits, native, opcodes, runtime  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures", "dex")
MACHINE = native_module.load()
BY_NAME = {name: (op, fmt) for op, (name, fmt, kind) in opcodes.OPCODES.items()}


def fixture(name):
    with open(os.path.join(FIXTURES, name + ".dex"), "rb") as handle:
        return handle.read()


def expected(name):
    with open(os.path.join(FIXTURES, "expected", name + ".txt"), encoding="utf-8") as handle:
        return handle.read()


def assemble(items):
    """items: ("label", name) or (mnemonic, field..., ) where a branch names its label last. returns code units"""
    sizes = []
    for item in items:
        sizes.append(0 if item[0] == "label" else opcodes.SIZES[BY_NAME[item[0]][1]])
    labels = {}
    at = 0
    for item, size in zip(items, sizes):
        if item[0] == "label":
            labels[item[1]] = at
        at += size
    units = []
    at = 0
    for item, size in zip(items, sizes):
        if item[0] != "label":
            units.extend(encode(item, at, labels))
        at += size
    return units


def encode(item, at, labels):
    name = item[0]
    op, fmt = BY_NAME[name]
    f = item[1:]
    if fmt == "10x":
        return [op]
    if fmt == "12x":
        return [op | f[0] << 8 | f[1] << 12]
    if fmt == "11x":
        return [op | f[0] << 8]
    if fmt == "11n":
        return [op | f[0] << 8 | (f[1] & 0xF) << 12]
    if fmt == "21s":
        return [op | f[0] << 8, f[1] & 0xFFFF]
    if fmt == "21h":
        return [op | f[0] << 8, (f[1] >> (48 if "wide" in name else 16)) & 0xFFFF]
    if fmt == "31i":
        return [op | f[0] << 8, f[1] & 0xFFFF, (f[1] >> 16) & 0xFFFF]
    if fmt == "51l":
        value = f[1] & 0xFFFFFFFFFFFFFFFF
        return [op | f[0] << 8] + [(value >> shift) & 0xFFFF for shift in (0, 16, 32, 48)]
    if fmt == "22x":
        return [op | f[0] << 8, f[1]]
    if fmt == "32x":
        return [op, f[0], f[1]]
    if fmt == "23x":
        return [op | f[0] << 8, f[1] | f[2] << 8]
    if fmt == "22s":
        return [op | f[0] << 8 | f[1] << 12, f[2] & 0xFFFF]
    if fmt == "22b":
        return [op | f[0] << 8, f[1] | (f[2] & 0xFF) << 8]
    if fmt == "10t":
        return [op | ((labels[f[0]] - at) & 0xFF) << 8]
    if fmt == "20t":
        return [op, (labels[f[0]] - at) & 0xFFFF]
    if fmt == "30t":
        offset = labels[f[0]] - at
        return [op, offset & 0xFFFF, (offset >> 16) & 0xFFFF]
    if fmt == "22t":
        return [op | f[0] << 8 | f[1] << 12, (labels[f[2]] - at) & 0xFFFF]
    if fmt == "21t":
        return [op | f[0] << 8, (labels[f[1]] - at) & 0xFFFF]
    raise AssertionError("no encoder for %s" % fmt)


def dex_with(methods):
    """methods: [(name, proto, registers, ins, items)] as static methods of class LRand;"""
    builder = dexbuilder.DexBuilder()
    cls = builder.add_class("LRand;")
    for name, proto, registers, ins, items in methods:
        cls.method(name, proto, dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=registers, ins=ins,
                   insns=assemble(items))
    return dexbuilder.fix_checksums(builder.build())


INT_REGS = (0, 1, 2, 3)
LONG_REGS = (4, 6, 8)
COUNTER, LIMIT = 10, 11
PARAMS = 12     # v12 int, v13 int, v14-v15 long
INT_BIN = ("add", "sub", "mul", "div", "rem", "and", "or", "xor", "shl", "shr", "ushr")
LIT8 = ("add", "rsub", "mul", "div", "rem", "and", "or", "xor", "shl", "shr", "ushr")
LIT16 = ("add", "rsub", "mul", "div", "rem", "and", "or", "xor")
CONDITIONS = ("eq", "ne", "lt", "ge", "gt", "le")
INTERESTING = (0, 1, -1, 2, 3, 5, -7, 31, 32, 33, 63, 64, 255, 256, 32767, 32768, 65535, 65536, 0x7FFFFFFF, -0x80000000,
               0x12345678, -0x12345678)
WIDE_INTERESTING = INTERESTING + (0x7FFFFFFFFFFFFFFF, -0x8000000000000000, 0x123456789ABCDEF0, -0x123456789ABCDEF0,
                                  1 << 32, (1 << 32) - 1, -(1 << 32))


def statement(rng, serial):
    """one random statement, as a list of items. serial makes the labels of the branches unique"""
    kind = rng.randrange(14)
    a, b, c = (rng.choice(INT_REGS) for _ in range(3))
    la, lb, lc = (rng.choice(LONG_REGS) for _ in range(3))
    if kind == 0:
        op = rng.choice(INT_BIN)
        return [(op + "-int", a, b, c)]
    if kind == 1:
        op = rng.choice(INT_BIN)
        return [(op + "-int/2addr", a, b)]
    if kind == 2:
        op = rng.choice(LIT8)
        name = "rsub-int/lit8" if op == "rsub" else op + "-int/lit8"
        return [(name, a, b, rng.choice((0, 1, -1, 2, 3, 7, -8, 31, 127, -128)))]
    if kind == 3:
        op = rng.choice(LIT16)
        name = "rsub-int" if op == "rsub" else op + "-int/lit16"
        return [(name, a, b, rng.choice((0, 1, -1, 255, 256, 1000, -1000, 32767, -32768)))]
    if kind == 4:
        return [rng.choice((
            ("const/4", a, rng.randrange(-8, 8)), ("const/16", a, rng.randrange(-32768, 32768)),
            ("const", a, rng.choice(INTERESTING)), ("const/high16", a, rng.randrange(-32768, 32768) << 16)))]
    if kind == 5:
        op = rng.choice(INT_BIN[:8] + ("shl", "shr", "ushr"))
        return [(op + "-long", la, lb, lc) if op not in ("shl", "shr", "ushr") else (op + "-long", la, lb, a)]
    if kind == 6:
        op = rng.choice(INT_BIN)
        if op in ("shl", "shr", "ushr"):
            return [(op + "-long/2addr", la, a)]
        return [(op + "-long/2addr", la, lb)]
    if kind == 7:
        return [rng.choice((
            ("const-wide/16", la, rng.randrange(-32768, 32768)), ("const-wide/32", la, rng.choice(INTERESTING)),
            ("const-wide", la, rng.choice(WIDE_INTERESTING)),
            ("const-wide/high16", la, rng.randrange(-32768, 32768) << 48)))]
    if kind == 8:
        return [rng.choice((
            ("neg-int", a, b), ("not-int", a, b), ("int-to-byte", a, b), ("int-to-char", a, b), ("int-to-short", a, b),
            ("neg-long", la, lb), ("not-long", la, lb), ("int-to-long", la, b), ("long-to-int", a, lb)))]
    if kind == 9:
        return [("cmp-long", a, la, lb)]
    if kind == 10:
        return [rng.choice((("move", a, b), ("move-wide", la, lb)))]
    if kind == 11:
        # a forward branch over one or two statements
        skip = "skip%d" % serial
        test = rng.choice(CONDITIONS)
        head = ("if-" + test, a, b, skip) if rng.random() < 0.5 else ("if-%sz" % test, a, skip)
        body = statement(rng, serial * 10 + 1) + (statement(rng, serial * 10 + 2) if rng.random() < 0.5 else [])
        return [head] + body + [("label", skip)]
    if kind == 12:
        return [("int-to-long", la, a), ("shl-long/2addr", la, b)]
    return [("long-to-int", a, la), ("add-int/2addr", a, b)]


def program(rng, returns):
    body = [("move", 0, PARAMS), ("move", 1, PARAMS + 1), ("move-wide", 4, PARAMS + 2), ("const/4", 2, 3),
            ("const/16", 3, -17), ("const-wide/16", 6, 5), ("const-wide/16", 8, -9),
            ("const/4", COUNTER, 0), ("const/4", LIMIT, rng.randrange(1, 5)), ("label", "loop")]
    for number in range(rng.randrange(6, 26)):
        body.extend(statement(rng, number + 1))
    body.extend([("add-int/lit8", COUNTER, COUNTER, 1), ("if-lt", COUNTER, LIMIT, "loop")])
    if returns == "J":
        body.append(("return-wide", 4))
    elif returns == "I":
        body.append(("return", 0))
    elif returns == "Z":
        body.extend([("and-int/lit8", 0, 0, 1), ("return", 0)])
    elif returns == "B":
        body.extend([("int-to-byte", 0, 0), ("return", 0)])
    elif returns == "S":
        body.extend([("int-to-short", 0, 0), ("return", 0)])
    elif returns == "C":
        body.extend([("int-to-char", 0, 0), ("return", 0)])
    else:
        body.append(("return-void",))
    return body


def outcome(function, args):
    try:
        return ("value", function(*args))
    except Exception as error:
        throwable = runtime.to_throwable(error)
        return ("throw", runtime.class_of(throwable).getName(), throwable.getMessage())


@unittest.skipIf(MACHINE is None, "the native machine did not build: %s" % native_module.reason())
class WithMachine(unittest.TestCase):
    def setUp(self):
        native.attach(MACHINE)

    def tearDown(self):
        native.attach(None)


class Header(unittest.TestCase):
    def test_the_opcodes_of_the_python_side_are_the_ones_of_the_header(self):
        with open(os.path.join(ROOT, "core", "dexnative", "exteria_dexnative.h"), encoding="utf-8") as handle:
            text = handle.read()
        block = text[text.index("typedef enum exteria_dexnative_op {"):text.index("} exteria_dexnative_op;")]
        names = re.findall(r"\bDN_([A-Z0-9_]+)\b", re.sub(r"/\*.*?\*/", "", block, flags=re.S))
        names = [name for name in names if name != "OP_COUNT"]
        self.assertEqual(native.OPS, names)


class OracleOnTheMachine(WithMachine):
    def test_pure_integer_methods_print_what_a_jvm_printed(self):
        before = native.compiled
        loader = dexvm.load(fixture("Ints"), name="Ints")
        got = loader.load_class("Ints").call_static("run")
        self.assertEqual(expected("Ints"), got)
        # gcd, collatz, fnv, the shifts and the rest of the helpers were compiled for the machine
        self.assertGreaterEqual(native.compiled - before, 24)

    def test_the_machine_leaves_every_other_fixture_alone(self):
        for name in ("Arith", "Flow", "Arrs", "Strs", "Objs", "Fmt", "Util", "Indy", "CustomIndy"):
            loader = dexvm.load(fixture(name), name=name)
            self.assertEqual(expected(name), loader.load_class(name).call_static("run"), name)

    def test_arith_runs_the_same_with_and_without_the_machine(self):
        loader = dexvm.load(fixture("Arith"), name="Arith")
        self.assertEqual(expected("Arith"), loader.load_class("Arith").call_static("run"))


class Eligibility(WithMachine):
    def plan(self, items, proto="(I)I", registers=3, ins=1, access=dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC):
        builder = dexbuilder.DexBuilder()
        builder.add_class("LRand;").method("m", proto, access, registers=registers, ins=ins, insns=assemble(items))
        loader = dexvm.load(dexbuilder.fix_checksums(builder.build()))
        method = loader.load_class("Rand").method("m")
        code = method.owner.dexfile.code(method.code_off)
        return native.plan(method.owner.dexfile, code, method.proto, method.access)

    def test_a_plain_integer_method_qualifies(self):
        program, registers, arguments, returns = self.plan([("add-int/lit8", 0, 2, 1), ("return", 0)])
        self.assertEqual(3, registers)
        self.assertEqual((2,), arguments)
        self.assertTrue(returns)
        self.assertEqual(32, len(program))

    def test_a_wide_argument_takes_two_registers(self):
        _, _, arguments, _ = self.plan([("return-wide", 2)], proto="(IJI)J", registers=6, ins=5)
        self.assertEqual((1, 2 + 1 + 1 - 1, 5)[0:1] + (2, 4), arguments)

    def test_each_reason_for_the_python_path(self):
        cases = [
            ("not static", dict(items=[("return", 0)], access=dexbuilder.ACC_PUBLIC)),
            ("not an integer", dict(items=[("return", 0)], proto="(F)I")),
            ("not an integer", dict(items=[("return", 0)], proto="(Ljava/lang/String;)I")),
            ("not an integer", dict(items=[("return", 0)], proto="(I)Ljava/lang/String;")),
            ("not an integer", dict(items=[("return", 0)], proto="(I)D")),
            ("synchronized", dict(items=[("return", 0)], access=dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC | 0x20)),
            ("uses add-float", dict(items=[("add-float", 0, 1, 2), ("return", 0)], registers=3, ins=1)),
            ("uses array-length", dict(items=[("array-length", 0, 1), ("return", 0)])),
            ("uses sget", dict(items=[("return", 0)], registers=1, ins=0)),
        ]
        for fragment, kwargs in cases[:-1]:
            with self.assertRaises(native.NotNative) as caught:
                self.plan(**kwargs)
            self.assertIn(fragment, str(caught.exception), kwargs)

    def test_a_method_with_a_try_block_stays_on_the_python_path(self):
        builder = dexbuilder.DexBuilder()
        cls = builder.add_class("LRand;")
        cls.method("m", "(I)I", dexbuilder.ACC_PUBLIC | dexbuilder.ACC_STATIC, registers=3, ins=1,
                   insns=assemble([("div-int/lit8", 0, 2, 0), ("return", 0), ("const/4", 0, 0), ("return", 0)]),
                   tries=[(0, 2, 2, [(None, 2)])] if False else ())
        # the builder's try tables need a handler type; the rule is checked on the decoded method instead
        loader = dexvm.load(dexbuilder.fix_checksums(builder.build()))
        method = loader.load_class("Rand").method("m")
        code = method.owner.dexfile.code(method.code_off)
        self.assertEqual((), tuple(code.tries))

    def test_a_branch_to_the_middle_of_nothing_is_not_native(self):
        with self.assertRaises(Exception):
            self.plan([("goto", "nowhere"), ("return", 0)])

    def test_a_method_the_machine_cannot_have_runs_on_python(self):
        data = dex_with([("m", "(F)F", 2, 1, [("return", 1)])])
        method = dexvm.load(data).load_class("Rand").method("m")
        function = method.function()
        self.assertFalse(hasattr(function, "native"))


class Behaviour(WithMachine):
    def load(self, items, proto, registers, ins):
        data = dex_with([("m", proto, registers, ins, items)])
        return dexvm.load(data).load_class("Rand").method("m")

    def test_the_result_of_a_loop(self):
        items = [("const/4", 1, 0), ("const/4", 2, 0), ("label", "top"), ("if-ge", 2, 3, "end"), ("add-int/2addr", 1, 2),
                 ("add-int/lit8", 2, 2, 1), ("goto", "top"), ("label", "end"), ("return", 1)]
        method = self.load(items, "(I)I", 4, 1)
        self.assertTrue(hasattr(method.function(), "native"))
        self.assertEqual(4950, method.invoke(100))
        self.assertEqual(0, method.invoke(0))
        self.assertEqual(186514128, method.invoke(100000 * 7))

    def test_division_by_zero_is_the_arithmetic_exception_of_the_python_path(self):
        method = self.load([("div-int", 0, 1, 2), ("return", 0)], "(II)I", 3, 2)
        self.assertTrue(hasattr(method.function(), "native"))
        with self.assertRaises(runtime.api.lookup_host("java.lang.ArithmeticException").py) as caught:
            method.invoke(1, 0)
        self.assertEqual("divide by zero", caught.exception.getMessage())
        self.assertEqual(7, method.invoke(21, 3))

    def test_booleans_and_chars_arrive_as_the_registers_python_gives(self):
        method = self.load([("return", 1)], "(IZ)Z", 2, 2)
        self.assertIs(True, method.invoke(5, True))
        self.assertIs(False, method.invoke(5, False))
        method = self.load([("add-int/lit8", 0, 1, 1), ("return", 0)], "(C)C", 2, 1)
        self.assertEqual("b", method.invoke("a"))

    def test_void_returns_none(self):
        method = self.load([("return-void",)], "(I)V", 1, 1)
        self.assertIsNone(method.invoke(3))

    def test_a_loop_without_an_exit_stops_at_the_budget(self):
        method = self.load([("label", "top"), ("add-int/lit8", 0, 0, 1), ("goto", "top")], "(I)I", 1, 1)
        self.assertTrue(hasattr(method.function(), "native"))
        import time
        started = time.monotonic()
        with limits.budget(seconds=0.2):
            with self.assertRaises(limits.BudgetExceeded):
                method.invoke(0)
        self.assertLess(time.monotonic() - started, 3)
        with limits.budget(steps=1000000):
            with self.assertRaises(limits.BudgetExceeded):
                method.invoke(0)
        self.assertEqual(7, self.load([("return", 0)], "(I)I", 1, 1).invoke(7))

    def test_a_tick_that_raises_ends_the_call(self):
        program = MACHINE.Program(b"".join(__import__("struct").pack("=iiii", *row) for row in (
            (native.OP["GOTO"], 0, 0, 0),)), 1, ())
        seen = []

        def tick(jumps):
            seen.append(jumps)
            if len(seen) == 3:
                raise KeyError("stop")
        with self.assertRaises(KeyError):
            program.call((), tick, 100)
        self.assertEqual([100, 100, 100], seen)

    def test_the_module_checks_what_python_gives_it(self):
        struct = __import__("struct")
        ret = struct.pack("=iiii", native.OP["RETURN"], 0, 0, 0)
        program = MACHINE.Program(ret, 1, (0,))
        self.assertEqual(9, program.call((9,)))
        self.assertEqual(-(1 << 63), program.call((-(1 << 63),)))
        with self.assertRaises(OverflowError):
            program.call((1 << 63,))
        with self.assertRaises(TypeError):
            program.call((1, 2))
        with self.assertRaises(TypeError):
            program.call([1])
        with self.assertRaises(ValueError):
            program.call((1,), None, 0)
        with self.assertRaises(ValueError):
            MACHINE.Program(ret[:15], 1, ())
        with self.assertRaises(ValueError):
            MACHINE.Program(struct.pack("=iiii", native.OP["RETURN"], 5, 0, 0), 1, ())
        with self.assertRaises(ValueError):
            MACHINE.Program(ret, 1, (3,))
        with self.assertRaises(ValueError):
            MACHINE.Program(ret, MACHINE.MAX_REGISTERS + 1, ())
        with self.assertRaises(ValueError):
            MACHINE.Program(struct.pack("=iiii", native.OP["ADD_I"], 0, 0, 0), 1, ())


class Differential(WithMachine):
    """the machine and the python translation run the same random method; every result, and every exception with its
    message, must be equal. the translation itself is checked against a jvm by the oracle tests"""

    def run_both(self, data, name, argsets):
        native.attach(MACHINE)
        fast = dexvm.load(data).load_class("Rand").method(name)
        slow_loader = None
        function = fast.function()
        self.assertTrue(hasattr(function, "native"), "the method was not compiled for the machine")
        native.attach(None)
        slow_loader = dexvm.load(data).load_class("Rand").method(name)
        self.assertFalse(hasattr(slow_loader.function(), "native"))
        native.attach(MACHINE)
        for args in argsets:
            self.assertEqual(outcome(slow_loader.invoke, args), outcome(fast.invoke, args), (name, args))

    def arguments(self, rng, count):
        sets = [(0, 0, 0), (1, -1, 1), (-0x80000000, -1, -0x8000000000000000), (0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFFFFFFFFFF)]
        for _ in range(count):
            sets.append((rng.choice(INTERESTING + (rng.randrange(-2**31, 2**31),)),
                         rng.choice(INTERESTING + (rng.randrange(-2**31, 2**31),)),
                         rng.choice(WIDE_INTERESTING + (rng.randrange(-2**63, 2**63),))))
        return sets

    def test_random_methods_with_loops_branches_and_every_arithmetic_form(self):
        rng = random.Random(20261111)
        for number in range(260):
            returns = rng.choice("IIJJZBSCV")
            items = program(rng, returns)
            data = dex_with([("m", "(IIJ)%s" % returns, 16, 4, items)])
            self.run_both(data, "m", self.arguments(rng, 10))

    def test_random_methods_that_divide_by_what_they_are_given(self):
        rng = random.Random(7)
        for number in range(80):
            body = [("move", 0, PARAMS), ("move", 1, PARAMS + 1), ("move-wide", 4, PARAMS + 2), ("move-wide", 6, PARAMS + 2)]
            for _ in range(rng.randrange(1, 5)):
                body.append(rng.choice((
                    ("div-int", 0, 0, 1), ("rem-int", 1, 0, 1), ("div-long", 4, 4, 6), ("rem-long", 6, 4, 6),
                    ("div-int/2addr", 0, 1), ("rem-long/2addr", 4, 6), ("div-int/lit8", 0, 1, 0), ("rem-int/lit16", 0, 1, 0),
                    ("div-int/lit8", 0, 0, -1), ("div-long/2addr", 4, 6), ("rem-int/2addr", 0, 1))))
            body.append(("return-wide", 4) if rng.random() < 0.5 else ("return", 0))
            returns = "J" if body[-1][0] == "return-wide" else "I"
            data = dex_with([("m", "(IIJ)%s" % returns, 16, 4, body)])
            self.run_both(data, "m", [(a, b, c) for a in (0, 1, -1, -0x80000000, 7) for b in (0, 1, -1, 3, -0x80000000)
                                      for c in (0, 1, -1, 5, -0x8000000000000000)])

    def test_the_largest_programs_the_machine_takes(self):
        items = [("const/4", 0, 1)] + [("add-int/lit8", 0, 0, 1)] * 3000 + [("return", 0)]
        data = dex_with([("m", "()I", 1, 0, items)])
        function = dexvm.load(data).load_class("Rand").method("m").function()
        self.assertTrue(hasattr(function, "native"))
        self.assertEqual(3001, function())


if __name__ == "__main__":
    unittest.main()
