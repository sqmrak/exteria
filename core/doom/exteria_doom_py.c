#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "exteria_doom.h"
#include "exteria_surface.h"

/* the python face of the engine: the module _doom, built into the app and listed in the config of core/pyhost */

static PyObject *doom_start(PyObject *self, PyObject *args) {
    const char *wad, *savedir;
    (void)self;
    if (!PyArg_ParseTuple(args, "ss", &wad, &savedir)) return NULL;
    exteria_status status = exteria_doom_start(wad, savedir);
    if (status != EXTERIA_OK) {
        const char *text = exteria_doom_error();
        PyErr_SetString(status == EXTERIA_E_IO ? PyExc_FileNotFoundError : PyExc_RuntimeError, text[0] ? text : "doom did not start");
        return NULL;
    }
    Py_RETURN_NONE;
}

static PyObject *doom_tick(PyObject *self, PyObject *args) {
    (void)self;
    (void)args;
    return PyBool_FromLong(exteria_doom_tick() == EXTERIA_OK);
}

static PyObject *doom_key(PyObject *self, PyObject *args) {
    int code, pressed;
    (void)self;
    if (!PyArg_ParseTuple(args, "ip", &code, &pressed)) return NULL;
    return PyBool_FromLong(exteria_doom_key(code, pressed));
}

static PyObject *doom_error(PyObject *self, PyObject *args) {
    (void)self;
    (void)args;
    return PyUnicode_FromString(exteria_doom_error());
}

static PyMethodDef doom_methods[] = {
    { "start", doom_start, METH_VARARGS, "start(wad_path, savedir): loads the game" },
    { "tick", doom_tick, METH_NOARGS, "tick() -> bool: runs to the next frame, False when the game has ended" },
    { "key", doom_key, METH_VARARGS, "key(code, pressed): a key of doomkeys.h goes down or up" },
    { "error", doom_error, METH_NOARGS, "error() -> str: why the engine stopped" },
    { NULL, NULL, 0, NULL }
};

static struct PyModuleDef doom_module = {
    PyModuleDef_HEAD_INIT, "_doom", "doom on doomgeneric, shown through the surface named doom", -1, doom_methods, NULL, NULL, NULL, NULL
};

void *exteria_doom_module_init(void) {
    exteria_surface_ops ops = { exteria_doom_frame, exteria_doom_running, exteria_doom_key };
    exteria_surface_register_ops("doom", &ops);
    PyObject *module = PyModule_Create(&doom_module);
    if (module && (PyModule_AddIntConstant(module, "WIDTH", EXTERIA_DOOM_WIDTH) < 0 || PyModule_AddIntConstant(module, "HEIGHT", EXTERIA_DOOM_HEIGHT) < 0)) {
        Py_DECREF(module);
        return NULL;
    }
    return (void *)module;
}
