"""certifi.where(): the ca bundle shipped next to the standard library (python/cacert.pem, the mozilla roots of curl.se)"""
import os


def where():
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "cacert.pem")
    if not os.path.isfile(path):
        raise FileNotFoundError("the ca bundle is missing: " + path)
    return path
