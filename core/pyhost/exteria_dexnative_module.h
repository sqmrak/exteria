#ifndef EXTERIA_DEXNATIVE_MODULE_H
#define EXTERIA_DEXNATIVE_MODULE_H

/* the PyInit function of _exteria_dexnative, for exteria_pyhost_config.modules: the register machine of
   core/dexnative as a python module. python/shim/dexvm/native.py is its only user */
void *exteria_dexnative_module_init(void);

#endif
