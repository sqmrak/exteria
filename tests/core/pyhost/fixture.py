import _exteria


def add(a, b):
    return a + b


def echo(value):
    return value


def nothing():
    return None


def boom():
    raise ValueError("boom")


def denied():
    raise PermissionError("no")


def spin():
    while True:
        pass


def service(name, payload):
    return _exteria.service(name, payload)


def service_error(name):
    try:
        _exteria.service(name, "{}")
    except Exception as e:
        return type(e).__name__
    return "none"


def not_json():
    return object()


def big(n):
    return "x" * n
