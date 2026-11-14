"""translation of one dex method into the source of a python function

the registers of the method become the local variables v0, v1 ... of the function; the arguments arrive in the
registers a dex method receives them in. a wide value (long, double) lives in the low register of its pair. a method
without a branch is straight line code; any other method is a loop over its basic blocks, `pc` holding the number of
the block that runs. a block that can throw sits inside a try that looks its handlers up by that number.

whatever needs a class, a method or a field of another class is a *site*: a global name the translated code calls,
bound to a stub that resolves the reference on its first execution, like the resolution of a dex runtime, so a
missing class surfaces at the instruction that names it. translate() returns the source and the site specs, it does
not load anything itself"""

from . import api, opcodes
from .format import ACC_STATIC
from .opcodes import DecodeError


class TranslateError(Exception):
    """a method the translator refuses: bad control flow, unknown opcode, inconsistent registers"""


WIDE = ("J", "D")

_TERMINATORS = frozenset(("return-void", "return", "return-wide", "return-object", "throw", "goto", "goto/16",
                          "goto/32"))

_INT_BIN = {
    "add-int": "{a} + {b}", "sub-int": "{a} - {b}", "mul-int": "{a} * {b}",
}
# the argument is parenthesised: << and >> bind weaker than +, so a bare shift would take the offset as part of its count
_WRAP32 = "(({}) + 2147483648 & 4294967295) - 2147483648"
_WRAP64 = "(({}) + 9223372036854775808 & 18446744073709551615) - 9223372036854775808"

_IF_OPS = {"eq": "==", "ne": "!=", "lt": "<", "ge": ">=", "gt": ">", "le": "<="}


class Translation:
    """code is the compiled form of source, set once it has been compiled or when the translation came from the cache,
    which stores no source; deps are the answers of the environment the translation was made under (see cache.py)"""
    __slots__ = ("source", "sites", "consts", "name", "handlers", "code", "deps")

    def __init__(self, source, sites, consts, handlers, code=None, deps=()):
        self.source = source
        self.sites = sites
        self.consts = consts
        self.handlers = handlers
        self.code = code
        self.deps = deps


def _is_wide(desc):
    return desc in WIDE


def _int_literal(value):
    return "(%d)" % value if value < 0 else str(value)


class Env:
    """what the translator asks of the linker. the default answers make a translation that is purely generic"""

    def dex_class(self, descriptor):
        """True when descriptor names a class (not an interface) defined by a dex file, so a virtual call on it is a plain attribute call"""
        return False

    def instance_field(self, class_desc, name, type_desc):
        """the attribute name of an instance field of a dex class, or None when the class is not a dex class or has no such field"""
        return None

    def own_static(self, class_desc, name, type_desc):
        """the attribute name of a static field declared by the class being translated, or None"""
        return None


class Translator:
    def __init__(self, dex, code, name, proto, access, class_desc, env=None, label=None, uid="0"):
        self.uid = uid
        self.dex = dex
        self.code = code
        self.method_name = name
        self.proto = proto
        self.access = access
        self.class_desc = class_desc
        self.env = env or Env()
        self.label = label or name
        self.sites = {}
        self.site_keys = {}
        self.consts = {}
        self.const_keys = {}
        self.lines = []
        self.indent = 1
        self.static = bool(access & ACC_STATIC)
        self.index = -1
        self.ticked = -2


    def site(self, *spec):
        found = self.site_keys.get(spec)
        if found is None:
            found = "_s%s_%d" % (self.uid, len(self.sites))
            self.sites[found] = spec
            self.site_keys[spec] = found
        return found

    def const(self, value, kind):
        # a table is cheap to rebuild and a dict cannot be a key, so only strings and byte payloads are shared
        key = (kind, value) if kind in ("string", "bytes") else (kind, id(value))
        found = self.const_keys.get(key)
        if found is None:
            found = "_k%s_%d" % (self.uid, len(self.consts))
            self.consts[found] = (kind, value)
            self.const_keys[key] = found
        return found

    def emit(self, line):
        self.lines.append("    " * self.indent + line)


    def run(self):
        code = self.code
        units = code.insns
        try:
            insns = opcodes.decode_all(units)
        except DecodeError as error:
            raise TranslateError(str(error)) from error
        self.insns = insns
        self.by_addr = {insn.addr: insn for insn in insns if insn.fmt != "payload"}
        self.payload_addrs = {insn.addr for insn in insns if insn.fmt == "payload"}
        self._check_targets()
        self._maybe_bits()
        self._blocks()
        params = self._parameters()
        self.lines = []
        straight = len(self.blocks) == 1 and not self.handlers_of
        self.straight = straight
        header = "def m(%s):" % ", ".join(params)
        if any(insn.name.startswith("invoke") for insn in insns):
            # a runaway recursion makes no backward jump, so a method that calls checks the budget on entry
            self.indent = 1
            self.emit("_tick()")
        if straight:
            self.indent = 1
            self._block_body(self.blocks[0], 0)
        else:
            self.emit("pc = 0")
            if self.handlers_by_block:
                self.emit("while True:")
                self.indent += 1
                self.emit("try:")
                self.indent += 1
                self.emit("while True:")
                self.indent += 1
                self._dispatch(0, len(self.blocks))
                self.indent -= 2
                self.emit("except Exception as _e:")
                self.indent += 1
                self.emit("_x = _jexc(_e)")
                self.emit("_h = _H%s.get(pc)" % self.uid)
                self.emit("if _h is None:")
                self.emit("    raise _x")
                self.emit("for _t, _p in _h:")
                self.emit("    if _t is None or _t(_x):")
                self.emit("        pc = _p")
                self.emit("        break")
                self.emit("else:")
                self.emit("    raise _x")
                self.indent -= 2
            else:
                self.emit("while True:")
                self.indent += 1
                self._dispatch(0, len(self.blocks))
                self.indent -= 1
        if not self.lines:
            self.emit("return")
        return Translation(header + "\n" + "\n".join(self.lines) + "\n", self.sites, self.consts,
                           self.handler_table)

    def _parameters(self):
        code = self.code
        reg = code.registers - code.ins
        params = []
        if not self.static:
            params.append("v%d" % reg)
            reg += 1
        for desc in self.proto.parameters:
            params.append("v%d" % reg)
            reg += 2 if _is_wide(desc) else 1
        if reg != code.registers:
            raise TranslateError("arguments of %s do not fill the %d incoming registers" %
                                 (self.label, code.ins))
        return params

    def _check_targets(self):
        for insn in self.insns:
            if insn.fmt == "payload":
                continue
            if insn.target is not None and insn.name not in ("packed-switch", "sparse-switch", "fill-array-data"):
                if insn.target not in self.by_addr:
                    raise TranslateError("branch at %04x leaves the method or lands inside an instruction" % insn.addr)
            self._check_registers(insn)
        for item in self.code.tries:
            if item.start not in self.by_addr:
                raise TranslateError("try range starts inside an instruction")
        for handler in self.code.handlers.values():
            for _, address in handler.clauses:
                if address not in self.by_addr:
                    raise TranslateError("catch handler lands inside an instruction")
            if handler.catch_all is not None and handler.catch_all not in self.by_addr:
                raise TranslateError("catch-all handler lands inside an instruction")

    def _check_registers(self, insn):
        limit = self.code.registers
        fields = []
        fmt = insn.fmt
        if fmt in ("12x", "22t", "22s", "22c", "22x", "32x"):
            fields = [insn.a, insn.b]
        elif fmt in ("11x", "11n", "21c", "21t", "21s", "21h", "31i", "31t", "31c", "51l"):
            fields = [insn.a]
        elif fmt in ("23x",):
            fields = [insn.a, insn.b, insn.c]
        elif fmt == "22b":
            fields = [insn.a, insn.b]
        elif fmt in ("35c", "3rc", "45cc", "4rcc"):
            fields = list(insn.regs)
        for reg in fields:
            if reg >= limit:
                raise TranslateError("%s at %04x uses register v%d of %d" % (insn.name, insn.addr, reg, limit))


    def _maybe_bits(self):
        """a const feeding a float or double operation holds the bits of the value, and const 0 is also how null is written. registers written by a const, or moved from one, are converted where a float, a double or a reference is expected"""
        maybe = set()
        null = set()
        moves = []
        object_moves = []
        for insn in self.insns:
            name = insn.name
            if name in ("const/4", "const/16", "const", "const/high16", "const-wide/16", "const-wide/32",
                        "const-wide", "const-wide/high16"):
                maybe.add(insn.a)
                if insn.lit == 0 and not name.startswith("const-wide"):
                    null.add(insn.a)
            elif name.startswith("move-object"):
                object_moves.append((insn.a, insn.b))
            elif name.startswith("move") and name not in ("move-result", "move-result-wide", "move-result-object",
                                                          "move-exception"):
                moves.append((insn.a, insn.b))
        for dest_set, pairs in ((maybe, moves), (null, object_moves)):
            changed = True
            while changed:
                changed = False
                for dest, source in pairs:
                    if source in dest_set and dest not in dest_set:
                        dest_set.add(dest)
                        changed = True
        self.maybe = maybe
        self.null = null

    def _ref(self, reg):
        """a register read where a reference is expected: a const 0 stands for null"""
        return "(None if v%d.__class__ is int else v%d)" % (reg, reg) if reg in self.null else "v%d" % reg

    def _f(self, reg):
        return "(v%d if v%d.__class__ is float else _bf(v%d))" % (reg, reg, reg) if reg in self.maybe else "v%d" % reg

    def _d(self, reg):
        return "(v%d if v%d.__class__ is float else _bd(v%d))" % (reg, reg, reg) if reg in self.maybe else "v%d" % reg


    def _blocks(self):
        by_addr = self.by_addr
        leaders = {0}
        for insn in self.insns:
            if insn.fmt == "payload":
                continue
            name = insn.name
            nxt = insn.addr + insn.size
            if name.startswith("if-"):
                leaders.add(insn.target)
                leaders.add(nxt)
            elif name in ("goto", "goto/16", "goto/32"):
                leaders.add(insn.target)
                leaders.add(nxt)
            elif name in ("packed-switch", "sparse-switch"):
                leaders.add(nxt)
                for target in self._switch_targets(insn):
                    leaders.add(target)
            elif name in ("return-void", "return", "return-wide", "return-object", "throw"):
                leaders.add(nxt)
        for item in self.code.tries:
            leaders.add(item.start)
            leaders.add(item.start + item.count)
        for handler in self.code.handlers.values():
            for _, address in handler.clauses:
                leaders.add(address)
            if handler.catch_all is not None:
                leaders.add(handler.catch_all)
        total = len(self.code.insns)
        leaders = sorted(address for address in leaders if address < total)
        addrs = []
        for address in leaders:
            if address in by_addr:
                addrs.append(address)
            elif address in self.payload_addrs:
                continue
            else:
                raise TranslateError("block starts inside an instruction at %04x" % address)
        self.block_of = {address: index for index, address in enumerate(addrs)}
        blocks = []
        position = 0
        real = [insn for insn in self.insns if insn.fmt != "payload"]
        for index, start in enumerate(addrs):
            end = addrs[index + 1] if index + 1 < len(addrs) else total
            members = []
            while position < len(real) and real[position].addr < end:
                insn = real[position]
                position += 1
                # padding nops follow a terminator before a payload: they are not code that can run
                if members and members[-1].name in _TERMINATORS:
                    continue
                members.append(insn)
            blocks.append((start, end, members))
        # a try item covers a whole block: the blocks are cut at every edge of every try range
        covering = {}
        for index, (start, end, _) in enumerate(blocks):
            for item in self.code.tries:
                if item.start <= start < item.start + item.count:
                    handler = self.code.handlers[item.handler]
                    entries = [(type_idx, address) for type_idx, address in handler.clauses]
                    if handler.catch_all is not None:
                        entries.append((None, handler.catch_all))
                    covering[index] = entries
                    break
        keep = self._reachable(blocks, covering, total)
        remap = {old: new for new, old in enumerate(keep)}
        self.block_of = {blocks[old][0]: new for old, new in remap.items()}
        self.blocks = [blocks[old] for old in keep]
        self.handlers_by_block = {}
        self.handler_table = {}
        for old, entries in covering.items():
            if old not in remap:
                continue
            table = []
            for type_idx, address in entries:
                desc = None if type_idx is None else self.dex.type(type_idx)
                table.append((desc, self.block_of[address]))
            self.handlers_by_block[remap[old]] = table
            self.handler_table[remap[old]] = tuple(table)
        self.handlers_of = set(self.handlers_by_block)

    def _reachable(self, blocks, covering, total):
        """the blocks that can run, in address order; a reachable block that would fall off the end of the method is an error"""
        index_of = {block[0]: index for index, block in enumerate(blocks)}
        seen = set()
        stack = [0]
        while stack:
            index = stack.pop()
            if index in seen:
                continue
            seen.add(index)
            start, end, members = blocks[index]
            successors = []
            if not members:
                raise TranslateError("empty block at %04x in %s" % (start, self.label))
            last = members[-1]
            name = last.name
            if name.startswith("if-"):
                successors += [last.target, last.addr + last.size]
            elif name in ("goto", "goto/16", "goto/32"):
                successors.append(last.target)
            elif name in ("packed-switch", "sparse-switch"):
                successors += self._switch_targets(last) + [last.addr + last.size]
            elif name in ("return-void", "return", "return-wide", "return-object", "throw"):
                pass
            else:
                successors.append(last.addr + last.size)
            for entry in covering.get(index, ()):
                successors.append(entry[1])
            for address in successors:
                target = index_of.get(address)
                if target is None:
                    raise TranslateError("method %s runs off its end or into a payload at %04x" % (self.label, address))
                stack.append(target)
        return sorted(seen)

    def _switch_targets(self, insn):
        units = self.code.insns
        payload = insn.target
        if payload not in self.payload_addrs:
            raise TranslateError("switch at %04x does not point at its payload" % insn.addr)
        try:
            if insn.name == "packed-switch":
                _, targets = opcodes.packed_switch_payload(units, payload, insn.addr)
            else:
                _, targets = opcodes.sparse_switch_payload(units, payload, insn.addr)
        except DecodeError as error:
            raise TranslateError(str(error)) from error
        for target in targets:
            if target not in self.by_addr:
                raise TranslateError("switch target of %04x leaves the method" % insn.addr)
        return targets

    def _dispatch(self, low, high):
        count = high - low
        if count <= 4:
            for index in range(low, high):
                keyword = "if" if index == low else "elif"
                self.emit("%s pc == %d:" % (keyword, index))
                self.indent += 1
                self._block_body(self.blocks[index], index)
                self.indent -= 1
            return
        middle = (low + high) // 2
        self.emit("if pc < %d:" % middle)
        self.indent += 1
        self._dispatch(low, middle)
        self.indent -= 1
        self.emit("else:")
        self.indent += 1
        self._dispatch(middle, high)
        self.indent -= 1

    def _block_body(self, block, index):
        start, end, members = block
        self.index = index
        before = len(self.lines)
        position = 0
        terminated = False
        while position < len(members):
            insn = members[position]
            fused = None
            if insn.name.startswith("invoke") or insn.name.startswith("filled-new-array"):
                if position + 1 < len(members) and members[position + 1].name in (
                        "move-result", "move-result-wide", "move-result-object"):
                    fused = members[position + 1]
            terminated = self._insn(insn, fused)
            position += 2 if fused is not None else 1
            if terminated:
                break
        if not terminated:
            # falls into the next block
            if self.straight:
                raise TranslateError("method %s runs off its end" % self.label)
            self.emit("pc = %d" % (index + 1))
        if len(self.lines) == before:
            self.emit("pass")

    def _go(self, target):
        index = self.block_of[target]
        # a jump back is a loop: the budget of the call is checked once per pass of the block that jumps
        if index <= self.index and self.ticked != self.index:
            self.ticked = self.index
            self.emit("_tick()")
        return index


    def _insn(self, insn, fused):
        name = insn.name
        handler = getattr(self, "op_" + name.replace("-", "_").replace("/", "_"), None)
        if handler is not None:
            return handler(insn, fused)
        for prefix, method in (
                ("if-", self._if), ("aget", self._aget), ("aput", self._aput), ("iget", self._iget),
                ("iput", self._iput), ("sget", self._sget), ("sput", self._sput), ("invoke-", self._invoke)):
            if name.startswith(prefix):
                return method(insn, fused)
        return self._arith(insn)

    def _assign(self, reg, expression):
        self.emit("v%d = %s" % (reg, expression))

    def op_nop(self, insn, fused):
        return False

    def _move(self, insn, fused):
        self.emit("v%d = v%d" % (insn.a, insn.b))
        return False

    op_move = op_move_from16 = op_move_16 = _move
    op_move_wide = op_move_wide_from16 = op_move_wide_16 = _move
    op_move_object = op_move_object_from16 = op_move_object_16 = _move

    def op_move_result(self, insn, fused):
        self.emit("v%d = _r" % insn.a)
        return False

    op_move_result_wide = op_move_result_object = op_move_result

    def op_move_exception(self, insn, fused):
        self.emit("v%d = _x" % insn.a)
        return False

    def op_return_void(self, insn, fused):
        self.emit("return")
        return True

    def _return(self, insn, fused):
        kind = self.proto.return_type
        if kind == "F":
            self.emit("return " + self._f(insn.a))
        elif kind == "D":
            self.emit("return " + self._d(insn.a))
        elif kind[0] in "L[":
            self.emit("return " + self._ref(insn.a))
        else:
            self.emit("return v%d" % insn.a)
        return True

    op_return = op_return_wide = op_return_object = _return

    def _const(self, insn, fused):
        self.emit("v%d = %s" % (insn.a, _int_literal(insn.lit)))
        return False

    op_const_4 = op_const_16 = op_const = op_const_high16 = _const
    op_const_wide_16 = op_const_wide_32 = op_const_wide = op_const_wide_high16 = _const

    def op_const_string(self, insn, fused):
        text = self.dex.string(insn.idx)
        self.emit("v%d = %s" % (insn.a, self.const(text, "string")))
        return False

    op_const_string_jumbo = op_const_string

    def op_const_class(self, insn, fused):
        site = self.site("const-class", self.dex.type(insn.idx))
        self.emit("v%d = %s()" % (insn.a, site))
        return False

    def op_const_method_handle(self, insn, fused):
        self.emit("v%d = %s()" % (insn.a, self.site("const-method-handle", insn.idx)))
        return False

    def op_const_method_type(self, insn, fused):
        self.emit("v%d = %s()" % (insn.a, self.site("const-method-type", insn.idx)))
        return False

    def op_monitor_enter(self, insn, fused):
        self.emit("_menter(%s)" % self._ref(insn.a))
        return False

    def op_monitor_exit(self, insn, fused):
        self.emit("_mexit(%s)" % self._ref(insn.a))
        return False

    def op_check_cast(self, insn, fused):
        self.emit("%s(%s)" % (self.site("check-cast", self.dex.type(insn.idx)), self._ref(insn.a)))
        return False

    def op_instance_of(self, insn, fused):
        self.emit("v%d = %s(%s)" % (insn.a, self.site("instance-of", self.dex.type(insn.idx)), self._ref(insn.b)))
        return False

    def op_array_length(self, insn, fused):
        self.emit("v%d = len(%s)" % (insn.a, self._ref(insn.b)))
        return False

    def op_new_instance(self, insn, fused):
        self.emit("v%d = %s()" % (insn.a, self.site("new-instance", self.dex.type(insn.idx))))
        return False

    def op_new_array(self, insn, fused):
        self.emit("v%d = %s(v%d)" % (insn.a, self.site("new-array", self.dex.type(insn.idx)), insn.b))
        return False

    def _filled(self, insn, fused):
        desc = self.dex.type(insn.idx)
        if not desc.startswith("["):
            raise TranslateError("filled-new-array of a non array type")
        if desc[1] in "L[":
            regs = ", ".join(self._ref(reg) for reg in insn.regs)
        else:
            regs = ", ".join("v%d" % reg for reg in insn.regs)
        call = "%s(%s)" % (self.site("filled-new-array", desc), regs)
        if fused is not None:
            self.emit("v%d = %s" % (fused.a, call))
        else:
            self.emit("_r = " + call)
        return False

    op_filled_new_array = op_filled_new_array_range = _filled

    def op_fill_array_data(self, insn, fused):
        if insn.target not in self.payload_addrs:
            raise TranslateError("fill-array-data does not point at its payload")
        width, raw, count = opcodes.fill_array_payload(self.code.insns, insn.target)
        self.emit("_fill(%s, %d, %s)" % (self._ref(insn.a), width, self.const(raw, "bytes")))
        return False

    def op_throw(self, insn, fused):
        self.emit("_throw(%s)" % self._ref(insn.a))
        return True

    def _goto(self, insn, fused):
        self.emit("pc = %d" % self._go(insn.target))
        return True

    op_goto = op_goto_16 = op_goto_32 = _goto

    def op_packed_switch(self, insn, fused):
        first, targets = opcodes.packed_switch_payload(self.code.insns, insn.target, insn.addr)
        table = self.const(tuple(self._go(t) for t in targets), "tuple")
        fall = self._go(insn.addr + insn.size)
        self.emit("_i = v%d - %d" % (insn.a, first))
        self.emit("pc = %s[_i] if 0 <= _i < %d else %d" % (table, len(targets), fall))
        return True

    def op_sparse_switch(self, insn, fused):
        keys, targets = opcodes.sparse_switch_payload(self.code.insns, insn.target, insn.addr)
        table = self.const({key: self._go(t) for key, t in zip(keys, targets)}, "dict")
        fall = self._go(insn.addr + insn.size)
        self.emit("pc = %s.get(v%d, %d)" % (table, insn.a, fall))
        return True

    def _cmp(self, insn, fused):
        a, b, c = insn.a, insn.b, insn.c
        name = insn.name
        if name == "cmp-long":
            self.emit("v%d = (v%d > v%d) - (v%d < v%d)" % (a, b, c, b, c))
        elif name.endswith("float"):
            self.emit("v%d = _%s(%s, %s)" % (a, "cmpl" if "cmpl" in name else "cmpg", self._f(b), self._f(c)))
        else:
            self.emit("v%d = _%s(%s, %s)" % (a, "cmpl" if "cmpl" in name else "cmpg", self._d(b), self._d(c)))
        return False

    op_cmpl_float = op_cmpg_float = op_cmpl_double = op_cmpg_double = op_cmp_long = _cmp

    def _if(self, insn, fused):
        operator = _IF_OPS[insn.name[3:5]]
        taken = self._go(insn.target)
        fall = self._go(insn.addr + insn.size)
        if insn.name.endswith("z"):
            reg = insn.a
            if operator == "==":
                cond = "v%d is None or v%d == 0" % (reg, reg)
            elif operator == "!=":
                cond = "v%d is not None and v%d != 0" % (reg, reg)
            else:
                cond = "v%d %s 0" % (reg, operator)
        else:
            a, b = insn.a, insn.b
            if operator == "==" and (a in self.null or b in self.null):
                cond = "(v%d == v%d) if (v%d.__class__ is int and v%d.__class__ is int) else (%s is %s)" % (
                    a, b, a, b, self._ref(a), self._ref(b))
            elif operator == "!=" and (a in self.null or b in self.null):
                cond = "(v%d != v%d) if (v%d.__class__ is int and v%d.__class__ is int) else (%s is not %s)" % (
                    a, b, a, b, self._ref(a), self._ref(b))
            elif operator == "==":
                cond = "v%d == v%d if v%d.__class__ is int else v%d is v%d" % (a, b, a, a, b)
            elif operator == "!=":
                cond = "v%d != v%d if v%d.__class__ is int else v%d is not v%d" % (a, b, a, a, b)
            else:
                cond = "v%d %s v%d" % (a, operator, b)
        self.emit("pc = %d if (%s) else %d" % (taken, cond, fall))
        return True


    def _aget(self, insn, fused):
        a, b, c = insn.a, insn.b, insn.c
        if b in self.null:
            self.emit("_arr = " + self._ref(b))
            self.emit("v%d = _arr[v%d] if 0 <= v%d < len(_arr) else _aioobe(_arr, v%d)" % (a, c, c, c))
            return False
        self.emit("v%d = v%d[v%d] if 0 <= v%d < len(v%d) else _aioobe(v%d, v%d)" % (a, b, c, c, b, b, c))
        return False

    def _aput(self, insn, fused):
        a, b, c = insn.a, insn.b, insn.c
        name = insn.name
        if name == "aput-object":
            self.emit("_aput_object(%s, v%d, %s)" % (self._ref(b), c, self._ref(a)))
            return False
        if b in self.null:
            self.emit("v%d = %s" % (b, self._ref(b)))
        narrow = {"aput-boolean": "v%d & 1", "aput-byte": "(v%d + 128 & 255) - 128",
                  "aput-char": "v%d & 65535", "aput-short": "(v%d + 32768 & 65535) - 32768"}.get(name)
        if narrow is not None:
            value = narrow % a
        elif a in self.maybe:
            self.emit("_aput_bits(v%d, v%d, v%d)" % (b, c, a))
            return False
        else:
            value = "v%d" % a
        self.emit("if 0 <= v%d < len(v%d):" % (c, b))
        self.emit("    v%d[v%d] = %s" % (b, c, value))
        self.emit("else:")
        self.emit("    _aioobe(v%d, v%d)" % (b, c))
        return False

    def _iget(self, insn, fused):
        ref = self.dex.field(insn.idx)
        attr = self.env.instance_field(ref.class_type, ref.name, ref.type)
        if attr is not None:
            self.emit("v%d = %s.%s" % (insn.a, self._ref(insn.b), attr))
        else:
            site = self.site("iget", ref.class_type, ref.name, ref.type)
            self.emit("v%d = %s(%s)" % (insn.a, site, self._ref(insn.b)))
        return False

    def _store_value(self, reg, type_desc):
        if type_desc == "Z":
            return "v%d & 1" % reg
        if type_desc == "B":
            return "(v%d + 128 & 255) - 128" % reg
        if type_desc == "S":
            return "(v%d + 32768 & 65535) - 32768" % reg
        if type_desc == "C":
            return "v%d & 65535" % reg
        if type_desc == "F":
            return self._f(reg)
        if type_desc == "D":
            return self._d(reg)
        if type_desc[0] in "L[":
            return self._ref(reg)
        return "v%d" % reg

    def _iput(self, insn, fused):
        ref = self.dex.field(insn.idx)
        value = self._store_value(insn.a, ref.type)
        attr = self.env.instance_field(ref.class_type, ref.name, ref.type)
        if attr is not None:
            self.emit("%s.%s = %s" % (self._ref(insn.b), attr, value))
        else:
            site = self.site("iput", ref.class_type, ref.name, ref.type)
            self.emit("%s(%s, %s)" % (site, self._ref(insn.b), value))
        return False

    def _sget(self, insn, fused):
        ref = self.dex.field(insn.idx)
        attr = self.env.own_static(ref.class_type, ref.name, ref.type)
        if attr is not None and ref.class_type == self.class_desc:
            self.emit("v%d = _C.%s" % (insn.a, attr))
        else:
            self.emit("v%d = %s()" % (insn.a, self.site("sget", ref.class_type, ref.name, ref.type)))
        return False

    def _sput(self, insn, fused):
        ref = self.dex.field(insn.idx)
        value = self._store_value(insn.a, ref.type)
        attr = self.env.own_static(ref.class_type, ref.name, ref.type)
        if attr is not None and ref.class_type == self.class_desc:
            self.emit("_C.%s = %s" % (attr, value))
        else:
            self.emit("%s(%s)" % (self.site("sput", ref.class_type, ref.name, ref.type), value))
        return False


    def _arguments(self, insn, params, has_receiver):
        regs = list(insn.regs)
        out = []
        position = 0
        if has_receiver:
            if not regs:
                raise TranslateError("instance invoke without a receiver at %04x" % insn.addr)
            out.append(self._ref(regs[0]))
            position = 1
        for desc in params:
            if position >= len(regs):
                raise TranslateError("invoke at %04x passes fewer registers than its prototype" % insn.addr)
            reg = regs[position]
            position += 2 if _is_wide(desc) else 1
            if desc == "F":
                out.append(self._f(reg))
            elif desc == "D":
                out.append(self._d(reg))
            elif desc[0] in "L[":
                out.append(self._ref(reg))
            else:
                out.append("v%d" % reg)
        if position != len(regs):
            raise TranslateError("invoke at %04x passes more registers than its prototype" % insn.addr)
        return out

    def _invoke(self, insn, fused):
        name = insn.name
        kind = name[7:].replace("/range", "")
        if kind == "custom":
            return self._custom(insn, fused)
        ref = self.dex.method(insn.idx)
        proto = ref.proto
        descriptor = proto.descriptor()
        if kind == "polymorphic":
            return self._polymorphic(insn, fused)
        has_receiver = kind != "static"
        args = self._arguments(insn, proto.parameters, has_receiver)
        owner = ref.class_type
        if kind == "direct" and ref.name == "<init>" and owner == "Ljava/lang/Object;":
            return False
        if kind in ("virtual",) and self.env.dex_class(owner):
            call = "%s.%s(%s)" % (args[0], api.method_attr(ref.name, descriptor), ", ".join(args[1:]))
        else:
            site = self.site("invoke-" + kind, owner, ref.name, descriptor)
            if kind == "direct" and ref.name == "<init>" and not self.env.dex_class(owner):
                # a constructor of a host class can return the finished value (String, boxes), so the register is rebound
                self.emit("v%d = %s(%s)" % (insn.regs[0], site, ", ".join(args)))
                return False
            call = "%s(%s)" % (site, ", ".join(args))
        if proto.return_type == "V":
            self.emit(call)
        elif fused is not None:
            self.emit("v%d = %s" % (fused.a, call))
        else:
            self.emit("_r = " + call)
        return False

    def _polymorphic(self, insn, fused):
        ref = self.dex.method(insn.idx)
        call_proto = self.dex.proto(insn.proto)
        args = self._arguments(insn, call_proto.parameters, True)
        site = self.site("invoke-polymorphic", ref.class_type, ref.name, call_proto.descriptor())
        call = "%s(%s)" % (site, ", ".join(args))
        if call_proto.return_type == "V":
            self.emit(call)
        elif fused is not None:
            self.emit("v%d = %s" % (fused.a, call))
        else:
            self.emit("_r = " + call)
        return False

    def _custom(self, insn, fused):
        values = self.dex.call_site(insn.idx)
        if len(values) < 3 or values[2][0] != 0x15:
            raise TranslateError("call site %d has no method type" % insn.idx)
        call_proto = self.dex.proto(values[2][1])
        args = self._arguments(insn, call_proto.parameters, False)
        call = "%s(%s)" % (self.site("invoke-custom", insn.idx), ", ".join(args))
        if call_proto.return_type == "V":
            self.emit(call)
        elif fused is not None:
            self.emit("v%d = %s" % (fused.a, call))
        else:
            self.emit("_r = " + call)
        return False


    def _arith(self, insn):
        name = insn.name
        a, b, c = insn.a, insn.b, insn.c
        fmt = insn.fmt
        lit = insn.lit
        if name.endswith("/2addr"):
            name = name[:-6]
            c = b
            b = a
        elif fmt in ("22s", "22b"):
            return self._arith_literal(insn)
        emit = self.emit
        if name in ("neg-int", "not-int", "neg-long", "not-long", "neg-float", "neg-double") or "-to-" in name:
            return self._unary(insn)
        kind = name.rsplit("-", 1)[1]
        op = name.rsplit("-", 1)[0]
        if kind == "int":
            wrap = _WRAP32
            x, y = "v%d" % b, "v%d" % c
            expr = {
                "add": wrap.format("%s + %s" % (x, y)), "sub": wrap.format("%s - %s" % (x, y)),
                "mul": wrap.format("%s * %s" % (x, y)), "div": "_idiv(%s, %s)" % (x, y),
                "rem": "_irem(%s, %s)" % (x, y), "and": "%s & %s" % (x, y), "or": "%s | %s" % (x, y),
                "xor": "%s ^ %s" % (x, y), "shl": wrap.format("%s << (%s & 31)" % (x, y)),
                "shr": "%s >> (%s & 31)" % (x, y),
                "ushr": wrap.format("(%s & 4294967295) >> (%s & 31)" % (x, y)),
            }[op]
        elif kind == "long":
            wrap = _WRAP64
            x, y = "v%d" % b, "v%d" % c
            expr = {
                "add": wrap.format("%s + %s" % (x, y)), "sub": wrap.format("%s - %s" % (x, y)),
                "mul": wrap.format("%s * %s" % (x, y)), "div": "_ldiv(%s, %s)" % (x, y),
                "rem": "_lrem(%s, %s)" % (x, y), "and": "%s & %s" % (x, y), "or": "%s | %s" % (x, y),
                "xor": "%s ^ %s" % (x, y), "shl": wrap.format("%s << (%s & 63)" % (x, y)),
                "shr": "%s >> (%s & 63)" % (x, y),
                "ushr": wrap.format("(%s & 18446744073709551615) >> (%s & 63)" % (x, y)),
            }[op]
        elif kind == "float":
            x, y = self._f(b), self._f(c)
            expr = {
                "add": "_f32(%s + %s)" % (x, y), "sub": "_f32(%s - %s)" % (x, y),
                "mul": "_f32(%s * %s)" % (x, y), "div": "_fdiv(%s, %s)" % (x, y),
                "rem": "_frem(%s, %s)" % (x, y),
            }[op]
        elif kind == "double":
            x, y = self._d(b), self._d(c)
            expr = {
                "add": "%s + %s" % (x, y), "sub": "%s - %s" % (x, y), "mul": "%s * %s" % (x, y),
                "div": "_ddiv(%s, %s)" % (x, y), "rem": "_drem(%s, %s)" % (x, y),
            }[op]
        else:
            raise TranslateError("unsupported instruction %s at %04x" % (insn.name, insn.addr))
        emit("v%d = %s" % (a, expr))
        return False

    def _arith_literal(self, insn):
        name = insn.name.replace("/lit16", "").replace("/lit8", "")
        a, b, lit = insn.a, insn.b, insn.lit
        x = "v%d" % b
        wrap = _WRAP32
        value = _int_literal(lit)
        expr = {
            "add-int": wrap.format("%s + %s" % (x, value)),
            "rsub-int": wrap.format("%s - %s" % (value, x)),
            "mul-int": wrap.format("%s * %s" % (x, value)),
            "div-int": "_idiv(%s, %s)" % (x, value),
            "rem-int": "_irem(%s, %s)" % (x, value),
            "and-int": "%s & %s" % (x, value),
            "or-int": "%s | %s" % (x, value),
            "xor-int": "%s ^ %s" % (x, value),
            "shl-int": wrap.format("%s << %d" % (x, lit & 31)),
            "shr-int": "%s >> %d" % (x, lit & 31),
            "ushr-int": (wrap.format("(%s & 4294967295) >> %d" % (x, lit & 31)) if lit & 31 == 0
                         else "(%s & 4294967295) >> %d" % (x, lit & 31)),
        }.get(name)
        if expr is None:
            raise TranslateError("unsupported instruction %s at %04x" % (insn.name, insn.addr))
        self.emit("v%d = %s" % (a, expr))
        return False

    def _unary(self, insn):
        name = insn.name
        if name.endswith("/2addr"):
            name = name[:-6]
        a, b = insn.a, insn.b
        x = "v%d" % b
        expr = {
            "neg-int": _WRAP32.format("-" + x), "not-int": "~" + x,
            "neg-long": _WRAP64.format("-" + x), "not-long": "~" + x,
            "neg-float": "-" + self._f(b), "neg-double": "-" + self._d(b),
            "int-to-long": x, "int-to-float": "_f32(%s)" % x, "int-to-double": "float(%s)" % x,
            "long-to-int": _WRAP32.format(x), "long-to-float": "_f32(%s)" % x,
            "long-to-double": "float(%s)" % x,
            "float-to-int": "_d2i(%s)" % self._f(b), "float-to-long": "_d2l(%s)" % self._f(b),
            "float-to-double": self._f(b),
            "double-to-int": "_d2i(%s)" % self._d(b), "double-to-long": "_d2l(%s)" % self._d(b),
            "double-to-float": "_f32(%s)" % self._d(b),
            "int-to-byte": "(%s + 128 & 255) - 128" % x, "int-to-char": "%s & 65535" % x,
            "int-to-short": "(%s + 32768 & 65535) - 32768" % x,
        }.get(name)
        if expr is None:
            raise TranslateError("unsupported instruction %s at %04x" % (insn.name, insn.addr))
        self.emit("v%d = %s" % (a, expr))
        return False


def translate(dex, code, name, proto, access, class_desc, env=None, label=None, uid="0"):
    """the Translation of a method body; uid keeps the global names of the methods of one class apart"""
    return Translator(dex, code, name, proto, access, class_desc, env, label, uid).run()
