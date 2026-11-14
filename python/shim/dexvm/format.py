"""reader of the dex file format, versions 035 to 040

every offset and count of the file is checked against the file size before it is read. a table or a data item that
leaves the file raises DexFormatError, nothing is read out of bounds and nothing is clamped. java strings are python
str holding utf-16 code units: a character outside the bmp is two surrogate characters, as in dalvik, so length and
charAt agree with the runtime that produced the file"""

import hashlib
import struct
import zlib

NO_INDEX = 0xFFFFFFFF
ENDIAN_CONSTANT = 0x12345678
REVERSE_ENDIAN_CONSTANT = 0x78563412

# a dex string table is one of several; a hostile file could repeat large items, so the work of one parse is bounded
MAX_FILE_SIZE = 64 * 1024 * 1024
MAX_ANNOTATION_DEPTH = 32
MAX_ENCODED_ARRAY = 65535

ACC_PUBLIC = 0x1
ACC_PRIVATE = 0x2
ACC_PROTECTED = 0x4
ACC_STATIC = 0x8
ACC_FINAL = 0x10
ACC_SYNCHRONIZED = 0x20
ACC_VOLATILE = 0x40
ACC_BRIDGE = 0x40
ACC_TRANSIENT = 0x80
ACC_VARARGS = 0x80
ACC_NATIVE = 0x100
ACC_INTERFACE = 0x200
ACC_ABSTRACT = 0x400
ACC_STRICT = 0x800
ACC_SYNTHETIC = 0x1000
ACC_ANNOTATION = 0x2000
ACC_ENUM = 0x4000
ACC_CONSTRUCTOR = 0x10000
ACC_DECLARED_SYNCHRONIZED = 0x20000

VALUE_BYTE = 0x00
VALUE_SHORT = 0x02
VALUE_CHAR = 0x03
VALUE_INT = 0x04
VALUE_LONG = 0x06
VALUE_FLOAT = 0x10
VALUE_DOUBLE = 0x11
VALUE_METHOD_TYPE = 0x15
VALUE_METHOD_HANDLE = 0x16
VALUE_STRING = 0x17
VALUE_TYPE = 0x18
VALUE_FIELD = 0x19
VALUE_METHOD = 0x1A
VALUE_ENUM = 0x1B
VALUE_ARRAY = 0x1C
VALUE_ANNOTATION = 0x1D
VALUE_NULL = 0x1E
VALUE_BOOLEAN = 0x1F

TYPE_METHOD_HANDLE_ITEM = 0x0008
TYPE_CALL_SITE_ID_ITEM = 0x0007

VISIBILITY_BUILD = 0
VISIBILITY_RUNTIME = 1
VISIBILITY_SYSTEM = 2

METHOD_HANDLE_STATIC_PUT = 0
METHOD_HANDLE_STATIC_GET = 1
METHOD_HANDLE_INSTANCE_PUT = 2
METHOD_HANDLE_INSTANCE_GET = 3
METHOD_HANDLE_INVOKE_STATIC = 4
METHOD_HANDLE_INVOKE_INSTANCE = 5
METHOD_HANDLE_INVOKE_CONSTRUCTOR = 6
METHOD_HANDLE_INVOKE_DIRECT = 7
METHOD_HANDLE_INVOKE_INTERFACE = 8

SUPPORTED_VERSIONS = (b"035", b"036", b"037", b"038", b"039", b"040")


class DexFormatError(ValueError):
    """the bytes are not a well formed dex file, or use a part of the format this reader refuses"""


class Proto:
    __slots__ = ("shorty", "return_type", "parameters")

    def __init__(self, shorty, return_type, parameters):
        self.shorty = shorty
        self.return_type = return_type
        self.parameters = parameters

    def descriptor(self):
        return "(" + "".join(self.parameters) + ")" + self.return_type


class FieldId:
    __slots__ = ("class_type", "type", "name")

    def __init__(self, class_type, type_, name):
        self.class_type = class_type
        self.type = type_
        self.name = name


class MethodId:
    __slots__ = ("class_type", "proto", "name")

    def __init__(self, class_type, proto, name):
        self.class_type = class_type
        self.proto = proto
        self.name = name


class EncodedField:
    __slots__ = ("field_idx", "access")

    def __init__(self, field_idx, access):
        self.field_idx = field_idx
        self.access = access


class EncodedMethod:
    __slots__ = ("method_idx", "access", "code_off")

    def __init__(self, method_idx, access, code_off):
        self.method_idx = method_idx
        self.access = access
        self.code_off = code_off


class ClassData:
    __slots__ = ("static_fields", "instance_fields", "direct_methods", "virtual_methods")

    def __init__(self, static_fields, instance_fields, direct_methods, virtual_methods):
        self.static_fields = static_fields
        self.instance_fields = instance_fields
        self.direct_methods = direct_methods
        self.virtual_methods = virtual_methods


class ClassDef:
    __slots__ = ("type_idx", "access", "superclass_idx", "interfaces_off", "source_file_idx",
                 "annotations_off", "class_data_off", "static_values_off")

    def __init__(self, *fields):
        (self.type_idx, self.access, self.superclass_idx, self.interfaces_off, self.source_file_idx,
         self.annotations_off, self.class_data_off, self.static_values_off) = fields


class TryItem:
    __slots__ = ("start", "count", "handler")

    def __init__(self, start, count, handler):
        self.start = start
        self.count = count
        self.handler = handler


class CatchHandler:
    """typed clauses as (type_idx, address) in file order and the catch-all address or None"""
    __slots__ = ("clauses", "catch_all")

    def __init__(self, clauses, catch_all):
        self.clauses = clauses
        self.catch_all = catch_all


class CodeItem:
    __slots__ = ("registers", "ins", "outs", "debug_info_off", "insns", "tries", "handlers")

    def __init__(self, registers, ins, outs, debug_info_off, insns, tries, handlers):
        self.registers = registers
        self.ins = ins
        self.outs = outs
        self.debug_info_off = debug_info_off
        self.insns = insns
        self.tries = tries
        self.handlers = handlers


class MethodHandleItem:
    __slots__ = ("kind", "target_idx")

    def __init__(self, kind, target_idx):
        self.kind = kind
        self.target_idx = target_idx


class Annotation:
    """visibility, the descriptor of the annotation type and its elements as (name, value) pairs. a value is a tuple (kind, payload) of the encoded_value kind and the decoded payload"""
    __slots__ = ("visibility", "type", "elements")

    def __init__(self, visibility, type_, elements):
        self.visibility = visibility
        self.type = type_
        self.elements = elements


def uleb128(data, pos, end):
    result = 0
    shift = 0
    for _ in range(5):
        if pos >= end:
            raise DexFormatError("leb128 runs out of the data")
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, pos
        shift += 7
    raise DexFormatError("leb128 longer than five bytes")


def uleb128p1(data, pos, end):
    value, pos = uleb128(data, pos, end)
    return value - 1, pos


def sleb128(data, pos, end):
    result = 0
    shift = 0
    for _ in range(5):
        if pos >= end:
            raise DexFormatError("leb128 runs out of the data")
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            if byte & 0x40:
                result -= 1 << shift
            return result, pos
    raise DexFormatError("leb128 longer than five bytes")


def decode_mutf8(data, pos, end, utf16_size):
    """modified utf-8 up to the terminating zero, into a str of utf-16 code units. a four byte form, an overlong form that is not the encoding of U+0000, a stray continuation byte or a bare zero inside the string is malformed"""
    units = []
    append = units.append
    while True:
        if pos >= end:
            raise DexFormatError("string is not terminated")
        first = data[pos]
        pos += 1
        if first == 0:
            break
        if first < 0x80:
            append(first)
        elif first & 0xE0 == 0xC0:
            if pos >= end:
                raise DexFormatError("string is cut in a two byte form")
            second = data[pos]
            pos += 1
            if second & 0xC0 != 0x80:
                raise DexFormatError("bad continuation byte in a string")
            unit = (first & 0x1F) << 6 | (second & 0x3F)
            if unit and unit < 0x80:
                raise DexFormatError("overlong two byte form in a string")
            append(unit)
        elif first & 0xF0 == 0xE0:
            if pos + 1 >= end:
                raise DexFormatError("string is cut in a three byte form")
            second = data[pos]
            third = data[pos + 1]
            pos += 2
            if second & 0xC0 != 0x80 or third & 0xC0 != 0x80:
                raise DexFormatError("bad continuation byte in a string")
            unit = (first & 0x0F) << 12 | (second & 0x3F) << 6 | (third & 0x3F)
            if unit < 0x800:
                raise DexFormatError("overlong three byte form in a string")
            append(unit)
        elif first & 0xF8 == 0xF0:
            raise DexFormatError("four byte form in a string")
        else:
            raise DexFormatError("bad lead byte in a string")
        if len(units) > utf16_size:
            raise DexFormatError("string is longer than its declared size")
    if len(units) != utf16_size:
        raise DexFormatError("string length differs from its declared size")
    return "".join(map(chr, units))


def encode_mutf8(text):
    """the inverse of decode_mutf8 for a str of code units; used by tests and by the dex builders of the fixtures"""
    out = bytearray()
    for char in text:
        unit = ord(char)
        if unit > 0xFFFF:
            raise ValueError("a java string holds utf-16 code units only")
        if 0 < unit < 0x80:
            out.append(unit)
        elif unit < 0x800:
            out += bytes((0xC0 | unit >> 6, 0x80 | unit & 0x3F))
        else:
            out += bytes((0xE0 | unit >> 12, 0x80 | unit >> 6 & 0x3F, 0x80 | unit & 0x3F))
    return bytes(out)


def utf16_units(text):
    """a python str of any code points as the str of utf-16 code units a java string holds"""
    if max(text, default="\0") <= "\uffff":
        return text
    raw = text.encode("utf-16-le", "surrogatepass")
    return "".join(map(chr, struct.unpack("<%dH" % (len(raw) // 2), raw)))


class DexFile:
    """one dex file. the tables are read at construction, strings and items on demand and then kept"""

    def __init__(self, data, name="<memory>", verify_checksum=True):
        data = bytes(data)
        self.name = name
        self.data = data
        size = len(data)
        if size > MAX_FILE_SIZE:
            raise DexFormatError("dex file larger than %d bytes" % MAX_FILE_SIZE)
        if size < 0x70:
            raise DexFormatError("dex file shorter than its header")
        magic = data[:8]
        if magic[:4] != b"dex\n" or magic[7] != 0 or magic[4:7] not in SUPPORTED_VERSIONS:
            if magic[:4] == b"dex\n" and magic[7] == 0:
                raise DexFormatError("dex version %s is not supported" % magic[4:7].decode("ascii", "replace"))
            raise DexFormatError("bad dex magic")
        self.version = int(magic[4:7])
        (self.checksum,) = struct.unpack_from("<I", data, 8)
        self.signature = data[12:32]
        (file_size, header_size, endian, link_size, link_off, map_off,
         string_size, string_off, type_size, type_off, proto_size, proto_off, field_size, field_off,
         method_size, method_off, class_size, class_off, data_size, data_off) = struct.unpack_from("<20I", data, 32)
        if endian != ENDIAN_CONSTANT:
            raise DexFormatError("dex byte order is not little endian" if endian == REVERSE_ENDIAN_CONSTANT
                                 else "bad dex endian tag")
        if header_size != 0x70:
            raise DexFormatError("bad dex header size")
        if file_size != size:
            raise DexFormatError("dex file size field differs from the data")
        if verify_checksum and zlib.adler32(data[12:]) & 0xFFFFFFFF != self.checksum:
            raise DexFormatError("dex checksum mismatch")
        self.header_size = header_size
        self.map_off = map_off
        self.data_off = data_off
        self.data_size = data_size
        self._check_range("data", data_off, data_size)
        if link_size or link_off:
            self._check_range("link", link_off, link_size)
        self._strings = [None] * string_size
        self._string_offsets = self._table("string_ids", string_off, string_size, 4, "<I")
        self._types = self._table("type_ids", type_off, type_size, 4, "<I")
        self._protos = self._table("proto_ids", proto_off, proto_size, 12, "<3I")
        self._fields = self._table("field_ids", field_off, field_size, 8, "<HHI")
        self._methods = self._table("method_ids", method_off, method_size, 8, "<HHI")
        self._class_defs = self._table("class_defs", class_off, class_size, 32, "<8I")
        self._type_cache = [None] * type_size
        self._proto_cache = [None] * proto_size
        self._field_cache = [None] * field_size
        self._method_cache = [None] * method_size
        self._type_lists = {}
        self._code = {}
        self._class_data = {}
        self._handle_items = None
        self._call_site_offsets = None
        self._sha256 = None
        self._validate_tables()

    def _check_range(self, what, offset, length):
        if offset > len(self.data) or length > len(self.data) - offset:
            raise DexFormatError("%s leaves the file" % what)

    def _table(self, what, offset, count, width, layout):
        if count == 0:
            return ()
        if offset < self.header_size:
            raise DexFormatError("%s starts inside the header" % what)
        self._check_range(what, offset, count * width)
        return tuple(struct.iter_unpack(layout, self.data[offset:offset + count * width]))

    def _validate_tables(self):
        strings = len(self._strings)
        types = len(self._types)
        protos = len(self._protos)
        for (offset,) in self._string_offsets:
            if offset < self.header_size or offset >= len(self.data):
                raise DexFormatError("string data offset leaves the file")
        for (descriptor,) in self._types:
            if descriptor >= strings:
                raise DexFormatError("type descriptor index out of range")
        for shorty, return_type, parameters_off in self._protos:
            if shorty >= strings or return_type >= types:
                raise DexFormatError("proto index out of range")
            if parameters_off and parameters_off < self.header_size:
                raise DexFormatError("proto parameters inside the header")
        for class_type, type_, name in self._fields:
            if class_type >= types or type_ >= types or name >= strings:
                raise DexFormatError("field id index out of range")
        for class_type, proto, name in self._methods:
            if class_type >= types or proto >= protos or name >= strings:
                raise DexFormatError("method id index out of range")
        for class_def in self._class_defs:
            if class_def[0] >= types:
                raise DexFormatError("class definition type index out of range")
            if class_def[2] != NO_INDEX and class_def[2] >= types:
                raise DexFormatError("class definition superclass index out of range")
            if class_def[4] != NO_INDEX and class_def[4] >= strings:
                raise DexFormatError("class definition source file index out of range")

    @property
    def sha256(self):
        if self._sha256 is None:
            self._sha256 = hashlib.sha256(self.data).hexdigest()
        return self._sha256

    def string_count(self):
        return len(self._strings)

    def type_count(self):
        return len(self._types)

    def proto_count(self):
        return len(self._protos)

    def field_count(self):
        return len(self._fields)

    def method_count(self):
        return len(self._methods)

    def class_count(self):
        return len(self._class_defs)

    def string(self, index):
        if index >= len(self._strings):
            raise DexFormatError("string index out of range")
        text = self._strings[index]
        if text is None:
            data = self.data
            offset = self._string_offsets[index][0]
            size, pos = uleb128(data, offset, len(data))
            text = self._strings[index] = decode_mutf8(data, pos, len(data), size)
        return text

    def type(self, index):
        """descriptor of a type id, such as Ljava/lang/String; or [I"""
        if index >= len(self._types):
            raise DexFormatError("type index out of range")
        found = self._type_cache[index]
        if found is None:
            found = self._type_cache[index] = self.string(self._types[index][0])
            if not valid_descriptor(found):
                raise DexFormatError("bad type descriptor %r" % found)
        return found

    def type_list(self, offset):
        if not offset:
            return ()
        found = self._type_lists.get(offset)
        if found is None:
            data = self.data
            self._check_range("type list", offset, 4)
            (count,) = struct.unpack_from("<I", data, offset)
            self._check_range("type list", offset + 4, count * 2)
            found = self._type_lists[offset] = tuple(
                self.type(index) for (index,) in struct.iter_unpack("<H", data[offset + 4:offset + 4 + count * 2]))
        return found

    def proto(self, index):
        if index >= len(self._protos):
            raise DexFormatError("proto index out of range")
        found = self._proto_cache[index]
        if found is None:
            shorty, return_type, parameters_off = self._protos[index]
            found = self._proto_cache[index] = Proto(self.string(shorty), self.type(return_type),
                                                     self.type_list(parameters_off))
        return found

    def field(self, index):
        if index >= len(self._fields):
            raise DexFormatError("field index out of range")
        found = self._field_cache[index]
        if found is None:
            class_type, type_, name = self._fields[index]
            found = self._field_cache[index] = FieldId(self.type(class_type), self.type(type_), self.string(name))
        return found

    def method(self, index):
        if index >= len(self._methods):
            raise DexFormatError("method index out of range")
        found = self._method_cache[index]
        if found is None:
            class_type, proto, name = self._methods[index]
            found = self._method_cache[index] = MethodId(self.type(class_type), self.proto(proto), self.string(name))
        return found

    def class_def(self, index):
        if index >= len(self._class_defs):
            raise DexFormatError("class index out of range")
        return ClassDef(*self._class_defs[index])

    def class_descriptors(self):
        return [self.type(class_def[0]) for class_def in self._class_defs]

    def class_defs(self):
        return [ClassDef(*fields) for fields in self._class_defs]

    def class_data(self, class_def):
        """the fields and methods of a class, with absolute indices and absolute access flags"""
        offset = class_def.class_data_off
        if not offset:
            return ClassData((), (), (), ())
        found = self._class_data.get(offset)
        if found is not None:
            return found
        data = self.data
        end = len(data)
        if offset < self.header_size or offset >= end:
            raise DexFormatError("class data leaves the file")
        sizes = []
        pos = offset
        for _ in range(4):
            value, pos = uleb128(data, pos, end)
            sizes.append(value)
        # each encoded member takes at least two bytes, so a count above the rest of the file is a lie
        if sum(sizes) * 2 > end - pos:
            raise DexFormatError("class data member counts exceed the file")
        groups = []
        for which, size in enumerate(sizes):
            members = []
            index = 0
            for _ in range(size):
                diff, pos = uleb128(data, pos, end)
                access, pos = uleb128(data, pos, end)
                index += diff
                if which < 2:
                    if index >= len(self._fields):
                        raise DexFormatError("class data field index out of range")
                    members.append(EncodedField(index, access))
                else:
                    code_off, pos = uleb128(data, pos, end)
                    if index >= len(self._methods):
                        raise DexFormatError("class data method index out of range")
                    members.append(EncodedMethod(index, access, code_off))
            groups.append(tuple(members))
        found = self._class_data[offset] = ClassData(*groups)
        return found

    def interfaces(self, class_def):
        return self.type_list(class_def.interfaces_off)

    def superclass(self, class_def):
        if class_def.superclass_idx == NO_INDEX:
            return None
        return self.type(class_def.superclass_idx)

    def source_file(self, class_def):
        if class_def.source_file_idx == NO_INDEX:
            return None
        return self.string(class_def.source_file_idx)

    def code(self, code_off):
        """the code item at an absolute offset, or None for an abstract or native method"""
        if not code_off:
            return None
        found = self._code.get(code_off)
        if found is not None:
            return found
        data = self.data
        end = len(data)
        if code_off < self.header_size or code_off % 4 or code_off + 16 > end:
            raise DexFormatError("code item leaves the file or is misaligned")
        registers, ins, outs, tries, debug_off, insns_size = struct.unpack_from("<4HII", data, code_off)
        if ins > registers:
            raise DexFormatError("code item has more arguments than registers")
        insns_start = code_off + 16
        self._check_range("instructions", insns_start, insns_size * 2)
        insns = struct.unpack_from("<%dH" % insns_size, data, insns_start)
        pos = insns_start + insns_size * 2
        try_items = ()
        handlers = {}
        if tries:
            if insns_size & 1:
                pos += 2
            self._check_range("try items", pos, tries * 8)
            try_items = tuple(TryItem(*fields) for fields in struct.iter_unpack("<IHH", data[pos:pos + tries * 8]))
            pos += tries * 8
            list_start = pos
            count, pos = uleb128(data, pos, end)
            if count > end - pos:
                raise DexFormatError("catch handler count exceeds the file")
            for _ in range(count):
                offset = pos - list_start
                size, pos = sleb128(data, pos, end)
                typed = abs(size)
                if typed > end - pos:
                    raise DexFormatError("catch clause count exceeds the file")
                clauses = []
                for _ in range(typed):
                    type_idx, pos = uleb128(data, pos, end)
                    address, pos = uleb128(data, pos, end)
                    if type_idx >= len(self._types):
                        raise DexFormatError("catch type index out of range")
                    clauses.append((type_idx, address))
                catch_all = None
                if size <= 0:
                    catch_all, pos = uleb128(data, pos, end)
                handlers[offset] = CatchHandler(tuple(clauses), catch_all)
            for item in try_items:
                if item.handler not in handlers:
                    raise DexFormatError("try item points into the middle of a catch handler")
                if item.start + item.count > insns_size:
                    raise DexFormatError("try range leaves the instructions")
            for handler in handlers.values():
                addresses = [address for _, address in handler.clauses]
                if handler.catch_all is not None:
                    addresses.append(handler.catch_all)
                if any(address >= insns_size for address in addresses):
                    raise DexFormatError("catch handler address leaves the instructions")
        found = self._code[code_off] = CodeItem(registers, ins, outs, debug_off, insns, try_items, handlers)
        return found

    def encoded_array(self, offset):
        """static values or a call site array as a list of (kind, payload)"""
        if offset < self.header_size or offset >= len(self.data):
            raise DexFormatError("encoded array leaves the file")
        values, _ = self._array(offset, len(self.data), 0)
        return values

    def static_values(self, class_def):
        if not class_def.static_values_off:
            return []
        return self.encoded_array(class_def.static_values_off)

    def _array(self, pos, end, depth):
        if depth > MAX_ANNOTATION_DEPTH:
            raise DexFormatError("encoded values nested too deeply")
        count, pos = uleb128(self.data, pos, end)
        if count > MAX_ENCODED_ARRAY or count > end - pos:
            raise DexFormatError("encoded array too large")
        values = []
        for _ in range(count):
            value, pos = self._value(pos, end, depth)
            values.append(value)
        return values, pos

    def _value(self, pos, end, depth):
        data = self.data
        if pos >= end:
            raise DexFormatError("encoded value runs out of the data")
        header = data[pos]
        pos += 1
        kind = header & 0x1F
        arg = header >> 5
        if kind == VALUE_NULL:
            if arg:
                raise DexFormatError("null value with an argument")
            return (VALUE_NULL, None), pos
        if kind == VALUE_BOOLEAN:
            if arg > 1:
                raise DexFormatError("boolean value argument above one")
            return (VALUE_BOOLEAN, bool(arg)), pos
        if kind == VALUE_ARRAY:
            if arg:
                raise DexFormatError("array value with an argument")
            values, pos = self._array(pos, end, depth + 1)
            return (VALUE_ARRAY, values), pos
        if kind == VALUE_ANNOTATION:
            if arg:
                raise DexFormatError("annotation value with an argument")
            annotation, pos = self._encoded_annotation(pos, end, VISIBILITY_RUNTIME, depth + 1)
            return (VALUE_ANNOTATION, annotation), pos
        width = arg + 1
        if pos + width > end:
            raise DexFormatError("encoded value runs out of the data")
        raw = data[pos:pos + width]
        pos += width
        if kind in (VALUE_BYTE, VALUE_SHORT, VALUE_INT, VALUE_LONG):
            limit = {VALUE_BYTE: 1, VALUE_SHORT: 2, VALUE_INT: 4, VALUE_LONG: 8}[kind]
            if width > limit:
                raise DexFormatError("integer value wider than its type")
            return (kind, int.from_bytes(raw, "little", signed=True)), pos
        if kind == VALUE_CHAR:
            if width > 2:
                raise DexFormatError("char value wider than two bytes")
            return (kind, int.from_bytes(raw, "little")), pos
        if kind == VALUE_FLOAT:
            if width > 4:
                raise DexFormatError("float value wider than four bytes")
            return (kind, struct.unpack("<f", bytes(4 - width) + raw)[0]), pos
        if kind == VALUE_DOUBLE:
            if width > 8:
                raise DexFormatError("double value wider than eight bytes")
            return (kind, struct.unpack("<d", bytes(8 - width) + raw)[0]), pos
        if kind in (VALUE_STRING, VALUE_TYPE, VALUE_FIELD, VALUE_METHOD, VALUE_ENUM, VALUE_METHOD_TYPE,
                    VALUE_METHOD_HANDLE):
            if width > 4:
                raise DexFormatError("index value wider than four bytes")
            index = int.from_bytes(raw, "little")
            return (kind, index), pos
        raise DexFormatError("unknown encoded value type 0x%02x" % kind)

    def _encoded_annotation(self, pos, end, visibility, depth):
        data = self.data
        type_idx, pos = uleb128(data, pos, end)
        size, pos = uleb128(data, pos, end)
        if size > end - pos:
            raise DexFormatError("annotation element count exceeds the file")
        elements = []
        for _ in range(size):
            name_idx, pos = uleb128(data, pos, end)
            value, pos = self._value(pos, end, depth)
            elements.append((self.string(name_idx), value))
        return Annotation(visibility, self.type(type_idx), tuple(elements)), pos

    def annotation_set(self, offset):
        """annotations of an annotation_set_item at an absolute offset"""
        if not offset:
            return ()
        data = self.data
        end = len(data)
        self._check_range("annotation set", offset, 4)
        (count,) = struct.unpack_from("<I", data, offset)
        self._check_range("annotation set", offset + 4, count * 4)
        result = []
        for (item_off,) in struct.iter_unpack("<I", data[offset + 4:offset + 4 + count * 4]):
            if item_off < self.header_size or item_off >= end:
                raise DexFormatError("annotation item leaves the file")
            visibility = data[item_off]
            if visibility > VISIBILITY_SYSTEM:
                raise DexFormatError("bad annotation visibility")
            annotation, _ = self._encoded_annotation(item_off + 1, end, visibility, 0)
            result.append(annotation)
        return tuple(result)

    def annotations_directory(self, class_def):
        """(class annotations, {field idx: annotations}, {method idx: annotations}, {method idx: [annotations per parameter]})"""
        offset = class_def.annotations_off
        if not offset:
            return (), {}, {}, {}
        data = self.data
        self._check_range("annotations directory", offset, 16)
        class_off, field_count, method_count, parameter_count = struct.unpack_from("<4I", data, offset)
        pos = offset + 16
        self._check_range("annotations directory", pos, (field_count + method_count + parameter_count) * 8)
        fields = {}
        methods = {}
        parameters = {}
        for _ in range(field_count):
            index, set_off = struct.unpack_from("<II", data, pos)
            pos += 8
            fields[index] = self.annotation_set(set_off)
        for _ in range(method_count):
            index, set_off = struct.unpack_from("<II", data, pos)
            pos += 8
            methods[index] = self.annotation_set(set_off)
        for _ in range(parameter_count):
            index, list_off = struct.unpack_from("<II", data, pos)
            pos += 8
            parameters[index] = self._annotation_set_ref_list(list_off)
        return self.annotation_set(class_off), fields, methods, parameters

    def _annotation_set_ref_list(self, offset):
        self._check_range("annotation set ref list", offset, 4)
        (count,) = struct.unpack_from("<I", self.data, offset)
        self._check_range("annotation set ref list", offset + 4, count * 4)
        return [self.annotation_set(set_off)
                for (set_off,) in struct.iter_unpack("<I", self.data[offset + 4:offset + 4 + count * 4])]

    def _map(self):
        if not self.map_off:
            return {}
        data = self.data
        self._check_range("map list", self.map_off, 4)
        (count,) = struct.unpack_from("<I", data, self.map_off)
        self._check_range("map list", self.map_off + 4, count * 12)
        return {kind: (size, offset) for kind, _, size, offset in
                struct.iter_unpack("<HHII", data[self.map_off + 4:self.map_off + 4 + count * 12])}

    def method_handle(self, index):
        if self._handle_items is None:
            size, offset = self._map().get(TYPE_METHOD_HANDLE_ITEM, (0, 0))
            self._check_range("method handles", offset, size * 8)
            items = []
            for kind, _, target, _ in struct.iter_unpack("<4H", self.data[offset:offset + size * 8]):
                if kind > METHOD_HANDLE_INVOKE_INTERFACE:
                    raise DexFormatError("bad method handle kind")
                items.append(MethodHandleItem(kind, target))
            self._handle_items = items
        if index >= len(self._handle_items):
            raise DexFormatError("method handle index out of range")
        return self._handle_items[index]

    def call_site(self, index):
        """the bootstrap arguments of a call site as an encoded array: linker method handle, name, method type, extra arguments"""
        if self._call_site_offsets is None:
            size, offset = self._map().get(TYPE_CALL_SITE_ID_ITEM, (0, 0))
            self._check_range("call sites", offset, size * 4)
            self._call_site_offsets = [off for (off,) in struct.iter_unpack("<I", self.data[offset:offset + size * 4])]
        if index >= len(self._call_site_offsets):
            raise DexFormatError("call site index out of range")
        return self.encoded_array(self._call_site_offsets[index])


def valid_descriptor(text):
    if not text:
        return False
    dims = 0
    while dims < len(text) and text[dims] == "[":
        dims += 1
    if dims > 255:
        return False
    rest = text[dims:]
    if len(rest) == 1:
        return rest in "ZBSCIJFD" or (rest == "V" and dims == 0)
    return len(rest) > 2 and rest[0] == "L" and rest[-1] == ";" and "\0" not in rest
