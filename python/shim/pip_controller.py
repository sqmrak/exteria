"""the dependency check of the sdk, without a package index. the app installs nothing at run time: code fetched from
pypi would run with the rights of the app, and the only libraries a plugin can have are the ones shipped in the bundle.
a requirement is met when its module is importable here (requests, websocket-client, certifi, pyyaml and the standard
library); any other fails the load with the name of the package"""

import importlib.util
import re

# distribution name to the module it installs, for the ones that differ
_MODULE = {"websocket-client": "websocket", "pyyaml": "yaml", "pillow": "PIL", "beautifulsoup4": "bs4", "python-dateutil": "dateutil"}


def _normalize(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def is_provided(name):
    module = _MODULE.get(_normalize(name), name.replace("-", "_"))
    try:
        return importlib.util.find_spec(module) is not None
    except (ImportError, ValueError):
        return False


def ensure_requirements(plugin_id, requirements):
    missing = []
    for raw in requirements or []:
        name = re.split(r"[\s;<>=!~\[(]", str(raw).strip(), maxsplit=1)[0]
        if name and not is_provided(name):
            missing.append(name)
    if missing:
        raise RuntimeError("this app ships no %s and installs nothing at run time" % ", ".join(missing))


def remove_requirements(plugin_id):
    pass


def restore_sys_path():
    pass


def installed_packages():
    return {}
