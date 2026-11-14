class JavaClass:
    """marker base of the objects jclass returns, for plugins that test isinstance"""


def __getattr__(name):
    # plugins import the proxies from java.chaquopy as well as from java
    if name in ("dynamic_proxy", "static_proxy"):
        import java
        return getattr(java, name)
    raise AttributeError(name)
