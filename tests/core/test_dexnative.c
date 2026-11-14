#include <limits.h>
#include "exteria_dexnative.h"
#include "test_util.h"

#define I(op, a, b, c) { (op), (a), (b), (c) }

static exteria_dexnative_status run_all(const exteria_dexnative_insn *program, size_t count, int64_t *regs, uint32_t nregs,
                                        int64_t *result) {
    uint32_t pc = 0;
    uint64_t jumps = 0;
    return exteria_dexnative_run(program, count, regs, nregs, &pc, 0, &jumps, result);
}

static int64_t one(int op, int64_t x, int64_t y, exteria_dexnative_status *status) {
    exteria_dexnative_insn program[] = { I(op, 2, 0, 1), I(DN_RETURN, 2, 0, 0) };
    int64_t regs[3] = { x, y, 0 };
    int64_t result = -12345;
    *status = run_all(program, 2, regs, 3, &result);
    return result;
}

static int64_t lit(int op, int64_t x, int32_t literal) {
    exteria_dexnative_insn program[] = { I(op, 1, 0, literal), I(DN_RETURN, 1, 0, 0) };
    int64_t regs[2] = { x, 0 };
    int64_t result = -12345;
    CHECK_EQ_INT(run_all(program, 2, regs, 2, &result), EXTERIA_DEXNATIVE_DONE);
    return result;
}

static int64_t unary(int op, int64_t x) {
    exteria_dexnative_insn program[] = { I(op, 1, 0, 0), I(DN_RETURN, 1, 0, 0) };
    int64_t regs[2] = { x, 0 };
    int64_t result = -12345;
    CHECK_EQ_INT(run_all(program, 2, regs, 2, &result), EXTERIA_DEXNATIVE_DONE);
    return result;
}

static void test_int_arithmetic_wraps_like_java(void) {
    exteria_dexnative_status st;
    CHECK_EQ_INT(one(DN_ADD_I, INT_MAX, 1, &st), INT_MIN);
    CHECK_EQ_INT(one(DN_SUB_I, INT_MIN, 1, &st), INT_MAX);
    CHECK_EQ_INT(one(DN_MUL_I, 65536, 65536, &st), 0);
    CHECK_EQ_INT(one(DN_MUL_I, INT_MIN, -1, &st), INT_MIN);
    CHECK_EQ_INT(one(DN_DIV_I, INT_MIN, -1, &st), INT_MIN);
    CHECK_EQ_INT(one(DN_REM_I, INT_MIN, -1, &st), 0);
    CHECK_EQ_INT(one(DN_DIV_I, -7, 2, &st), -3);
    CHECK_EQ_INT(one(DN_REM_I, -7, 2, &st), -1);
    CHECK_EQ_INT(one(DN_REM_I, 7, -2, &st), 1);
    CHECK_EQ_INT(one(DN_SHL_I, 1, 31, &st), INT_MIN);
    CHECK_EQ_INT(one(DN_SHL_I, 1, 33, &st), 2);
    CHECK_EQ_INT(one(DN_SHL_I, 3, -1, &st), INT_MIN);
    CHECK_EQ_INT(one(DN_SHR_I, -8, 1, &st), -4);
    CHECK_EQ_INT(one(DN_SHR_I, -1, 31, &st), -1);
    CHECK_EQ_INT(one(DN_SHR_I, INT_MIN, 31, &st), -1);
    CHECK_EQ_INT(one(DN_USHR_I, -1, 28, &st), 15);
    CHECK_EQ_INT(one(DN_USHR_I, -1, 0, &st), -1);
    CHECK_EQ_INT(one(DN_USHR_I, INT_MIN, 31, &st), 1);
    CHECK_EQ_INT(one(DN_AND_I, -1, 0x0F0F, &st), 0x0F0F);
    CHECK_EQ_INT(one(DN_OR_I, 0x10, -16, &st), -16);
    CHECK_EQ_INT(one(DN_XOR_I, -1, 5, &st), -6);
}

static void test_long_arithmetic_wraps_like_java(void) {
    exteria_dexnative_status st;
    CHECK_EQ_INT(one(DN_ADD_L, INT64_MAX, 1, &st), INT64_MIN);
    CHECK_EQ_INT(one(DN_SUB_L, INT64_MIN, 1, &st), INT64_MAX);
    CHECK_EQ_INT(one(DN_MUL_L, INT64_MIN, -1, &st), INT64_MIN);
    CHECK_EQ_INT(one(DN_MUL_L, 4294967296LL, 4294967296LL, &st), 0);
    CHECK_EQ_INT(one(DN_DIV_L, INT64_MIN, -1, &st), INT64_MIN);
    CHECK_EQ_INT(one(DN_REM_L, INT64_MIN, -1, &st), 0);
    CHECK_EQ_INT(one(DN_DIV_L, -9, 4, &st), -2);
    CHECK_EQ_INT(one(DN_REM_L, -9, 4, &st), -1);
    CHECK_EQ_INT(one(DN_SHL_L, 1, 63, &st), INT64_MIN);
    CHECK_EQ_INT(one(DN_SHL_L, 1, 65, &st), 2);
    CHECK_EQ_INT(one(DN_SHR_L, -16, 2, &st), -4);
    CHECK_EQ_INT(one(DN_SHR_L, INT64_MIN, 63, &st), -1);
    CHECK_EQ_INT(one(DN_USHR_L, -1, 60, &st), 15);
    CHECK_EQ_INT(one(DN_USHR_L, -1, 0, &st), -1);
    CHECK_EQ_INT(one(DN_CMP_L, 5, 9, &st), -1);
    CHECK_EQ_INT(one(DN_CMP_L, 9, 9, &st), 0);
    CHECK_EQ_INT(one(DN_CMP_L, INT64_MIN, INT64_MAX, &st), -1);
    CHECK_EQ_INT(one(DN_CMP_L, INT64_MAX, INT64_MIN, &st), 1);
}

static void test_division_by_zero_is_reported_not_trapped(void) {
    exteria_dexnative_status st;
    one(DN_DIV_I, 1, 0, &st);
    CHECK_EQ_INT(st, EXTERIA_DEXNATIVE_DIV_ZERO);
    one(DN_REM_I, 1, 0, &st);
    CHECK_EQ_INT(st, EXTERIA_DEXNATIVE_DIV_ZERO);
    one(DN_DIV_L, 1, 0, &st);
    CHECK_EQ_INT(st, EXTERIA_DEXNATIVE_DIV_ZERO);
    one(DN_REM_L, INT64_MIN, 0, &st);
    CHECK_EQ_INT(st, EXTERIA_DEXNATIVE_DIV_ZERO);
    exteria_dexnative_insn program[] = { I(DN_DIV_LIT, 1, 0, 0), I(DN_RETURN, 1, 0, 0) };
    int64_t regs[2] = { 7, 0 };
    int64_t result = 0;
    CHECK_EQ_INT(run_all(program, 2, regs, 2, &result), EXTERIA_DEXNATIVE_DIV_ZERO);
}

static void test_literal_forms(void) {
    CHECK_EQ_INT(lit(DN_ADD_LIT, INT_MAX, 1), INT_MIN);
    CHECK_EQ_INT(lit(DN_RSUB_LIT, 10, 3), -7);
    CHECK_EQ_INT(lit(DN_RSUB_LIT, INT_MIN, 0), INT_MIN);
    CHECK_EQ_INT(lit(DN_MUL_LIT, 100000, 100000), 1410065408);
    CHECK_EQ_INT(lit(DN_DIV_LIT, -7, 2), -3);
    CHECK_EQ_INT(lit(DN_DIV_LIT, INT_MIN, -1), INT_MIN);
    CHECK_EQ_INT(lit(DN_REM_LIT, -7, 3), -1);
    CHECK_EQ_INT(lit(DN_AND_LIT, 0x1234, 0xFF), 0x34);
    CHECK_EQ_INT(lit(DN_OR_LIT, 1, 6), 7);
    CHECK_EQ_INT(lit(DN_XOR_LIT, 5, -1), -6);
    CHECK_EQ_INT(lit(DN_SHL_LIT, 1, 35), 8);
    CHECK_EQ_INT(lit(DN_SHR_LIT, -64, 3), -8);
    CHECK_EQ_INT(lit(DN_USHR_LIT, -1, 4), 0x0FFFFFFF);
    CHECK_EQ_INT(lit(DN_USHR_LIT, -5, 0), -5);
}

static void test_unary_and_conversions(void) {
    CHECK_EQ_INT(unary(DN_NEG_I, INT_MIN), INT_MIN);
    CHECK_EQ_INT(unary(DN_NEG_I, 5), -5);
    CHECK_EQ_INT(unary(DN_NOT_I, 0), -1);
    CHECK_EQ_INT(unary(DN_NEG_L, INT64_MIN), INT64_MIN);
    CHECK_EQ_INT(unary(DN_NOT_L, INT64_MAX), INT64_MIN);
    CHECK_EQ_INT(unary(DN_I2L, -3), -3);
    CHECK_EQ_INT(unary(DN_L2I, 0x1FFFFFFFFLL), -1);
    CHECK_EQ_INT(unary(DN_L2I, 0x80000000LL), INT_MIN);
    CHECK_EQ_INT(unary(DN_L2I, 0x7FFFFFFFLL), INT_MAX);
    CHECK_EQ_INT(unary(DN_I2B, 0x80), -128);
    CHECK_EQ_INT(unary(DN_I2B, 0x17F), 127);
    CHECK_EQ_INT(unary(DN_I2B, -129), 127);
    CHECK_EQ_INT(unary(DN_I2C, -1), 65535);
    CHECK_EQ_INT(unary(DN_I2C, 0x12345), 0x2345);
    CHECK_EQ_INT(unary(DN_I2S, 0x8000), -32768);
    CHECK_EQ_INT(unary(DN_I2S, 65535), -1);
    CHECK_EQ_INT(unary(DN_I2S, 32767), 32767);
}

static void test_constants_and_moves(void) {
    exteria_dexnative_insn program[] = {
        I(DN_CONST, 0, -5, 0),
        I(DN_CONST_WIDE, 1, (int32_t)0x89ABCDEFu, (int32_t)0x01234567),
        I(DN_MOVE, 3, 1, 0),
        I(DN_RETURN, 3, 0, 0),
    };
    int64_t regs[4] = { 0, 0, 0, 0 };
    int64_t result = 0;
    CHECK_EQ_INT(run_all(program, 4, regs, 4, &result), EXTERIA_DEXNATIVE_DONE);
    CHECK_EQ_INT(regs[0], -5);
    CHECK_EQ_INT(result, 0x0123456789ABCDEFLL);
    exteria_dexnative_insn nothing[] = { I(DN_NOP, 0, 0, 0), I(DN_RETURN_VOID, 0, 0, 0) };
    result = 99;
    CHECK_EQ_INT(run_all(nothing, 2, regs, 1, &result), EXTERIA_DEXNATIVE_DONE);
    CHECK_EQ_INT(result, 0);
}

/* sum = 0; for (i = 0; i < n; i++) sum += i; return sum */
static const exteria_dexnative_insn SUM[] = {
    I(DN_CONST, 1, 0, 0),           /* 0: sum */
    I(DN_CONST, 2, 0, 0),           /* 1: i */
    I(DN_IF_GE, 2, 0, 6),           /* 2: if i >= n goto 6 */
    I(DN_ADD_I, 1, 1, 2),           /* 3: sum += i */
    I(DN_ADD_LIT, 2, 2, 1),         /* 4: i++ */
    I(DN_GOTO, 0, 0, 2),            /* 5: loop */
    I(DN_RETURN, 1, 0, 0),          /* 6 */
};

static void test_loop_and_branches(void) {
    int64_t regs[3] = { 100, 0, 0 };
    int64_t result = 0;
    CHECK_EQ_INT(run_all(SUM, 7, regs, 3, &result), EXTERIA_DEXNATIVE_DONE);
    CHECK_EQ_INT(result, 4950);
    regs[0] = 0; regs[1] = 0; regs[2] = 0;
    CHECK_EQ_INT(run_all(SUM, 7, regs, 3, &result), EXTERIA_DEXNATIVE_DONE);
    CHECK_EQ_INT(result, 0);
    regs[0] = 100000; regs[1] = 0; regs[2] = 0;
    CHECK_EQ_INT(run_all(SUM, 7, regs, 3, &result), EXTERIA_DEXNATIVE_DONE);
    CHECK_EQ_INT(result, (int32_t)(100000LL * 99999LL / 2));     /* the java sum wraps to an int */
}

static void test_every_comparison(void) {
    static const struct { int op; int64_t a, b; int taken; } cases[] = {
        { DN_IF_EQ, 3, 3, 1 }, { DN_IF_EQ, 3, 4, 0 }, { DN_IF_NE, 3, 4, 1 }, { DN_IF_NE, 3, 3, 0 },
        { DN_IF_LT, -1, 0, 1 }, { DN_IF_LT, 0, 0, 0 }, { DN_IF_GE, 0, 0, 1 }, { DN_IF_GE, -1, 0, 0 },
        { DN_IF_GT, 1, 0, 1 }, { DN_IF_GT, 0, 0, 0 }, { DN_IF_LE, 0, 0, 1 }, { DN_IF_LE, 1, 0, 0 },
        { DN_IF_EQZ, 0, 0, 1 }, { DN_IF_EQZ, 5, 0, 0 }, { DN_IF_NEZ, 5, 0, 1 }, { DN_IF_NEZ, 0, 0, 0 },
        { DN_IF_LTZ, -5, 0, 1 }, { DN_IF_LTZ, 0, 0, 0 }, { DN_IF_GEZ, 0, 0, 1 }, { DN_IF_GEZ, -1, 0, 0 },
        { DN_IF_GTZ, 5, 0, 1 }, { DN_IF_GTZ, 0, 0, 0 }, { DN_IF_LEZ, 0, 0, 1 }, { DN_IF_LEZ, 1, 0, 0 },
        { DN_IF_LT, INT64_MIN, INT64_MAX, 1 }, { DN_IF_GT, INT64_MIN, INT64_MAX, 0 },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; ++i) {
        exteria_dexnative_insn program[] = {
            I(cases[i].op, 0, 1, 3), I(DN_CONST, 2, 0, 0), I(DN_RETURN, 2, 0, 0), I(DN_CONST, 2, 1, 0), I(DN_RETURN, 2, 0, 0),
        };
        int64_t regs[3] = { cases[i].a, cases[i].b, 7 };
        int64_t result = -1;
        CHECK_EQ_INT(run_all(program, 5, regs, 3, &result), EXTERIA_DEXNATIVE_DONE);
        CHECK_EQ_INT(result, cases[i].taken);
    }
}

static void test_yield_and_resume_give_the_same_result(void) {
    for (uint64_t quantum = 1; quantum <= 40; quantum += 3) {
        int64_t regs[3] = { 500, 0, 0 };
        uint32_t pc = 0;
        uint64_t total = 0, jumps = 0;
        int64_t result = 0;
        exteria_dexnative_status st;
        int rounds = 0;
        while ((st = exteria_dexnative_run(SUM, 7, regs, 3, &pc, quantum, &jumps, &result)) == EXTERIA_DEXNATIVE_YIELD) {
            CHECK_EQ_INT(jumps, quantum);
            total += jumps;
            CHECK(++rounds < 100000);
        }
        total += jumps;
        CHECK_EQ_INT(st, EXTERIA_DEXNATIVE_DONE);
        CHECK_EQ_INT(result, 124750);
        CHECK_EQ_INT(total, 500);
    }
}

static void test_an_endless_loop_yields_every_quantum(void) {
    static const exteria_dexnative_insn spin[] = { I(DN_ADD_LIT, 0, 0, 1), I(DN_GOTO, 0, 0, 0) };
    int64_t regs[1] = { 0 };
    uint32_t pc = 0;
    uint64_t jumps = 0;
    int64_t result = 0;
    for (int round = 1; round <= 5; ++round) {
        CHECK_EQ_INT(exteria_dexnative_run(spin, 2, regs, 1, &pc, 1000, &jumps, &result), EXTERIA_DEXNATIVE_YIELD);
        CHECK_EQ_INT(jumps, 1000);
        CHECK_EQ_INT(regs[0], round * 1000);
    }
}

static void test_a_jump_to_itself_counts_as_a_back_jump(void) {
    static const exteria_dexnative_insn self[] = { I(DN_GOTO, 0, 0, 0) };
    int64_t regs[1] = { 0 };
    uint32_t pc = 0;
    uint64_t jumps = 0;
    int64_t result = 0;
    CHECK_EQ_INT(exteria_dexnative_run(self, 1, regs, 1, &pc, 7, &jumps, &result), EXTERIA_DEXNATIVE_YIELD);
    CHECK_EQ_INT(jumps, 7);
    CHECK_EQ_INT(pc, 0);
}

static void test_validation_rejects_every_malformed_program(void) {
    exteria_dexnative_insn ok[] = { I(DN_CONST, 0, 1, 0), I(DN_RETURN, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(ok, 2, 1), 0);
    CHECK_EQ_INT(exteria_dexnative_validate(NULL, 2, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    CHECK_EQ_INT(exteria_dexnative_validate(ok, 0, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    CHECK_EQ_INT(exteria_dexnative_validate(ok, 2, 0), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    CHECK_EQ_INT(exteria_dexnative_validate(ok, 2, EXTERIA_DEXNATIVE_MAX_REGISTERS + 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    CHECK_EQ_INT(exteria_dexnative_validate(ok, EXTERIA_DEXNATIVE_MAX_INSNS + 1, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);

    exteria_dexnative_insn bad_op[] = { I(DN_OP_COUNT, 0, 0, 0), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(bad_op, 2, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn negative_op[] = { I(-1, 0, 0, 0), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(negative_op, 2, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn bad_a[] = { I(DN_CONST, 1, 0, 0), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(bad_a, 2, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn bad_b[] = { I(DN_MOVE, 0, 5, 0), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(bad_b, 2, 2), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn bad_c[] = { I(DN_ADD_I, 0, 0, -1), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(bad_c, 2, 2), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn literal_is_not_a_register[] = { I(DN_ADD_LIT, 0, 0, 100000), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(literal_is_not_a_register, 2, 2), 0);
    exteria_dexnative_insn jump_out[] = { I(DN_GOTO, 0, 0, 2), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(jump_out, 2, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn jump_negative[] = { I(DN_IF_EQZ, 0, 0, -1), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(jump_negative, 2, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn falls_off[] = { I(DN_CONST, 0, 1, 0), I(DN_ADD_LIT, 0, 0, 1) };
    CHECK_EQ_INT(exteria_dexnative_validate(falls_off, 2, 1), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    exteria_dexnative_insn cmp_bad[] = { I(DN_CMP_L, 0, 1, 2), I(DN_RETURN_VOID, 0, 0, 0) };
    CHECK_EQ_INT(exteria_dexnative_validate(cmp_bad, 2, 2), EXTERIA_DEXNATIVE_BAD_PROGRAM);
}

static void test_run_refuses_what_validation_refuses(void) {
    exteria_dexnative_insn bad[] = { I(DN_CONST, 9, 0, 0), I(DN_RETURN_VOID, 0, 0, 0) };
    int64_t regs[1] = { 0 };
    uint32_t pc = 0;
    uint64_t jumps = 0;
    int64_t result = 0;
    CHECK_EQ_INT(exteria_dexnative_run(bad, 2, regs, 1, &pc, 0, &jumps, &result), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    pc = 5;
    CHECK_EQ_INT(exteria_dexnative_run(SUM, 7, regs, 1, &pc, 0, &jumps, &result), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    pc = 0;
    CHECK_EQ_INT(exteria_dexnative_run(SUM, 7, NULL, 3, &pc, 0, &jumps, &result), EXTERIA_DEXNATIVE_BAD_PROGRAM);
    CHECK_EQ_INT(exteria_dexnative_run(SUM, 7, regs, 3, &pc, 0, &jumps, NULL), EXTERIA_DEXNATIVE_BAD_PROGRAM);
}

int main(void) {
    test_int_arithmetic_wraps_like_java();
    test_long_arithmetic_wraps_like_java();
    test_division_by_zero_is_reported_not_trapped();
    test_literal_forms();
    test_unary_and_conversions();
    test_constants_and_moves();
    test_loop_and_branches();
    test_every_comparison();
    test_yield_and_resume_give_the_same_result();
    test_an_endless_loop_yields_every_quantum();
    test_a_jump_to_itself_counts_as_a_back_jump();
    test_validation_rejects_every_malformed_program();
    test_run_refuses_what_validation_refuses();
    if (g_failures) {
        fprintf(stderr, "dexnative: %d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("dexnative: %d checks ok\n", g_checks);
    return 0;
}
