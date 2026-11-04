#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include "exteria_pyhost.h"

#define ERROR_MAX 2048

static exteria_pyhost_config g_cfg;
static char g_error[ERROR_MAX];
static int g_running;

/* one watchdog thread serves every call: python loops are stopped by an async exception, which only lands between bytecodes */
static pthread_mutex_t g_wd_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_wd_cond = PTHREAD_COND_INITIALIZER;
static pthread_t g_wd_thread;
static int g_wd_started;
static int g_wd_quit;
static int g_wd_armed;
static unsigned long g_wd_target;
static struct timespec g_wd_deadline;
static unsigned long g_wd_generation;

static void set_error(const char *text) {
    snprintf(g_error, sizeof g_error, "%s", text);
}

static exteria_status status_of_service_error(exteria_status status) {
    return status < 0 ? status : EXTERIA_E_STATE;
}

static PyObject *exteria_service(PyObject *self, PyObject *args) {
    const char *name;
    const char *payload;
    Py_ssize_t payload_len;
    (void)self;
    if (!PyArg_ParseTuple(args, "ss#", &name, &payload, &payload_len)) return NULL;
    if (!g_cfg.service) {
        PyErr_SetString(PyExc_RuntimeError, "no services are attached");
        return NULL;
    }
    char *reply = malloc(EXTERIA_PYHOST_REPLY_MAX + 1);
    if (!reply) return PyErr_NoMemory();
    size_t reply_len = 0;
    exteria_status status = g_cfg.service(g_cfg.service_ctx, name, payload, (size_t)payload_len, reply,
                                          EXTERIA_PYHOST_REPLY_MAX, &reply_len);
    if (reply_len > EXTERIA_PYHOST_REPLY_MAX) reply_len = EXTERIA_PYHOST_REPLY_MAX;
    reply[reply_len] = 0;
    PyObject *result = NULL;
    if (status == EXTERIA_OK) {
        result = PyUnicode_DecodeUTF8(reply, (Py_ssize_t)reply_len, "replace");
    } else {
        PyObject *exc = PyExc_RuntimeError;
        if (status == EXTERIA_E_SECURITY) exc = PyExc_PermissionError;
        else if (status == EXTERIA_E_NOTFOUND) exc = PyExc_LookupError;
        else if (status == EXTERIA_E_ARG) exc = PyExc_ValueError;
        else if (status == EXTERIA_E_UNSUPPORTED) exc = PyExc_NotImplementedError;
        PyErr_Format(exc, "%s: %s", name, reply_len ? reply : exteria_status_name(status_of_service_error(status)));
    }
    free(reply);
    return result;
}

static PyMethodDef exteria_methods[] = {
    { "service", exteria_service, METH_VARARGS, "service(name, json) -> json, asks the app" },
    { NULL, NULL, 0, NULL }
};

static struct PyModuleDef exteria_module = {
    PyModuleDef_HEAD_INIT, "_exteria", "the services the app gives to plugins", -1, exteria_methods,
    NULL, NULL, NULL, NULL
};

static PyObject *exteria_module_init(void) {
    return PyModule_Create(&exteria_module);
}

static void *watchdog_main(void *arg) {
    (void)arg;
    pthread_mutex_lock(&g_wd_lock);
    while (!g_wd_quit) {
        if (!g_wd_armed) {
            pthread_cond_wait(&g_wd_cond, &g_wd_lock);
            continue;
        }
        unsigned long generation = g_wd_generation;
        struct timespec deadline = g_wd_deadline;
        int rc = pthread_cond_timedwait(&g_wd_cond, &g_wd_lock, &deadline);
        if (rc == ETIMEDOUT && g_wd_armed && generation == g_wd_generation) {
            unsigned long target = g_wd_target;
            g_wd_armed = 0;
            pthread_mutex_unlock(&g_wd_lock);
            PyGILState_STATE gil = PyGILState_Ensure();
            PyThreadState_SetAsyncExc(target, PyExc_TimeoutError);
            PyGILState_Release(gil);
            pthread_mutex_lock(&g_wd_lock);
        }
    }
    pthread_mutex_unlock(&g_wd_lock);
    return NULL;
}

static void watchdog_arm(uint32_t timeout_ms) {
    /* clock_gettime is absent before ios 10 */
    struct timeval now;
    gettimeofday(&now, NULL);
    pthread_mutex_lock(&g_wd_lock);
    g_wd_deadline.tv_sec = now.tv_sec + (time_t)(timeout_ms / 1000u);
    g_wd_deadline.tv_nsec = (long)now.tv_usec * 1000L + (long)(timeout_ms % 1000u) * 1000000L;
    if (g_wd_deadline.tv_nsec >= 1000000000L) {
        g_wd_deadline.tv_sec += 1;
        g_wd_deadline.tv_nsec -= 1000000000L;
    }
    g_wd_target = PyThread_get_thread_ident();
    g_wd_generation++;
    g_wd_armed = 1;
    pthread_cond_signal(&g_wd_cond);
    pthread_mutex_unlock(&g_wd_lock);
}

static void watchdog_disarm(void) {
    pthread_mutex_lock(&g_wd_lock);
    g_wd_armed = 0;
    g_wd_generation++;
    unsigned long target = g_wd_target;
    pthread_mutex_unlock(&g_wd_lock);
    /* an exception posted just before the call returned must not land in the next python code that runs */
    PyThreadState_SetAsyncExc(target, NULL);
}

/* writes the traceback of the pending exception to g_error and returns the status that names its class */
static exteria_status take_exception(void) {
    PyObject *type, *value, *tb;
    PyErr_Fetch(&type, &value, &tb);
    PyErr_NormalizeException(&type, &value, &tb);
    exteria_status status = EXTERIA_E_STATE;
    if (type && PyErr_GivenExceptionMatches(type, PyExc_TimeoutError)) status = EXTERIA_E_TIMEOUT;
    else if (type && PyErr_GivenExceptionMatches(type, PyExc_PermissionError)) status = EXTERIA_E_SECURITY;
    else if (type && PyErr_GivenExceptionMatches(type, PyExc_MemoryError)) status = EXTERIA_E_NOMEM;
    g_error[0] = 0;
    PyObject *traceback = PyImport_ImportModule("traceback");
    PyObject *lines = NULL;
    if (traceback) {
        lines = PyObject_CallMethod(traceback, "format_exception", "OOO", type ? type : Py_None,
                                    value ? value : Py_None, tb ? tb : Py_None);
    }
    if (lines) {
        PyObject *empty = PyUnicode_FromString("");
        PyObject *text = empty ? PyUnicode_Join(empty, lines) : NULL;
        Py_XDECREF(empty);
        if (text) {
            Py_ssize_t n = 0;
            const char *utf8 = PyUnicode_AsUTF8AndSize(text, &n);
            if (utf8) {
                /* the end of a traceback names the failure, keep that part when it does not fit */
                size_t keep = (size_t)n < sizeof g_error - 1 ? (size_t)n : sizeof g_error - 1;
                memcpy(g_error, utf8 + (size_t)n - keep, keep);
                g_error[keep] = 0;
            }
            Py_DECREF(text);
        }
    }
    if (!g_error[0]) set_error("python raised and its traceback could not be formatted");
    PyErr_Clear();
    Py_XDECREF(lines);
    Py_XDECREF(traceback);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(tb);
    return status;
}

static PyThreadState *g_main_state;

exteria_status exteria_pyhost_init(const exteria_pyhost_config *cfg) {
    if (!cfg || !cfg->stdlib || !cfg->stdlib[0]) return EXTERIA_E_ARG;
    if (g_running) return EXTERIA_E_STATE;
    g_cfg = *cfg;
    g_error[0] = 0;
    if (PyImport_AppendInittab("_exteria", exteria_module_init) < 0) return EXTERIA_E_NOMEM;
    for (size_t i = 0; i < EXTERIA_PYHOST_MODULES_MAX && cfg->modules[i].name; ++i) {
        if (!cfg->modules[i].init) return EXTERIA_E_ARG;
        if (PyImport_AppendInittab(cfg->modules[i].name, (PyObject *(*)(void))cfg->modules[i].init) < 0) return EXTERIA_E_NOMEM;
    }

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.install_signal_handlers = 0;
    config.write_bytecode = 0;
    config.site_import = 0;
    config.user_site_directory = 0;
    config.pathconfig_warnings = 0;
    config.module_search_paths_set = 1;
    PyStatus st = PyConfig_SetBytesString(&config, &config.program_name, "exteria");
    if (!PyStatus_Exception(st)) st = PyConfig_SetBytesString(&config, &config.home, cfg->stdlib);
    const char *dirs[1 + EXTERIA_PYHOST_PATHS_MAX + 1];
    size_t n = 0;
    dirs[n++] = cfg->stdlib;
    for (size_t i = 0; i < EXTERIA_PYHOST_PATHS_MAX && cfg->paths[i]; ++i) dirs[n++] = cfg->paths[i];
    for (size_t i = 0; i < n && !PyStatus_Exception(st); ++i) {
        wchar_t *wide = Py_DecodeLocale(dirs[i], NULL);
        if (!wide) {
            st = PyStatus_NoMemory();
            break;
        }
        st = PyWideStringList_Append(&config.module_search_paths, wide);
        PyMem_RawFree(wide);
    }
    if (!PyStatus_Exception(st)) st = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(st)) {
        snprintf(g_error, sizeof g_error, "python did not start: %s", st.err_msg ? st.err_msg : "unknown");
        return EXTERIA_E_IO;
    }

    g_wd_quit = 0;
    g_wd_armed = 0;
    if (pthread_create(&g_wd_thread, NULL, watchdog_main, NULL) == 0) g_wd_started = 1;
    /* drop the lock so every call takes it with PyGILState_Ensure, from any thread */
    g_main_state = PyEval_SaveThread();
    g_running = 1;
    return EXTERIA_OK;
}

exteria_status exteria_pyhost_call(const char *module, const char *func, const char *json_args, uint32_t timeout_ms,
                                   char *out, size_t cap, size_t *out_len) {
    if (out_len) *out_len = 0;
    if (!module || !func || !json_args || !out || cap < 2) return EXTERIA_E_ARG;
    if (!g_running) return EXTERIA_E_STATE;
    if (strlen(json_args) > EXTERIA_PYHOST_ARGS_MAX) return EXTERIA_E_LIMIT;
    g_error[0] = 0;
    out[0] = 0;

    exteria_status status = EXTERIA_E_STATE;
    PyGILState_STATE gil = PyGILState_Ensure();
    PyObject *mod = NULL, *fn = NULL, *json = NULL, *args = NULL, *result = NULL, *dumped = NULL;
    if (timeout_ms && g_wd_started) watchdog_arm(timeout_ms);
    else timeout_ms = 0;

    json = PyImport_ImportModule("json");
    if (!json) goto raised;
    args = PyObject_CallMethod(json, "loads", "s", json_args);
    if (!args) {
        PyErr_Clear();
        set_error("the arguments are not json");
        status = EXTERIA_E_MALFORMED;
        goto done;
    }
    if (!PyList_Check(args)) {
        set_error("the arguments are not a json list");
        status = EXTERIA_E_MALFORMED;
        goto done;
    }
    mod = PyImport_ImportModule(module);
    if (!mod) goto raised;
    fn = PyObject_GetAttrString(mod, func);
    if (!fn) goto raised;
    PyObject *tuple = PyList_AsTuple(args);
    if (!tuple) goto raised;
    result = PyObject_CallObject(fn, tuple);
    Py_DECREF(tuple);
    if (!result) goto raised;
    dumped = PyObject_CallMethod(json, "dumps", "O", result);
    if (!dumped) {
        PyErr_Clear();
        set_error("the result is not json");
        status = EXTERIA_E_MALFORMED;
        goto done;
    }
    Py_ssize_t n = 0;
    const char *utf8 = PyUnicode_AsUTF8AndSize(dumped, &n);
    if (!utf8) goto raised;
    if ((size_t)n >= cap) {
        set_error("the result does not fit the reply buffer");
        status = EXTERIA_E_LIMIT;
        goto done;
    }
    memcpy(out, utf8, (size_t)n);
    out[n] = 0;
    if (out_len) *out_len = (size_t)n;
    status = EXTERIA_OK;
    goto done;

raised:
    status = take_exception();
done:
    if (timeout_ms) watchdog_disarm();
    Py_XDECREF(dumped);
    Py_XDECREF(result);
    Py_XDECREF(args);
    Py_XDECREF(fn);
    Py_XDECREF(mod);
    Py_XDECREF(json);
    PyGILState_Release(gil);
    return status;
}

const char *exteria_pyhost_error(void) {
    return g_error;
}

void exteria_pyhost_shutdown(void) {
    if (!g_running) return;
    if (g_wd_started) {
        pthread_mutex_lock(&g_wd_lock);
        g_wd_quit = 1;
        pthread_cond_signal(&g_wd_cond);
        pthread_mutex_unlock(&g_wd_lock);
        pthread_join(g_wd_thread, NULL);
        g_wd_started = 0;
    }
    PyEval_RestoreThread(g_main_state);
    Py_FinalizeEx();
    g_running = 0;
}
