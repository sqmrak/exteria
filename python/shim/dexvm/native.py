"""the native path of a dex method

a static method that is pure integer code (int, long, boolean, byte, short and char arguments, arithmetic, comparisons,
jumps, no calls, no fields, no arrays, no try blocks) is turned into a program of the register machine in
core/dexnative and run in c instead of being translated into python. a loop of such code runs in nanoseconds, where
the python translation spends about a hundred times that on every pass. every other method takes the python path:
plan() says why a method does not qualify, and nothing about the choice shows in the result

the machine is a python module the app registers (_exteria_dexnative, core/pyhost/exteria_dexnative_module.c). where it
is missing, as in a host test run without the build of the module, every method takes the python path. the semantics
are the ones of the python translation, which tests/python/test_dexvm_native.py checks instruction by instruction on
random programs; division by zero is the ArithmeticException of the python path"""

import struct

from . import limits, runtime
from .format import ACC_NATIVE, ACC_STATIC, ACC_SYNCHRONIZED
from . import opcodes

try:
    import _exteria_dexnative as _machine
except ImportError:
    _machine = None

# the order of exteria_dexnative_op in core/dexnative/exteria_dexnative.h; a test compares the two
OPS = """NOP MOVE CONST CONST_WIDE
ADD_I SUB_I MUL_I DIV_I REM_I AND_I OR_I XOR_I SHL_I SHR_I USHR_I
ADD_L SUB_L MUL_L DIV_L REM_L AND_L OR_L XOR_L SHL_L SHR_L USHR_L
ADD_LIT RSUB_LIT MUL_LIT DIV_LIT REM_LIT AND_LIT OR_LIT XOR_LIT SHL_LIT SHR_LIT USHR_LIT
NEG_I NOT_I NEG_L NOT_L I2L L2I I2B I2C I2S CMP_L GOTO
IF_EQ IF_NE IF_LT IF_GE IF_GT IF_LE IF_EQZ IF_NEZ IF_LTZ IF_GEZ IF_GTZ IF_LEZ RETURN RETURN_VOID""".split()
OP = {name: number for number, name in enumerate(OPS)}

INTEGER_TYPES = frozenset("ZBSCIJ")
_ARITHMETIC = ("add", "sub", "mul", "div", "rem", "and", "or", "xor", "shl", "shr", "ushr")
_LITERAL = {"add-int": "ADD_LIT", "rsub-int": "RSUB_LIT", "mul-int": "MUL_LIT", "div-int": "DIV_LIT",
            "rem-int": "REM_LIT", "and-int": "AND_LIT", "or-int": "OR_LIT", "xor-int": "XOR_LIT",
            "shl-int": "SHL_LIT", "shr-int": "SHR_LIT", "ushr-int": "USHR_LIT"}
_UNARY = {"neg-int": "NEG_I", "not-int": "NOT_I", "neg-long": "NEG_L", "not-long": "NOT_L", "int-to-long": "I2L",
          "long-to-int": "L2I", "int-to-byte": "I2B", "int-to-char": "I2C", "int-to-short": "I2S"}
_MOVES = frozenset(("move", "move/from16", "move/16", "move-wide", "move-wide/from16", "move-wide/16"))
_CONSTANTS = frozenset(("const/4", "const/16", "const", "const/high16", "const-wide/16", "const-wide/32", "const-wide",
                        "const-wide/high16"))
_GOTOS = frozenset(("goto", "goto/16", "goto/32"))
_RETURNS = frozenset(("return", "return-wide"))
_COMPARISONS = ("eq", "ne", "lt", "ge", "gt", "le")


class NotNative(Exception):
    """a method the machine does not run; the message says which part of it is out of reach"""


compiled = 0


def available():
    return _machine is not None


def attach(module):
    """use module as the machine (None to stop using one): for an embedding that loads the module itself, and for tests"""
    global _machine
    _machine = module


def _literal32(value):
    return -0x80000000 <= value <= 0x7FFFFFFF


def plan(dexfile, code, proto, access):
    """(program bytes, register count, register of each argument, returns a value) for a method, or NotNative"""
    if access & (ACC_NATIVE | ACC_SYNCHRONIZED):
        raise NotNative("native or synchronized")
    if not access & ACC_STATIC:
        raise NotNative("not static")
    if code.tries:
        raise NotNative("has a try block")
    if any(t not in INTEGER_TYPES for t in proto.parameters) or (
            proto.return_type != "V" and proto.return_type not in INTEGER_TYPES):
        raise NotNative("takes or returns something that is not an integer")
    if code.registers > _machine.MAX_REGISTERS:
        raise NotNative("too many registers")
    try:
        insns = opcodes.decode_all(code.insns)
    except opcodes.DecodeError as error:
        raise NotNative("does not decode: %s" % error)
    body = [insn for insn in insns if insn.fmt != "payload"]
    if len(body) > _machine.MAX_INSNS:
        raise NotNative("too long")
    index_of = {insn.addr: number for number, insn in enumerate(body)}
    out = []
    for insn in body:
        out.append(_encode(insn, index_of))
    first = code.registers - code.ins
    registers = []
    for descriptor in proto.parameters:
        registers.append(first)
        first += 2 if descriptor == "J" else 1
    return b"".join(struct.pack("=iiii", *row) for row in out), code.registers, tuple(registers), \
        proto.return_type != "V"


def _target(insn, index_of):
    target = index_of.get(insn.target)
    if target is None:
        raise NotNative("branch to nowhere")
    return target


def _encode(insn, index_of):
    name = insn.name
    a, b, c = insn.a, insn.b, insn.c
    if name == "nop":
        return OP["NOP"], 0, 0, 0
    if name in _MOVES:
        return OP["MOVE"], a, b, 0
    if name in _CONSTANTS:
        value = insn.lit
        if _literal32(value):
            return OP["CONST"], a, value, 0
        value &= 0xFFFFFFFFFFFFFFFF
        return OP["CONST_WIDE"], a, _signed32(value & 0xFFFFFFFF), _signed32(value >> 32)
    if name == "return-void":
        return OP["RETURN_VOID"], 0, 0, 0
    if name in _RETURNS:
        return OP["RETURN"], a, 0, 0
    if name in _GOTOS:
        return OP["GOTO"], 0, 0, _target(insn, index_of)
    if name == "cmp-long":
        return OP["CMP_L"], a, b, c
    if name.startswith("if-"):
        suffix = name[3:]
        if suffix in _COMPARISONS:
            return OP["IF_" + suffix.upper()], a, b, _target(insn, index_of)
        if suffix[-1] == "z" and suffix[:-1] in _COMPARISONS:
            return OP["IF_" + suffix.upper()], a, 0, _target(insn, index_of)
    two_address = name.endswith("/2addr")
    base = name[:-6] if two_address else name
    if base in _UNARY:
        return OP[_UNARY[base]], a, b, 0
    kind = base.rsplit("-", 1)
    if len(kind) == 2 and kind[0] in _ARITHMETIC and kind[1] in ("int", "long"):
        suffix = "_I" if kind[1] == "int" else "_L"
        if two_address:
            return OP[kind[0].upper() + suffix], a, a, b
        return OP[kind[0].upper() + suffix], a, b, c
    literal = base.replace("/lit16", "").replace("/lit8", "")
    if literal in _LITERAL:
        return OP[_LITERAL[literal]], a, b, insn.lit
    raise NotNative("uses %s" % name)


def _signed32(value):
    return value - 0x100000000 if value >= 0x80000000 else value


def compile_method(dexfile, code, proto, access, label):
    """the function of a method that runs on the machine, or None: the python path takes it"""
    if _machine is None:
        return None
    try:
        program, nregs, argument_registers, returns = plan(dexfile, code, proto, access)
        machine = _machine.Program(program, nregs, argument_registers)
    except (NotNative, ValueError):
        return None
    global compiled
    compiled += 1
    call = machine.call
    tick = limits.native_tick

    def run(*args):
        try:
            result = call(args, tick)
        except ZeroDivisionError:
            runtime.throw_new("java.lang.ArithmeticException", "divide by zero")
        return result if returns else None
    run.__qualname__ = label
    run.native = machine
    return run
