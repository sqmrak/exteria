#ifndef EXTERIA_DEXNATIVE_H
#define EXTERIA_DEXNATIVE_H

#include <stddef.h>
#include <stdint.h>

/* a small register machine for the dex methods that are pure integer code: int and long arithmetic, comparisons and
   jumps, no objects, no calls, no exceptions other than a division by zero. python/shim/dexvm/native.py turns such a
   method into a program, the interpreter runs it without the cost of a python bytecode per instruction. everything else
   stays on the python path

   a register holds an int sign extended to 64 bits or a long; a wide dex value lives in the low register of its pair,
   as the python translation keeps it, so both paths see the same register numbers. results equal java: int and long
   arithmetic wraps, shift counts are masked, division truncates toward zero, MIN / -1 is MIN */

#define EXTERIA_DEXNATIVE_MAX_REGISTERS 1024u
#define EXTERIA_DEXNATIVE_MAX_INSNS 65536u

typedef enum exteria_dexnative_status {
    EXTERIA_DEXNATIVE_DONE = 0,         /* the method returned, result is set */
    EXTERIA_DEXNATIVE_YIELD = 1,        /* the budget of jumps back ran out: call again with the same state to go on */
    EXTERIA_DEXNATIVE_DIV_ZERO = -1,    /* integer division or remainder by zero */
    EXTERIA_DEXNATIVE_BAD_PROGRAM = -2  /* the program failed validation or left its bounds */
} exteria_dexnative_status;

typedef enum exteria_dexnative_op {
    DN_NOP = 0,
    DN_MOVE,            /* a = b */
    DN_CONST,           /* a = sign extended b (an int) */
    DN_CONST_WIDE,      /* a = (c << 32) | (uint32)b */
    DN_ADD_I, DN_SUB_I, DN_MUL_I, DN_DIV_I, DN_REM_I, DN_AND_I, DN_OR_I, DN_XOR_I, DN_SHL_I, DN_SHR_I, DN_USHR_I,
    DN_ADD_L, DN_SUB_L, DN_MUL_L, DN_DIV_L, DN_REM_L, DN_AND_L, DN_OR_L, DN_XOR_L, DN_SHL_L, DN_SHR_L, DN_USHR_L,
    DN_ADD_LIT, DN_RSUB_LIT, DN_MUL_LIT, DN_DIV_LIT, DN_REM_LIT, DN_AND_LIT, DN_OR_LIT, DN_XOR_LIT,
    DN_SHL_LIT, DN_SHR_LIT, DN_USHR_LIT,    /* a = b op literal c, in int arithmetic */
    DN_NEG_I, DN_NOT_I, DN_NEG_L, DN_NOT_L,
    DN_I2L, DN_L2I, DN_I2B, DN_I2C, DN_I2S,
    DN_CMP_L,           /* a = -1, 0 or 1 by the long values of b and c */
    DN_GOTO,            /* pc = c */
    DN_IF_EQ, DN_IF_NE, DN_IF_LT, DN_IF_GE, DN_IF_GT, DN_IF_LE,        /* if a op b then pc = c */
    DN_IF_EQZ, DN_IF_NEZ, DN_IF_LTZ, DN_IF_GEZ, DN_IF_GTZ, DN_IF_LEZ,  /* if a op 0 then pc = c */
    DN_RETURN,          /* result = a */
    DN_RETURN_VOID,
    DN_OP_COUNT
} exteria_dexnative_op;

/* four words, so a program is a flat array a caller can hold as bytes */
typedef struct exteria_dexnative_insn {
    int32_t op;
    int32_t a;
    int32_t b;
    int32_t c;
} exteria_dexnative_insn;

/* 0 when every opcode is known, every register is below nregs, every jump lands inside the program and the last
   instruction cannot fall off the end. EXTERIA_DEXNATIVE_BAD_PROGRAM otherwise */
int exteria_dexnative_validate(const exteria_dexnative_insn *program, size_t count, uint32_t nregs);

/* runs a validated program. regs holds nregs registers: the arguments on entry, the state between yields. *pc is the
   next instruction (0 at the start). at most max_back_jumps jumps to an earlier or the same instruction are taken
   before it yields, with *pc and regs ready to continue and *back_jumps set to the count taken in this call; max_back_jumps
   of 0 means no limit. *result is written on DONE */
exteria_dexnative_status exteria_dexnative_run(const exteria_dexnative_insn *program, size_t count, int64_t *regs,
                                               uint32_t nregs, uint32_t *pc, uint64_t max_back_jumps,
                                               uint64_t *back_jumps, int64_t *result);

#endif
