#include "exteria_dexnative.h"

/* all arithmetic goes through unsigned types: signed overflow is undefined in c, wrapping is the java rule */

static int64_t wrap32(uint64_t value) {
    uint32_t low = (uint32_t)(value & 0xFFFFFFFFu);
    return low >= 0x80000000u ? (int64_t)low - 4294967296LL : (int64_t)low;
}

static int64_t shift_right_signed32(int64_t value, uint32_t count) {
    return value < 0 ? ~((~value) >> count) : value >> count;
}

static int64_t shift_right_signed64(int64_t value, uint32_t count) {
    return value < 0 ? ~((~value) >> count) : value >> count;
}

int exteria_dexnative_validate(const exteria_dexnative_insn *program, size_t count, uint32_t nregs) {
    if (!program || count == 0 || count > EXTERIA_DEXNATIVE_MAX_INSNS || nregs == 0 || nregs > EXTERIA_DEXNATIVE_MAX_REGISTERS) {
        return EXTERIA_DEXNATIVE_BAD_PROGRAM;
    }
    for (size_t i = 0; i < count; ++i) {
        const exteria_dexnative_insn *insn = &program[i];
        int32_t op = insn->op;
        if (op < 0 || op >= DN_OP_COUNT) return EXTERIA_DEXNATIVE_BAD_PROGRAM;
        uint32_t used = 0;     /* bit 0: a is a register, bit 1: b is, bit 2: c is */
        int jump = 0;
        switch (op) {
        case DN_NOP: case DN_RETURN_VOID: break;
        case DN_GOTO: jump = 1; break;
        case DN_CONST: case DN_CONST_WIDE: case DN_RETURN: used = 1; break;
        case DN_MOVE: case DN_NEG_I: case DN_NOT_I: case DN_NEG_L: case DN_NOT_L: case DN_I2L: case DN_L2I:
        case DN_I2B: case DN_I2C: case DN_I2S: used = 3; break;
        case DN_ADD_LIT: case DN_RSUB_LIT: case DN_MUL_LIT: case DN_DIV_LIT: case DN_REM_LIT: case DN_AND_LIT:
        case DN_OR_LIT: case DN_XOR_LIT: case DN_SHL_LIT: case DN_SHR_LIT: case DN_USHR_LIT: used = 3; break;
        case DN_IF_EQ: case DN_IF_NE: case DN_IF_LT: case DN_IF_GE: case DN_IF_GT: case DN_IF_LE: used = 3; jump = 1; break;
        case DN_IF_EQZ: case DN_IF_NEZ: case DN_IF_LTZ: case DN_IF_GEZ: case DN_IF_GTZ: case DN_IF_LEZ: used = 1; jump = 1; break;
        default: used = 7; break;       /* the three register arithmetic forms and cmp-long */
        }
        if (((used & 1u) && (insn->a < 0 || (uint32_t)insn->a >= nregs)) ||
            ((used & 2u) && (insn->b < 0 || (uint32_t)insn->b >= nregs)) ||
            ((used & 4u) && (insn->c < 0 || (uint32_t)insn->c >= nregs))) {
            return EXTERIA_DEXNATIVE_BAD_PROGRAM;
        }
        if (jump && (insn->c < 0 || (size_t)insn->c >= count)) return EXTERIA_DEXNATIVE_BAD_PROGRAM;
    }
    int32_t last = program[count - 1].op;
    if (last != DN_GOTO && last != DN_RETURN && last != DN_RETURN_VOID) return EXTERIA_DEXNATIVE_BAD_PROGRAM;
    return 0;
}

static int64_t div32(int64_t x, int64_t y, int *zero, int remainder) {
    if (y == 0) {
        *zero = 1;
        return 0;
    }
    if (y == -1) return remainder ? 0 : wrap32((uint64_t)(-x));
    return remainder ? x % y : x / y;
}

static int64_t div64(int64_t x, int64_t y, int *zero, int remainder) {
    if (y == 0) {
        *zero = 1;
        return 0;
    }
    if (y == -1) return remainder ? 0 : (int64_t)(0 - (uint64_t)x);
    return remainder ? x % y : x / y;
}

exteria_dexnative_status exteria_dexnative_run(const exteria_dexnative_insn *program, size_t count, int64_t *regs,
                                               uint32_t nregs, uint32_t *pc, uint64_t max_back_jumps,
                                               uint64_t *back_jumps, int64_t *result) {
    if (!program || !regs || !pc || !back_jumps || !result || exteria_dexnative_validate(program, count, nregs) != 0 ||
        *pc >= count) {
        return EXTERIA_DEXNATIVE_BAD_PROGRAM;
    }
    uint64_t jumps = 0;
    uint32_t at = *pc;
    *back_jumps = 0;
    for (;;) {
        const exteria_dexnative_insn *insn = &program[at];
        uint32_t next = at + 1;
        int64_t x = 0, y = 0;
        int zero = 0;
        int taken = 0;
        switch (insn->op) {
        case DN_NOP: break;
        case DN_MOVE: regs[insn->a] = regs[insn->b]; break;
        case DN_CONST: regs[insn->a] = (int64_t)insn->b; break;
        case DN_CONST_WIDE:
            regs[insn->a] = (int64_t)(((uint64_t)(uint32_t)insn->c << 32) | (uint64_t)(uint32_t)insn->b);
            break;

        case DN_ADD_I: regs[insn->a] = wrap32((uint64_t)regs[insn->b] + (uint64_t)regs[insn->c]); break;
        case DN_SUB_I: regs[insn->a] = wrap32((uint64_t)regs[insn->b] - (uint64_t)regs[insn->c]); break;
        case DN_MUL_I: regs[insn->a] = wrap32((uint64_t)regs[insn->b] * (uint64_t)regs[insn->c]); break;
        case DN_DIV_I: regs[insn->a] = div32(regs[insn->b], regs[insn->c], &zero, 0); break;
        case DN_REM_I: regs[insn->a] = div32(regs[insn->b], regs[insn->c], &zero, 1); break;
        case DN_AND_I: case DN_AND_L: regs[insn->a] = regs[insn->b] & regs[insn->c]; break;
        case DN_OR_I: case DN_OR_L: regs[insn->a] = regs[insn->b] | regs[insn->c]; break;
        case DN_XOR_I: case DN_XOR_L: regs[insn->a] = regs[insn->b] ^ regs[insn->c]; break;
        case DN_SHL_I: regs[insn->a] = wrap32((uint64_t)regs[insn->b] << (regs[insn->c] & 31)); break;
        case DN_SHR_I: regs[insn->a] = shift_right_signed32(regs[insn->b], (uint32_t)(regs[insn->c] & 31)); break;
        case DN_USHR_I:
            regs[insn->a] = wrap32((uint64_t)((uint32_t)(regs[insn->b] & 0xFFFFFFFF)) >> (regs[insn->c] & 31));
            break;

        case DN_ADD_L: regs[insn->a] = (int64_t)((uint64_t)regs[insn->b] + (uint64_t)regs[insn->c]); break;
        case DN_SUB_L: regs[insn->a] = (int64_t)((uint64_t)regs[insn->b] - (uint64_t)regs[insn->c]); break;
        case DN_MUL_L: regs[insn->a] = (int64_t)((uint64_t)regs[insn->b] * (uint64_t)regs[insn->c]); break;
        case DN_DIV_L: regs[insn->a] = div64(regs[insn->b], regs[insn->c], &zero, 0); break;
        case DN_REM_L: regs[insn->a] = div64(regs[insn->b], regs[insn->c], &zero, 1); break;
        case DN_SHL_L: regs[insn->a] = (int64_t)((uint64_t)regs[insn->b] << (regs[insn->c] & 63)); break;
        case DN_SHR_L: regs[insn->a] = shift_right_signed64(regs[insn->b], (uint32_t)(regs[insn->c] & 63)); break;
        case DN_USHR_L: regs[insn->a] = (int64_t)((uint64_t)regs[insn->b] >> (regs[insn->c] & 63)); break;

        case DN_ADD_LIT: regs[insn->a] = wrap32((uint64_t)regs[insn->b] + (uint64_t)(int64_t)insn->c); break;
        case DN_RSUB_LIT: regs[insn->a] = wrap32((uint64_t)(int64_t)insn->c - (uint64_t)regs[insn->b]); break;
        case DN_MUL_LIT: regs[insn->a] = wrap32((uint64_t)regs[insn->b] * (uint64_t)(int64_t)insn->c); break;
        case DN_DIV_LIT: regs[insn->a] = div32(regs[insn->b], insn->c, &zero, 0); break;
        case DN_REM_LIT: regs[insn->a] = div32(regs[insn->b], insn->c, &zero, 1); break;
        case DN_AND_LIT: regs[insn->a] = regs[insn->b] & (int64_t)insn->c; break;
        case DN_OR_LIT: regs[insn->a] = regs[insn->b] | (int64_t)insn->c; break;
        case DN_XOR_LIT: regs[insn->a] = regs[insn->b] ^ (int64_t)insn->c; break;
        case DN_SHL_LIT: regs[insn->a] = wrap32((uint64_t)regs[insn->b] << (insn->c & 31)); break;
        case DN_SHR_LIT: regs[insn->a] = shift_right_signed32(regs[insn->b], (uint32_t)(insn->c & 31)); break;
        case DN_USHR_LIT:
            regs[insn->a] = wrap32((uint64_t)((uint32_t)(regs[insn->b] & 0xFFFFFFFF)) >> (insn->c & 31));
            break;

        case DN_NEG_I: regs[insn->a] = wrap32(0 - (uint64_t)regs[insn->b]); break;
        case DN_NOT_I: regs[insn->a] = ~regs[insn->b]; break;
        case DN_NEG_L: regs[insn->a] = (int64_t)(0 - (uint64_t)regs[insn->b]); break;
        case DN_NOT_L: regs[insn->a] = ~regs[insn->b]; break;
        case DN_I2L: regs[insn->a] = regs[insn->b]; break;
        case DN_L2I: regs[insn->a] = wrap32((uint64_t)regs[insn->b]); break;
        case DN_I2B:
            x = regs[insn->b] & 0xFF;
            regs[insn->a] = x >= 0x80 ? x - 0x100 : x;
            break;
        case DN_I2C: regs[insn->a] = regs[insn->b] & 0xFFFF; break;
        case DN_I2S:
            x = regs[insn->b] & 0xFFFF;
            regs[insn->a] = x >= 0x8000 ? x - 0x10000 : x;
            break;
        case DN_CMP_L:
            x = regs[insn->b];
            y = regs[insn->c];
            regs[insn->a] = x < y ? -1 : (x > y ? 1 : 0);
            break;

        case DN_GOTO: taken = 1; break;
        case DN_IF_EQ: taken = regs[insn->a] == regs[insn->b]; break;
        case DN_IF_NE: taken = regs[insn->a] != regs[insn->b]; break;
        case DN_IF_LT: taken = regs[insn->a] < regs[insn->b]; break;
        case DN_IF_GE: taken = regs[insn->a] >= regs[insn->b]; break;
        case DN_IF_GT: taken = regs[insn->a] > regs[insn->b]; break;
        case DN_IF_LE: taken = regs[insn->a] <= regs[insn->b]; break;
        case DN_IF_EQZ: taken = regs[insn->a] == 0; break;
        case DN_IF_NEZ: taken = regs[insn->a] != 0; break;
        case DN_IF_LTZ: taken = regs[insn->a] < 0; break;
        case DN_IF_GEZ: taken = regs[insn->a] >= 0; break;
        case DN_IF_GTZ: taken = regs[insn->a] > 0; break;
        case DN_IF_LEZ: taken = regs[insn->a] <= 0; break;

        case DN_RETURN:
            *result = regs[insn->a];
            *pc = at;
            *back_jumps = jumps;
            return EXTERIA_DEXNATIVE_DONE;
        case DN_RETURN_VOID:
            *result = 0;
            *pc = at;
            *back_jumps = jumps;
            return EXTERIA_DEXNATIVE_DONE;
        default:
            return EXTERIA_DEXNATIVE_BAD_PROGRAM;
        }
        if (zero) {
            *pc = at;
            *back_jumps = jumps;
            return EXTERIA_DEXNATIVE_DIV_ZERO;
        }
        if (taken) {
            next = (uint32_t)insn->c;
            if (next <= at) {
                ++jumps;
                if (max_back_jumps && jumps >= max_back_jumps) {
                    *pc = next;
                    *back_jumps = jumps;
                    return EXTERIA_DEXNATIVE_YIELD;
                }
            }
        }
        at = next;
    }
}
