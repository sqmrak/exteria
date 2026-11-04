"""why a plugin did not load, in the words of the popup the app shows. the sdk reports the first failure of an import as an
error text; the person is better served by what stops the plugin as a whole: java code the system cannot run, the number of
android classes the plugin names that the shims do not have, a library that is not on, a feature the app does not offer.

the answer is a dictionary of plain values, the app turns it into text in the language of the interface:
  kind: "java", "android", "library", "feature" or "other"
  classes: up to five names, what the kind is about
  missing, total: android classes the plugin names that are missing, and all it names (kind android)
  detail: the last line of the error (kind other)"""

import ast
import os
import re
import zipfile

_JAVA_CODE = re.compile(r"\b(InMemoryDexClassLoader|DexClassLoader|PathClassLoader|dalvik\.system)\b")
_JAVA_ROOTS = ("android", "androidx", "org.telegram", "com.exteragram", "com.google", "de.robv", "dalvik", "java", "javax", "kotlin")
_BY_NAME = re.compile(r"""(?:find_class|jclass)\(\s*["']([\w.$]+)["']""")
_NO_MODULE = re.compile(r"No module named '([\w.]+)'")
_NO_CLASS = re.compile(r"no such Java class: ([\w.$]+)")
_NOT_ON_IOS = re.compile(r"([\w.$]+) is not available on ios")
_NO_NAME = re.compile(r"cannot import name '(\w+)' from '([\w.]+)'")
_SOURCE_MAX = 1 << 20
_SHOWN = 5


def _java_root(name):
    return any(name == root or name.startswith(root + ".") for root in _JAVA_ROOTS)


def _sources(path):
    """the python text of a plugin file, or of every module of an archive, and the names of the files of java code in it"""
    texts, java_files = [], []
    if str(path).endswith((".elyx", ".eaf")):
        try:
            with zipfile.ZipFile(path) as archive:
                for info in archive.infolist():
                    if info.filename.endswith((".dex", ".jar")):
                        java_files.append(info.filename)
                    elif info.filename.endswith(".py") and info.file_size <= _SOURCE_MAX:
                        texts.append(archive.read(info).decode("utf-8", "replace"))
        except (OSError, zipfile.BadZipFile):
            pass
    else:
        try:
            with open(path, "rb") as handle:
                texts.append(handle.read(_SOURCE_MAX).decode("utf-8", "replace"))
        except OSError:
            pass
    return texts, java_files


def _named_classes(text):
    """the java class names a source asks for by import or by string, as full names"""
    names = set()
    try:
        tree = ast.parse(text)
    except SyntaxError:
        tree = None
    if tree is not None:
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module and _java_root(node.module) and node.module != "java":
                names.update(node.module + "." + alias.name for alias in node.names if alias.name != "*")
            elif isinstance(node, ast.Import):
                names.update(alias.name for alias in node.names if _java_root(alias.name) and alias.name != "java")
    names.update(found for found in _BY_NAME.findall(text) if _java_root(found))
    return names


def _present(name):
    from hook_utils import find_class
    if find_class(name) is not None:
        return True
    # a module of the shims (import android.widget) is not a class
    import importlib.util
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def _last_line(text):
    lines = [line.strip() for line in str(text).splitlines() if line.strip()]
    return lines[0] if lines else ""


def explain(path, error):
    """the reason a plugin at path did not load, given the error text of the sdk"""
    error = str(error or "")
    texts, java_files = _sources(path)
    java = list(java_files)
    for text in texts:
        java.extend(sorted(set(match.group(1) for match in _JAVA_CODE.finditer(text))))
    if java:
        return {"kind": "java", "classes": sorted(set(java))[:_SHOWN]}
    named = set()
    for text in texts:
        named |= _named_classes(text)
    missing = sorted(name for name in named if not _present(name))
    if missing:
        return {"kind": "android", "classes": missing[:_SHOWN], "missing": len(missing), "total": len(named)}
    found = _NO_CLASS.search(error) or _NOT_ON_IOS.search(error)
    if found:
        return {"kind": "feature" if _NOT_ON_IOS.search(error) else "android", "classes": [found.group(1)], "missing": 1, "total": 1}
    renamed = _NO_NAME.search(error)
    if renamed and _java_root(renamed.group(2)):
        return {"kind": "android", "classes": [renamed.group(2) + "." + renamed.group(1)], "missing": 1, "total": 1}
    module = _NO_MODULE.search(error)
    if module:
        name = module.group(1)
        if _java_root(name):
            return {"kind": "android", "classes": [name], "missing": 1, "total": 1}
        return {"kind": "library", "classes": [name.partition(".")[0]]}
    return {"kind": "other", "detail": _last_line(error)}
