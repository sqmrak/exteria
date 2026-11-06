"""_scproxy: the macos module urllib.request imports at once when sys.platform is darwin, which it is on ios. cpython's own reads the proxy of the
SystemConfiguration framework, which ios does not have; this one asks the app for the system proxy settings it reads from CFNetwork and gives the answers
the same way (the app is asked when a proxy is looked up, not when urllib is imported): the proxy of a scheme as http://host[:port] (whatever the scheme, as in cpython), the hosts that skip the proxy, and whether simple hostnames do"""


def _get_proxy_settings():
    from android import _ui
    answer = _ui.ask("net.proxies")
    return {"exclude_simple": bool(answer.get("exclude_simple")), "exceptions": tuple(str(host) for host in answer.get("exceptions", ()))}


def _get_proxies():
    from android import _ui
    proxies = {}
    answer = _ui.ask("net.proxies")
    for scheme in ("http", "https", "ftp"):
        entry = answer.get(scheme)
        if not entry:
            continue
        port = entry.get("port")
        proxies[scheme] = "http://%s:%d" % (entry["host"], int(port)) if port is not None else "http://%s" % entry["host"]
    return proxies
