"""a dex runtime in python: reads dex files and runs their classes by translating methods into python functions"""

from . import api, cache, jlang, limits  # the java.lang core registers itself
from . import jcore  # noqa: F401  and the members it leaves out
from . import index as _index
from .classes import BOOT, DexClass, VMLoader
from .container import load_container
from .format import DexFile, DexFormatError
from .opcodes import DecodeError
from .translate import TranslateError

from . import runtime as _runtime

_runtime.configure_interpreter()

# every other library module is imported when a program first names one of its classes
for _name, _module in _index.NAMES.items():
    api.host_lazy(_name, "dexvm." + _module)


def load(data, parent=None, name=None):
    """a VMLoader over the dex files of data: one dex file, a zip with classes.dex and classesN.dex, or bytes of either"""
    return VMLoader(load_container(data), parent=parent, name=name)
