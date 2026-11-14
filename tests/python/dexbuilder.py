"""a small dex writer for tests that need a file javac and d8 would never produce: inheritance cycles, a class whose
parent is missing, a method with an opcode the runtime does not know. strings, types, prototypes, fields, methods and
class definitions with code items; the checksum and the signature are computed"""

import hashlib
import struct
import zlib

ACC_PUBLIC = 0x1
ACC_STATIC = 0x8
ACC_FINAL = 0x10
ACC_INTERFACE = 0x200
ACC_ABSTRACT = 0x400
ACC_CONSTRUCTOR = 0x10000


def uleb(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def mutf8(text):
    out = bytearray()
    for char in text:
        unit = ord(char)
        if 0 < unit < 0x80:
            out.append(unit)
        elif unit < 0x800:
            out += bytes((0xC0 | unit >> 6, 0x80 | unit & 0x3F))
        else:
            out += bytes((0xE0 | unit >> 12, 0x80 | unit >> 6 & 0x3F, 0x80 | unit & 0x3F))
    return bytes(out)


class MethodSpec:
    def __init__(self, name, proto, access, registers, ins, insns, tries):
        self.name = name
        self.proto = proto
        self.access = access
        self.registers = registers
        self.ins = ins
        self.insns = insns
        self.tries = tries


class ClassSpec:
    def __init__(self, descriptor, superclass, interfaces, access):
        self.descriptor = descriptor
        self.superclass = superclass
        self.interfaces = interfaces
        self.access = access
        self.methods = []
        self.fields = []

    def method(self, name, proto, access, registers=1, ins=0, insns=None, tries=()):
        self.methods.append(MethodSpec(name, proto, access, registers, ins, insns, tries))
        return self

    def field(self, name, type_, access):
        self.fields.append((name, type_, access))
        return self


def split_proto(proto):
    params = []
    pos = 1
    while proto[pos] != ")":
        start = pos
        while proto[pos] == "[":
            pos += 1
        if proto[pos] == "L":
            pos = proto.index(";", pos)
        pos += 1
        params.append(proto[start:pos])
    return params, proto[pos + 1:]


class DexBuilder:
    def __init__(self, version=b"035"):
        self.version = version
        self.classes = []

    def add_class(self, descriptor, superclass="Ljava/lang/Object;", interfaces=(), access=ACC_PUBLIC):
        spec = ClassSpec(descriptor, superclass, tuple(interfaces), access)
        self.classes.append(spec)
        return spec

    def build(self):
        strings = set()
        types = set()
        protos = set()
        fields = set()
        methods = set()

        def add_type(descriptor):
            strings.add(descriptor)
            types.add(descriptor)

        def add_proto(proto):
            params, ret = split_proto(proto)
            shorty = ("V" if ret == "V" else (ret if len(ret) == 1 else "L")) + "".join(
                p if len(p) == 1 else "L" for p in params)
            strings.add(shorty)
            add_type(ret)
            for param in params:
                add_type(param)
            protos.add((shorty, ret, tuple(params)))

        for cls in self.classes:
            add_type(cls.descriptor)
            if cls.superclass:
                add_type(cls.superclass)
            for interface in cls.interfaces:
                add_type(interface)
            for name, type_, _ in cls.fields:
                strings.add(name)
                add_type(type_)
                fields.add((cls.descriptor, type_, name))
            for method in cls.methods:
                strings.add(method.name)
                add_proto(method.proto)
                methods.add((cls.descriptor, method.proto, method.name))
        string_list = sorted(strings, key=lambda s: mutf8(s))
        string_index = {s: i for i, s in enumerate(string_list)}
        type_list = sorted(types, key=lambda t: string_index[t])
        type_index = {t: i for i, t in enumerate(type_list)}
        proto_list = sorted(protos, key=lambda p: (type_index[p[1]], [type_index[x] for x in p[2]]))
        proto_index = {p: i for i, p in enumerate(proto_list)}
        field_list = sorted(fields, key=lambda f: (type_index[f[0]], string_index[f[2]], type_index[f[1]]))
        field_index = {f: i for i, f in enumerate(field_list)}

        def proto_key(proto):
            params, ret = split_proto(proto)
            shorty = ("V" if ret == "V" else (ret if len(ret) == 1 else "L")) + "".join(
                p if len(p) == 1 else "L" for p in params)
            return (shorty, ret, tuple(params))
        method_list = sorted(methods, key=lambda m: (type_index[m[0]], string_index[m[2]], proto_index[proto_key(m[1])]))
        method_index = {m: i for i, m in enumerate(method_list)}

        header_size = 0x70
        offset = header_size
        string_ids_off = offset
        offset += 4 * len(string_list)
        type_ids_off = offset
        offset += 4 * len(type_list)
        proto_ids_off = offset
        offset += 12 * len(proto_list)
        field_ids_off = offset
        offset += 8 * len(field_list)
        method_ids_off = offset
        offset += 8 * len(method_list)
        class_defs_off = offset
        offset += 32 * len(self.classes)
        data_off = offset
        data = bytearray()

        def align(n):
            while (data_off + len(data)) % n:
                data.append(0)

        string_offsets = []
        for text in string_list:
            string_offsets.append(data_off + len(data))
            data += uleb(len(text)) + mutf8(text) + b"\0"
        type_list_offsets = {}
        for params in {p[2] for p in proto_list} | {tuple(c.interfaces) for c in self.classes}:
            if not params:
                continue
            align(4)
            type_list_offsets[params] = data_off + len(data)
            data += struct.pack("<I", len(params)) + b"".join(struct.pack("<H", type_index[t]) for t in params)
        class_data_offsets = {}
        code_offsets = {}
        for cls in self.classes:
            for method in cls.methods:
                if method.insns is None:
                    continue
                align(4)
                code_offsets[(cls.descriptor, method.name, method.proto)] = data_off + len(data)
                insns = list(method.insns)
                tries = method.tries
                data += struct.pack("<4HII", method.registers, method.ins, 0, len(tries), 0, len(insns))
                data += b"".join(struct.pack("<H", unit & 0xFFFF) for unit in insns)
                if tries:
                    if len(insns) & 1:
                        data += b"\0\0"
                    handlers = bytearray()
                    handler_offsets = []
                    for start, count, clauses, catch_all in tries:
                        handler_offsets.append(len(handlers))
                        size = len(clauses) if catch_all is None else -len(clauses)
                        handlers += uleb_signed(size)
                        for type_desc, address in clauses:
                            handlers += uleb(type_index[type_desc]) + uleb(address)
                        if catch_all is not None:
                            handlers += uleb(catch_all)
                    list_header = uleb(len(tries))
                    for (start, count, _, _), h_off in zip(tries, handler_offsets):
                        data += struct.pack("<IHH", start, count, len(list_header) + h_off)
                    data += list_header + handlers
        for cls in self.classes:
            statics = [f for f in cls.fields if f[2] & ACC_STATIC]
            instances = [f for f in cls.fields if not f[2] & ACC_STATIC]
            directs = [m for m in cls.methods if m.access & (ACC_STATIC | ACC_CONSTRUCTOR | 0x2)]
            virtuals = [m for m in cls.methods if m not in directs]
            if not (cls.fields or cls.methods):
                class_data_offsets[cls.descriptor] = 0
                continue
            class_data_offsets[cls.descriptor] = data_off + len(data)
            data += uleb(len(statics)) + uleb(len(instances)) + uleb(len(directs)) + uleb(len(virtuals))
            for group in (statics, instances):
                last = 0
                ordered = sorted(group, key=lambda f: field_index[(cls.descriptor, f[1], f[0])])
                for name, type_, access in ordered:
                    index = field_index[(cls.descriptor, type_, name)]
                    data += uleb(index - last) + uleb(access)
                    last = index
            for group in (directs, virtuals):
                last = 0
                ordered = sorted(group, key=lambda m: method_index[(cls.descriptor, m.proto, m.name)])
                for method in ordered:
                    index = method_index[(cls.descriptor, method.proto, method.name)]
                    data += uleb(index - last) + uleb(method.access) + uleb(
                        code_offsets.get((cls.descriptor, method.name, method.proto), 0))
                    last = index
        align(4)
        map_off = data_off + len(data)
        map_items = [(0x0000, 1, 0), (0x0001, len(string_list), string_ids_off), (0x0002, len(type_list), type_ids_off),
                     (0x0003, len(proto_list), proto_ids_off), (0x0004, len(field_list), field_ids_off),
                     (0x0005, len(method_list), method_ids_off), (0x0006, len(self.classes), class_defs_off),
                     (0x1000, 1, map_off)]
        data += struct.pack("<I", len(map_items))
        for kind, size, off in map_items:
            data += struct.pack("<HHII", kind, 0, size, off)
        file_size = data_off + len(data)

        out = bytearray(header_size)
        for text in string_list:
            pass
        out += b"".join(struct.pack("<I", o) for o in string_offsets)
        out += b"".join(struct.pack("<I", string_index[t]) for t in type_list)
        for shorty, ret, params in proto_list:
            out += struct.pack("<III", string_index[shorty], type_index[ret], type_list_offsets.get(params, 0))
        for owner, type_, name in field_list:
            out += struct.pack("<HHI", type_index[owner], type_index[type_], string_index[name])
        for owner, proto, name in method_list:
            out += struct.pack("<HHI", type_index[owner], proto_index[proto_key(proto)], string_index[name])
        for cls in self.classes:
            out += struct.pack(
                "<8I", type_index[cls.descriptor], cls.access, type_index[cls.superclass] if cls.superclass else 0xFFFFFFFF,
                type_list_offsets.get(tuple(cls.interfaces), 0), 0xFFFFFFFF, 0, class_data_offsets[cls.descriptor], 0)
        out += data
        header = bytearray()
        header += b"dex\n" + self.version + b"\0"
        header += b"\0" * 4 + b"\0" * 20
        header += struct.pack("<II", file_size, header_size)
        header += struct.pack("<II", 0x12345678, 0)
        header += struct.pack("<II", 0, map_off)
        header += struct.pack("<II", len(string_list), string_ids_off)
        header += struct.pack("<II", len(type_list), type_ids_off)
        header += struct.pack("<II", len(proto_list), proto_ids_off)
        header += struct.pack("<II", len(field_list), field_ids_off)
        header += struct.pack("<II", len(method_list), method_ids_off)
        header += struct.pack("<II", len(self.classes), class_defs_off)
        header += struct.pack("<II", len(data), data_off)
        out[:header_size] = header
        return fix_checksums(bytes(out))


def uleb_signed(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if (value == 0 and not byte & 0x40) or (value == -1 and byte & 0x40):
            out.append(byte)
            return bytes(out)
        out.append(byte | 0x80)


def fix_checksums(data):
    """recompute the signature and the adler-32 checksum after a change to the bytes"""
    data = bytearray(data)
    data[12:32] = hashlib.sha1(bytes(data[32:])).digest()
    data[8:12] = struct.pack("<I", zlib.adler32(bytes(data[12:])) & 0xFFFFFFFF)
    return bytes(data)


# instruction encoders for the opcodes the tests use
def op_const4(reg, value):
    return [0x12 | (reg | (value & 0xF) << 4) << 8]


def op_return(reg):
    return [0x0F | reg << 8]


def op_return_void():
    return [0x0E]


def op_add_int(dest, a, b):
    return [0x90 | dest << 8, a | b << 8]
