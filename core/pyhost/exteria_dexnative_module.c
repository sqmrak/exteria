#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdlib.h>
#include <string.h>
#include "exteria_dexnative.h"
#include "exteria_dexnative_module.h"

/* jumps back taken between two looks at the interpreter: a few milliseconds of work, so a budget, a signal or the
   watchdog of exteria_pyhost reaches a loop that never ends */
#define DEFAULT_QUANTUM 65536ull

typedef struct {
    PyObject_HEAD
    exteria_dexnative_insn *program;
    size_t count;
    uint32_t nregs;
    uint32_t *arg_registers;
    size_t nargs;
} ProgramObject;

static void program_dealloc(ProgramObject *self) {
    free(self->program);
    free(self->arg_registers);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

/* program: count * 16 bytes of int32 op, a, b, c in native order. arg_registers: the register of each argument */
static PyObject *program_new(PyTypeObject *type, PyObject *args, PyObject *kwargs) {
    static char *keywords[] = { "program", "nregs", "arg_registers", NULL };
    Py_buffer buffer;
    unsigned long nregs;
    PyObject *arg_list;
    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "y*kO", keywords, &buffer, &nregs, &arg_list)) return NULL;
    PyObject *result = NULL;
    ProgramObject *self = NULL;
    PyObject *sequence = PySequence_Fast(arg_list, "arg_registers must be a sequence");
    if (!sequence) goto done;
    if (buffer.len == 0 || buffer.len % (Py_ssize_t)sizeof(exteria_dexnative_insn) != 0) {
        PyErr_SetString(PyExc_ValueError, "program is not a whole number of instructions");
        goto done;
    }
    size_t count = (size_t)buffer.len / sizeof(exteria_dexnative_insn);
    if (nregs == 0 || nregs > EXTERIA_DEXNATIVE_MAX_REGISTERS || count > EXTERIA_DEXNATIVE_MAX_INSNS) {
        PyErr_SetString(PyExc_ValueError, "program is larger than the machine allows");
        goto done;
    }
    Py_ssize_t nargs = PySequence_Fast_GET_SIZE(sequence);
    if (nargs < 0 || (size_t)nargs > nregs) {
        PyErr_SetString(PyExc_ValueError, "more arguments than registers");
        goto done;
    }
    self = (ProgramObject *)type->tp_alloc(type, 0);
    if (!self) goto done;
    self->program = malloc(count * sizeof(exteria_dexnative_insn));
    self->arg_registers = malloc((size_t)(nargs ? nargs : 1) * sizeof(uint32_t));
    if (!self->program || !self->arg_registers) {
        PyErr_NoMemory();
        goto done;
    }
    memcpy(self->program, buffer.buf, count * sizeof(exteria_dexnative_insn));
    self->count = count;
    self->nregs = (uint32_t)nregs;
    self->nargs = (size_t)nargs;
    if (exteria_dexnative_validate(self->program, count, self->nregs) != 0) {
        PyErr_SetString(PyExc_ValueError, "program failed validation");
        goto done;
    }
    for (Py_ssize_t i = 0; i < nargs; ++i) {
        long reg = PyLong_AsLong(PySequence_Fast_GET_ITEM(sequence, i));
        if (reg == -1 && PyErr_Occurred()) goto done;
        if (reg < 0 || (unsigned long)reg >= nregs) {
            PyErr_SetString(PyExc_ValueError, "argument register out of range");
            goto done;
        }
        self->arg_registers[i] = (uint32_t)reg;
    }
    result = (PyObject *)self;
    self = NULL;
done:
    Py_XDECREF(self);
    Py_XDECREF(sequence);
    PyBuffer_Release(&buffer);
    return result;
}

/* call(args, tick=None, quantum=65536) -> int. args are register values (python ints that fit 64 bits). tick, when given,
   is called with the number of jumps back taken since its last call, between quanta, with the interpreter lock held */
static PyObject *program_call(ProgramObject *self, PyObject *args, PyObject *kwargs) {
    static char *keywords[] = { "args", "tick", "quantum", NULL };
    PyObject *values;
    PyObject *tick = Py_None;
    unsigned long long quantum = DEFAULT_QUANTUM;
    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O!|OK", keywords, &PyTuple_Type, &values, &tick, &quantum)) return NULL;
    if ((size_t)PyTuple_GET_SIZE(values) != self->nargs) {
        PyErr_Format(PyExc_TypeError, "expected %zu arguments, got %zd", self->nargs, PyTuple_GET_SIZE(values));
        return NULL;
    }
    if (tick != Py_None && !PyCallable_Check(tick)) {
        PyErr_SetString(PyExc_TypeError, "tick must be callable");
        return NULL;
    }
    if (quantum == 0) {
        PyErr_SetString(PyExc_ValueError, "quantum must be positive");
        return NULL;
    }
    int64_t regs[EXTERIA_DEXNATIVE_MAX_REGISTERS];
    memset(regs, 0, (size_t)self->nregs * sizeof(int64_t));
    for (size_t i = 0; i < self->nargs; ++i) {
        long long value = PyLong_AsLongLong(PyTuple_GET_ITEM(values, (Py_ssize_t)i));
        if (value == -1 && PyErr_Occurred()) return NULL;
        regs[self->arg_registers[i]] = value;
    }
    uint32_t pc = 0;
    for (;;) {
        uint64_t jumps = 0;
        int64_t result = 0;
        exteria_dexnative_status status;
        Py_BEGIN_ALLOW_THREADS
        status = exteria_dexnative_run(self->program, self->count, regs, self->nregs, &pc, quantum, &jumps, &result);
        Py_END_ALLOW_THREADS
        if (status == EXTERIA_DEXNATIVE_DONE) return PyLong_FromLongLong(result);
        if (status == EXTERIA_DEXNATIVE_DIV_ZERO) {
            PyErr_SetString(PyExc_ZeroDivisionError, "integer division or modulo by zero");
            return NULL;
        }
        if (status != EXTERIA_DEXNATIVE_YIELD) {
            PyErr_SetString(PyExc_SystemError, "the native program left its bounds");
            return NULL;
        }
        if (tick != Py_None) {
            PyObject *answer = PyObject_CallFunction(tick, "K", (unsigned long long)jumps);
            if (!answer) return NULL;
            Py_DECREF(answer);
        } else if (PyErr_CheckSignals() < 0) {
            return NULL;
        }
    }
}

static PyObject *program_get_length(ProgramObject *self, void *closure) {
    (void)closure;
    return PyLong_FromSize_t(self->count);
}

static PyMethodDef program_methods[] = {
    { "call", (PyCFunction)(void (*)(void))program_call, METH_VARARGS | METH_KEYWORDS,
      "call(args, tick=None, quantum=65536) -> int, runs the program" },
    { NULL, NULL, 0, NULL }
};

static PyGetSetDef program_getset[] = {
    { "length", (getter)program_get_length, NULL, "number of instructions", NULL },
    { NULL, NULL, NULL, NULL, NULL }
};

static PyTypeObject ProgramType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "_exteria_dexnative.Program",
    .tp_basicsize = sizeof(ProgramObject),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "a validated program of the integer register machine",
    .tp_new = program_new,
    .tp_dealloc = (destructor)program_dealloc,
    .tp_methods = program_methods,
    .tp_getset = program_getset,
};

static struct PyModuleDef dexnative_module = {
    PyModuleDef_HEAD_INIT, "_exteria_dexnative", "the integer register machine of the dex runtime", -1, NULL,
    NULL, NULL, NULL, NULL
};

PyMODINIT_FUNC PyInit__exteria_dexnative(void);

PyMODINIT_FUNC PyInit__exteria_dexnative(void) {
    if (PyType_Ready(&ProgramType) < 0) return NULL;
    PyObject *module = PyModule_Create(&dexnative_module);
    if (!module) return NULL;
    Py_INCREF(&ProgramType);
    if (PyModule_AddObject(module, "Program", (PyObject *)&ProgramType) < 0 ||
        PyModule_AddIntConstant(module, "MAX_REGISTERS", (long)EXTERIA_DEXNATIVE_MAX_REGISTERS) < 0 ||
        PyModule_AddIntConstant(module, "MAX_INSNS", (long)EXTERIA_DEXNATIVE_MAX_INSNS) < 0) {
        Py_DECREF(&ProgramType);
        Py_DECREF(module);
        return NULL;
    }
    return module;
}

void *exteria_dexnative_module_init(void) {
    return (void *)PyInit__exteria_dexnative();
}
