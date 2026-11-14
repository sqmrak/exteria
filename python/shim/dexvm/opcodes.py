"""decoder of dalvik instructions from 16-bit code units

OPCODES maps an opcode byte to (name, format, index kind). the formats are the names of the dalvik bytecode
document (10x, 12x, 35c ...). an opcode byte the table has no entry for, a payload that does not fit, a register
list that disagrees with its count or a branch outside the method raises DecodeError, nothing is skipped"""

import struct


class DecodeError(ValueError):
    """an instruction stream the decoder refuses"""


# index kinds of the c field
NONE = 0
STRING = 1
TYPE = 2
FIELD = 3
METHOD = 4
METHOD_HANDLE = 5
METHOD_TYPE = 6
CALL_SITE = 7

# (name, format, index kind)
OPCODES = {}


def _define(first, names, fmt, kind=NONE):
    for offset, name in enumerate(names.split()):
        OPCODES[first + offset] = (name, fmt, kind)


_define(0x00, "nop", "10x")
_define(0x01, "move", "12x")
_define(0x02, "move/from16", "22x")
_define(0x03, "move/16", "32x")
_define(0x04, "move-wide", "12x")
_define(0x05, "move-wide/from16", "22x")
_define(0x06, "move-wide/16", "32x")
_define(0x07, "move-object", "12x")
_define(0x08, "move-object/from16", "22x")
_define(0x09, "move-object/16", "32x")
_define(0x0A, "move-result move-result-wide move-result-object move-exception", "11x")
_define(0x0E, "return-void", "10x")
_define(0x0F, "return return-wide return-object", "11x")
_define(0x12, "const/4", "11n")
OPCODES[0x13] = ("const/16", "21s", NONE)
OPCODES[0x14] = ("const", "31i", NONE)
OPCODES[0x15] = ("const/high16", "21h", NONE)
OPCODES[0x16] = ("const-wide/16", "21s", NONE)
OPCODES[0x17] = ("const-wide/32", "31i", NONE)
OPCODES[0x18] = ("const-wide", "51l", NONE)
OPCODES[0x19] = ("const-wide/high16", "21h", NONE)
OPCODES[0x1A] = ("const-string", "21c", STRING)
OPCODES[0x1B] = ("const-string/jumbo", "31c", STRING)
OPCODES[0x1C] = ("const-class", "21c", TYPE)
_define(0x1D, "monitor-enter monitor-exit", "11x")
OPCODES[0x1F] = ("check-cast", "21c", TYPE)
OPCODES[0x20] = ("instance-of", "22c", TYPE)
OPCODES[0x21] = ("array-length", "12x", NONE)
OPCODES[0x22] = ("new-instance", "21c", TYPE)
OPCODES[0x23] = ("new-array", "22c", TYPE)
OPCODES[0x24] = ("filled-new-array", "35c", TYPE)
OPCODES[0x25] = ("filled-new-array/range", "3rc", TYPE)
OPCODES[0x26] = ("fill-array-data", "31t", NONE)
OPCODES[0x27] = ("throw", "11x", NONE)
OPCODES[0x28] = ("goto", "10t", NONE)
OPCODES[0x29] = ("goto/16", "20t", NONE)
OPCODES[0x2A] = ("goto/32", "30t", NONE)
OPCODES[0x2B] = ("packed-switch", "31t", NONE)
OPCODES[0x2C] = ("sparse-switch", "31t", NONE)
_define(0x2D, "cmpl-float cmpg-float cmpl-double cmpg-double cmp-long", "23x")
_define(0x32, "if-eq if-ne if-lt if-ge if-gt if-le", "22t")
_define(0x38, "if-eqz if-nez if-ltz if-gez if-gtz if-lez", "21t")
_define(0x44, "aget aget-wide aget-object aget-boolean aget-byte aget-char aget-short "
              "aput aput-wide aput-object aput-boolean aput-byte aput-char aput-short", "23x")
_define(0x52, "iget iget-wide iget-object iget-boolean iget-byte iget-char iget-short "
              "iput iput-wide iput-object iput-boolean iput-byte iput-char iput-short", "22c", FIELD)
_define(0x60, "sget sget-wide sget-object sget-boolean sget-byte sget-char sget-short "
              "sput sput-wide sput-object sput-boolean sput-byte sput-char sput-short", "21c", FIELD)
_define(0x6E, "invoke-virtual invoke-super invoke-direct invoke-static invoke-interface", "35c", METHOD)
_define(0x74, "invoke-virtual/range invoke-super/range invoke-direct/range invoke-static/range "
              "invoke-interface/range", "3rc", METHOD)
_define(0x7B, "neg-int not-int neg-long not-long neg-float neg-double int-to-long int-to-float int-to-double "
              "long-to-int long-to-float long-to-double float-to-int float-to-long float-to-double "
              "double-to-int double-to-long double-to-float int-to-byte int-to-char int-to-short", "12x")
_define(0x90, "add-int sub-int mul-int div-int rem-int and-int or-int xor-int shl-int shr-int ushr-int "
              "add-long sub-long mul-long div-long rem-long and-long or-long xor-long shl-long shr-long ushr-long "
              "add-float sub-float mul-float div-float rem-float add-double sub-double mul-double div-double "
              "rem-double", "23x")
_define(0xB0, "add-int/2addr sub-int/2addr mul-int/2addr div-int/2addr rem-int/2addr and-int/2addr "
              "or-int/2addr xor-int/2addr shl-int/2addr shr-int/2addr ushr-int/2addr "
              "add-long/2addr sub-long/2addr mul-long/2addr div-long/2addr rem-long/2addr and-long/2addr "
              "or-long/2addr xor-long/2addr shl-long/2addr shr-long/2addr ushr-long/2addr "
              "add-float/2addr sub-float/2addr mul-float/2addr div-float/2addr rem-float/2addr "
              "add-double/2addr sub-double/2addr mul-double/2addr div-double/2addr rem-double/2addr", "12x")
_define(0xD0, "add-int/lit16 rsub-int mul-int/lit16 div-int/lit16 rem-int/lit16 and-int/lit16 or-int/lit16 "
              "xor-int/lit16", "22s")
_define(0xD8, "add-int/lit8 rsub-int/lit8 mul-int/lit8 div-int/lit8 rem-int/lit8 and-int/lit8 or-int/lit8 "
              "xor-int/lit8 shl-int/lit8 shr-int/lit8 ushr-int/lit8", "22b")
OPCODES[0xFA] = ("invoke-polymorphic", "45cc", METHOD)
OPCODES[0xFB] = ("invoke-polymorphic/range", "4rcc", METHOD)
OPCODES[0xFC] = ("invoke-custom", "35c", CALL_SITE)
OPCODES[0xFD] = ("invoke-custom/range", "3rc", CALL_SITE)
OPCODES[0xFE] = ("const-method-handle", "21c", METHOD_HANDLE)
OPCODES[0xFF] = ("const-method-type", "21c", METHOD_TYPE)

# code units each format occupies
SIZES = {
    "10x": 1, "12x": 1, "11n": 1, "11x": 1, "10t": 1, "20t": 2, "22x": 2, "21t": 2, "21s": 2, "21h": 2,
    "21c": 2, "23x": 2, "22b": 2, "22t": 2, "22s": 2, "22c": 2, "30t": 3, "32x": 3, "31i": 3, "31t": 3,
    "31c": 3, "35c": 3, "3rc": 3, "45cc": 4, "4rcc": 4, "51l": 5,
}

PACKED_SWITCH_IDENT = 0x0100
SPARSE_SWITCH_IDENT = 0x0200
FILL_ARRAY_IDENT = 0x0300

# a limit on the register list of a range invoke: 65535 is what the format can say, a method never has that many
MAX_RANGE = 255


class Insn:
    """one decoded instruction. regs holds the registers of a 35c, 3rc, 45cc or 4rcc form, a and b and c the
    register fields of the short forms, lit the literal, idx the index into the string, type, field, method or
    other table, proto the proto index of a polymorphic invoke, target the absolute branch address in code units"""
    __slots__ = ("addr", "op", "name", "fmt", "size", "a", "b", "c", "lit", "idx", "proto", "target", "regs")

    def __init__(self, addr, op, name, fmt, size):
        self.addr = addr
        self.op = op
        self.name = name
        self.fmt = fmt
        self.size = size
        self.a = self.b = self.c = 0
        self.lit = 0
        self.idx = 0
        self.proto = 0
        self.target = None
        self.regs = ()

    def __repr__(self):
        return "<%04x %s a=%d b=%d c=%d lit=%d idx=%d target=%s regs=%s>" % (
            self.addr, self.name, self.a, self.b, self.c, self.lit, self.idx, self.target, self.regs)


def _signed(value, bits):
    return value - (1 << bits) if value >> (bits - 1) else value


def decode_one(units, addr):
    """the instruction at addr. a payload pseudo instruction comes back as a nop-named Insn with fmt 'payload'"""
    size_units = len(units)
    if addr >= size_units:
        raise DecodeError("instruction at %04x is past the end" % addr)
    unit = units[addr]
    op = unit & 0xFF
    if op == 0 and unit != 0:
        return _payload(units, addr, unit)
    entry = OPCODES.get(op)
    if entry is None:
        raise DecodeError("unknown opcode 0x%02x at %04x" % (op, addr))
    name, fmt, _kind = entry
    length = SIZES[fmt]
    if addr + length > size_units:
        raise DecodeError("instruction %s at %04x is cut" % (name, addr))
    insn = Insn(addr, op, name, fmt, length)
    high = unit >> 8
    if fmt == "10x":
        pass
    elif fmt == "12x":
        insn.a = high & 0xF
        insn.b = high >> 4
    elif fmt == "11n":
        insn.a = high & 0xF
        insn.lit = _signed(high >> 4, 4)
    elif fmt == "11x":
        insn.a = high
    elif fmt == "10t":
        insn.target = addr + _signed(high, 8)
    elif fmt == "20t":
        insn.target = addr + _signed(units[addr + 1], 16)
    elif fmt == "22x":
        insn.a = high
        insn.b = units[addr + 1]
    elif fmt == "21t":
        insn.a = high
        insn.target = addr + _signed(units[addr + 1], 16)
    elif fmt == "21s":
        insn.a = high
        insn.lit = _signed(units[addr + 1], 16)
    elif fmt == "21h":
        insn.a = high
        insn.lit = _signed(units[addr + 1], 16) << (48 if op == 0x19 else 16)
    elif fmt == "21c":
        insn.a = high
        insn.idx = units[addr + 1]
    elif fmt == "23x":
        insn.a = high
        insn.b = units[addr + 1] & 0xFF
        insn.c = units[addr + 1] >> 8
    elif fmt == "22b":
        insn.a = high
        insn.b = units[addr + 1] & 0xFF
        insn.lit = _signed(units[addr + 1] >> 8, 8)
    elif fmt == "22t":
        insn.a = high & 0xF
        insn.b = high >> 4
        insn.target = addr + _signed(units[addr + 1], 16)
    elif fmt == "22s":
        insn.a = high & 0xF
        insn.b = high >> 4
        insn.lit = _signed(units[addr + 1], 16)
    elif fmt == "22c":
        insn.a = high & 0xF
        insn.b = high >> 4
        insn.idx = units[addr + 1]
    elif fmt == "30t":
        insn.target = addr + _signed(units[addr + 1] | units[addr + 2] << 16, 32)
    elif fmt == "32x":
        insn.a = units[addr + 1]
        insn.b = units[addr + 2]
    elif fmt == "31i":
        insn.a = high
        insn.lit = _signed(units[addr + 1] | units[addr + 2] << 16, 32)
    elif fmt == "31t":
        insn.a = high
        insn.target = addr + _signed(units[addr + 1] | units[addr + 2] << 16, 32)
    elif fmt == "31c":
        insn.a = high
        insn.idx = units[addr + 1] | units[addr + 2] << 16
    elif fmt in ("35c", "45cc"):
        count = high >> 4
        if count > 5:
            raise DecodeError("%s at %04x lists %d registers" % (name, addr, count))
        insn.idx = units[addr + 1]
        packed = units[addr + 2]
        regs = [packed & 0xF, packed >> 4 & 0xF, packed >> 8 & 0xF, packed >> 12]
        regs.append(high & 0xF)
        insn.regs = tuple(regs[:count])
        if count < 5 and regs[count:4] != [0] * (4 - count):
            raise DecodeError("%s at %04x has stray register nibbles" % (name, addr))
        if fmt == "45cc":
            insn.proto = units[addr + 3]
    elif fmt == "51l":
        insn.a = high
        insn.lit = _signed(units[addr + 1] | units[addr + 2] << 16 | units[addr + 3] << 32 | units[addr + 4] << 48, 64)
    else:
        count = high
        insn.idx = units[addr + 1]
        first = units[addr + 2]
        if count > MAX_RANGE:
            raise DecodeError("%s at %04x lists %d registers" % (name, addr, count))
        insn.regs = tuple(range(first, first + count))
        if fmt == "4rcc":
            insn.proto = units[addr + 3]
    return insn


def _payload(units, addr, ident):
    if ident == PACKED_SWITCH_IDENT:
        if addr + 4 > len(units):
            raise DecodeError("packed switch payload at %04x is cut" % addr)
        count = units[addr + 1]
        length = 4 + count * 2
    elif ident == SPARSE_SWITCH_IDENT:
        if addr + 2 > len(units):
            raise DecodeError("sparse switch payload at %04x is cut" % addr)
        count = units[addr + 1]
        length = 2 + count * 4
    elif ident == FILL_ARRAY_IDENT:
        if addr + 4 > len(units):
            raise DecodeError("array payload at %04x is cut" % addr)
        width = units[addr + 1]
        count = units[addr + 2] | units[addr + 3] << 16
        length = 4 + (width * count + 1) // 2
    else:
        raise DecodeError("unknown opcode 0x00 with operand 0x%02x at %04x" % (ident >> 8, addr))
    if addr + length > len(units):
        raise DecodeError("payload at %04x leaves the method" % addr)
    insn = Insn(addr, 0, "payload", "payload", length)
    insn.lit = ident
    return insn


def packed_switch_payload(units, addr, base):
    """(first key, [absolute targets]) of the payload at addr, relative to the switch instruction at base"""
    insn = decode_one(units, addr)
    if insn.fmt != "payload" or insn.lit != PACKED_SWITCH_IDENT:
        raise DecodeError("packed-switch at %04x does not point at its payload" % base)
    count = units[addr + 1]
    first = _signed(units[addr + 2] | units[addr + 3] << 16, 32)
    targets = []
    for index in range(count):
        offset = _signed(units[addr + 4 + index * 2] | units[addr + 5 + index * 2] << 16, 32)
        targets.append(base + offset)
    return first, targets


def sparse_switch_payload(units, addr, base):
    """([keys], [absolute targets]) of the payload at addr, relative to the switch instruction at base"""
    insn = decode_one(units, addr)
    if insn.fmt != "payload" or insn.lit != SPARSE_SWITCH_IDENT:
        raise DecodeError("sparse-switch at %04x does not point at its payload" % base)
    count = units[addr + 1]
    keys = []
    targets = []
    for index in range(count):
        keys.append(_signed(units[addr + 2 + index * 2] | units[addr + 3 + index * 2] << 16, 32))
    start = addr + 2 + count * 2
    for index in range(count):
        offset = _signed(units[start + index * 2] | units[start + 1 + index * 2] << 16, 32)
        targets.append(base + offset)
    return keys, targets


def fill_array_payload(units, addr):
    """(element width, raw little endian bytes, element count) of the payload at addr"""
    insn = decode_one(units, addr)
    if insn.fmt != "payload" or insn.lit != FILL_ARRAY_IDENT:
        raise DecodeError("fill-array-data at %04x does not point at its payload" % addr)
    width = units[addr + 1]
    count = units[addr + 2] | units[addr + 3] << 16
    if width not in (1, 2, 4, 8):
        raise DecodeError("array payload element width %d" % width)
    total = (width * count + 1) // 2
    raw = struct.pack("<%dH" % total, *units[addr + 4:addr + 4 + total])[:width * count]
    return width, raw, count


def decode_all(units):
    """every instruction of a method in address order, payloads included, or DecodeError"""
    result = []
    addr = 0
    total = len(units)
    while addr < total:
        insn = decode_one(units, addr)
        result.append(insn)
        addr += insn.size
    return result
