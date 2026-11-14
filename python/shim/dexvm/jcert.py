"""X.509 certificates, X500Principal, CertificateFactory and an in-memory KeyStore

a certificate is read from DER or PEM with a strict reader of the ASN.1 it needs (bounds on every length, a depth limit, no
indefinite lengths). its fields answer as java.security.cert.X509Certificate does: names, validity, serial number, the
signature algorithm, the public key (RSA and EC; any other key is an X.509 encoded key without parameters), the common
extensions, and verify() for RSA PKCS#1 v1.5 signatures. verify() of an ECDSA or RSASSA-PSS signature, certification paths,
revocation lists and the toString dump of the jdk are not implemented and say so

a KeyStore lives in memory. load(null, null) makes an empty one, load(stream) and store(stream) refuse: PKCS#12, JKS and BKS
files need the password based encryption of those formats, which this runtime does not carry. tests/fixtures/dex/src/Certs.java
prints the same text on a jvm"""

import base64
import hashlib
import re
import time

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jcrypto import RSAPublicKeyImpl, _rsa_from_encoded
from .jlang import Object, jstr
from .jnum import BigInteger
from .jutil import PyIterator, check_nonnull, iterate

MAX_DEPTH = 12
MAX_CERTIFICATE = 1 << 20


def _throw(name, message=None):
    runtime.throw_new(name, message)


def _cert_error(message, name="java.security.cert.CertificateException"):
    _throw(name, message)


class DerError(Exception):
    pass


def der_read(data, pos, end):
    """(tag, content start, content end) of the element at pos; DerError when it does not fit before end"""
    if pos + 2 > end:
        raise DerError("truncated element")
    tag = data[pos]
    if tag & 0x1F == 0x1F:
        raise DerError("high tag numbers are not supported")
    length = data[pos + 1]
    start = pos + 2
    if length & 0x80:
        count = length & 0x7F
        if count == 0 or count > 4 or start + count > end:
            raise DerError("bad length")
        length = int.from_bytes(data[start:start + count], "big")
        start += count
    stop = start + length
    if stop > end:
        raise DerError("element runs past its parent")
    return tag, start, stop


def der_children(data, start, stop, depth=0):
    if depth > MAX_DEPTH:
        raise DerError("nested too deeply")
    items = []
    pos = start
    while pos < stop:
        tag, cs, ce = der_read(data, pos, stop)
        items.append((tag, cs, ce, pos))
        pos = ce
    return items


def der_oid(data, start, stop):
    if start >= stop:
        raise DerError("empty object identifier")
    first = data[start]
    parts = [first // 40, first % 40] if first < 80 else [2, first - 80]
    value = 0
    for byte in data[start + 1:stop]:
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            parts.append(value)
            value = 0
    return ".".join(str(p) for p in parts)


def der_int(data, start, stop):
    return int.from_bytes(data[start:stop], "big", signed=True)


def der_encode(tag, content):
    n = len(content)
    if n < 128:
        length = bytes([n])
    else:
        raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
        length = bytes([0x80 | len(raw)]) + raw
    return bytes([tag]) + length + content


def der_oid_encode(oid):
    numbers = [int(p) for p in oid.split(".")]
    out = bytearray([numbers[0] * 40 + numbers[1]])
    for number in numbers[2:]:
        chunk = [number & 0x7F]
        number >>= 7
        while number:
            chunk.append(0x80 | (number & 0x7F))
            number >>= 7
        out.extend(reversed(chunk))
    return bytes(out)


def _string_of(tag, raw):
    if tag in (0x0C, 0x13, 0x16, 0x12, 0x19, 0x1A, 0x1B):
        return raw.decode("utf-8" if tag == 0x0C else "latin-1", "replace")
    if tag == 0x14:
        return raw.decode("latin-1")
    if tag == 0x1E:
        return raw.decode("utf-16-be", "replace")
    if tag == 0x1C:
        return raw.decode("utf-32-be", "replace")
    return None


_KEYWORDS = {"2.5.4.3": "CN", "2.5.4.6": "C", "2.5.4.7": "L", "2.5.4.8": "ST", "2.5.4.9": "STREET", "2.5.4.10": "O",
             "2.5.4.11": "OU", "0.9.2342.19200300.100.1.25": "DC", "0.9.2342.19200300.100.1.1": "UID"}
_EXTRA = {"2.5.4.5": "SERIALNUMBER", "2.5.4.12": "T", "2.5.4.4": "SURNAME", "2.5.4.42": "GIVENNAME", "2.5.4.43": "INITIALS",
          "2.5.4.44": "GENERATION", "2.5.4.46": "DNQ", "1.2.840.113549.1.9.1": "EMAILADDRESS", "2.5.4.13": "DESCRIPTION"}
_BY_KEYWORD = {value: key for key, value in {**_KEYWORDS, **_EXTRA}.items()}
_BY_KEYWORD.update({"E": "1.2.840.113549.1.9.1", "EMAIL": "1.2.840.113549.1.9.1", "TITLE": "2.5.4.12", "SN": "2.5.4.4",
                    "GN": "2.5.4.42"})


class Rdn:
    """one attribute: its object identifier, its text when it is a string, the DER of its value"""

    def __init__(self, oid, text, der_value):
        self.oid, self.text, self.der = oid, text, der_value


def parse_name(data, start, stop):
    """the relative distinguished names of a Name, in encoded order, each a list of Rdn (a multi valued rdn has several)"""
    out = []
    for tag, cs, ce, _ in der_children(data, start, stop, 1):
        if tag != 0x31:
            raise DerError("rdn is not a set")
        rdn = []
        for atag, acs, ace, _ in der_children(data, cs, ce, 2):
            if atag != 0x30:
                raise DerError("attribute is not a sequence")
            parts = der_children(data, acs, ace, 3)
            if len(parts) != 2 or parts[0][0] != 0x06:
                raise DerError("bad attribute")
            oid = der_oid(data, parts[0][1], parts[0][2])
            vtag, vcs, vce, vpos = parts[1]
            rdn.append(Rdn(oid, _string_of(vtag, data[vcs:vce]), data[vpos:vce]))
        out.append(rdn)
    return out


def _rfc2253_value(rdn, keep_non_ascii=True):
    if rdn.text is None:
        return "#" + rdn.der.hex()
    text = rdn.text
    out = []
    for index, char in enumerate(text):
        if char in ',+"\\<>;':
            out.append("\\" + char)
        elif index == 0 and char in "# ":
            out.append("\\" + char)
        elif index == len(text) - 1 and char == " ":
            out.append("\\ ")
        elif ord(char) < 0x20 or ord(char) == 0x7F:
            out.append("\\%02X" % ord(char))
        else:
            out.append(char)
    return "".join(out)


def _keyword_or_oid(oid, table):
    return table.get(oid)


def format_name(rdns, style):
    """RFC2253 (the default of getName()), RFC1779, CANONICAL; the rdns come in encoded order and are written last first"""
    parts = []
    for rdn in reversed(rdns):
        pieces = []
        for attribute in rdn:
            if style == "RFC2253":
                key = _KEYWORDS.get(attribute.oid) or attribute.oid
                # an attribute without a keyword is written as its object identifier and the hex of its DER value
                value = _rfc2253_value(attribute) if key != attribute.oid else "#" + attribute.der.hex()
                pieces.append("%s=%s" % (key, value))
            elif style == "CANONICAL":
                key = _KEYWORDS.get(attribute.oid) or attribute.oid
                if attribute.text is None:
                    value = "#" + attribute.der.hex()
                else:
                    import unicodedata
                    folded = unicodedata.normalize("NFKD", re.sub(r"\s+", " ", attribute.text.strip()).lower())
                    value = _rfc2253_value(Rdn(attribute.oid, folded, attribute.der))
                pieces.append("%s=%s" % (key.lower(), value))
            else:
                key = _KEYWORDS.get(attribute.oid) or "OID." + attribute.oid
                if attribute.text is None:
                    value = "#" + attribute.der.hex()
                elif re.search(r'[,+="\\<>#;\n]|^ | $', attribute.text):
                    value = '"%s"' % attribute.text.replace("\\", "\\\\").replace('"', '\\"')
                else:
                    value = attribute.text
                pieces.append("%s=%s" % (key, value))
        parts.append("+".join(pieces) if style != "RFC1779" else " + ".join(pieces))
    return ("," if style in ("RFC2253", "CANONICAL") else ", ").join(parts)


def display_name(rdns):
    """X500Name.toString(): the keywords the jdk knows, ", " between rdns, last rdn first, values quoted when they need it"""
    parts = []
    for rdn in reversed(rdns):
        pieces = []
        for attribute in rdn:
            key = _KEYWORDS.get(attribute.oid) or _EXTRA.get(attribute.oid) or "OID." + attribute.oid
            if attribute.text is None:
                value = "#" + attribute.der.hex()
            else:
                value = attribute.text
                if re.search(r'[,+="\\<>#;\n]|^ | $', value):
                    value = value.replace("\\", "\\\\").replace('"', '\\"')
                    value = '"%s"' % value if re.search(r'[+="\\<>#;\n]|^ | $', attribute.text) or "," in attribute.text else value
            pieces.append("%s=%s" % (key, value))
        parts.append(" + ".join(pieces))
    return ", ".join(parts)


def _encode_value(text):
    if all(c.isascii() and (c.isalnum() or c in " '()+,-./:=?") for c in text):
        return der_encode(0x13, text.encode("ascii"))
    return der_encode(0x0C, text.encode("utf-8"))


def parse_dn(text):
    """the Rdns (encoded order) of a name given as RFC2253 or RFC1779 text"""
    pieces, buf, quoted, escaped = [], [], False, False
    # split the string into rdns at unquoted commas and semicolons, remembering plus signs inside
    tokens = []
    i = 0
    while i < len(text):
        c = text[i]
        if escaped:
            buf.append(("\\", c))
            escaped = False
        elif c == "\\":
            escaped = True
        elif c == '"':
            quoted = not quoted
            buf.append(("q", c))
        elif not quoted and c in ",;":
            tokens.append(buf)
            buf = []
        elif not quoted and c == "+":
            buf.append(("+", c))
        else:
            buf.append(("c", c))
        i += 1
    tokens.append(buf)

    def render(items):
        out = []
        for kind, char in items:
            if kind == "q":
                continue
            out.append(char)
        return "".join(out)

    result = []
    for buf in tokens:
        if not buf:
            continue
        groups, current = [], []
        for item in buf:
            if item[0] == "+":
                groups.append(current)
                current = []
            else:
                current.append(item)
        groups.append(current)
        rdn = []
        for group in groups:
            joined = render(group)
            if "=" not in joined:
                _throw("java.lang.IllegalArgumentException", "improperly specified input name: " + text)
            key, _, value = joined.partition("=")
            key = key.strip()
            value = value.strip() if not value.endswith("\\ ") else value[:-3].strip() + " "
            oid = _BY_KEYWORD.get(key.upper()) or (key[4:] if key.upper().startswith("OID.") else key)
            if not re.fullmatch(r"\d+(\.\d+)+", oid):
                _throw("java.lang.IllegalArgumentException", "Invalid keyword \"%s\"" % key)
            if value.startswith("#"):
                der_value = bytes.fromhex(value[1:])
                rdn.append(Rdn(oid, None, der_value))
            else:
                if oid in ("1.2.840.113549.1.9.1", "0.9.2342.19200300.100.1.25") and value.isascii():
                    encoded = der_encode(0x16, value.encode("ascii"))
                elif oid == "2.5.4.6":
                    encoded = der_encode(0x13, value.encode("ascii", "replace"))
                else:
                    encoded = _encode_value(value)
                rdn.append(Rdn(oid, value, encoded))
        result.append(rdn)
    # text is written last rdn first: the encoded order is the reverse
    result.reverse()
    return result


def encode_name(rdns):
    body = b""
    for rdn in rdns:
        attributes = b"".join(der_encode(0x30, der_encode(0x06, der_oid_encode(a.oid)) + a.der) for a in rdn)
        body += der_encode(0x31, attributes)
    return der_encode(0x30, body)


@host_class("javax.security.auth.x500.X500Principal", final=True, interfaces=("java.security.Principal", "java.io.Serializable"))
class X500Principal(Object):
    RFC1779, RFC2253, CANONICAL = "RFC1779", "RFC2253", "CANONICAL"

    def __init__(self, source, keywords=None):
        if source is None:
            runtime.npe("provided null name")
        if isinstance(source, str):
            self._rdns = parse_dn(source)
            self._der = encode_name(self._rdns)
        else:
            data = bytes(b & 0xFF for b in source)
            try:
                tag, cs, ce = der_read(data, 0, len(data))
                if tag != 0x30 or ce != len(data):
                    raise DerError("not a name")
                self._rdns = parse_name(data, cs, ce)
            except DerError as error:
                _throw("java.lang.IllegalArgumentException", "improperly specified input name: " + str(error))
            self._der = data

    @staticmethod
    def of_der(data):
        found = X500Principal.__new__(X500Principal)
        tag, cs, ce = der_read(data, 0, len(data))
        found._rdns = parse_name(data, cs, ce)
        found._der = bytes(data)
        return found

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "([B)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/util/Map;)V")
    def _init(self, source, keywords=None):
        X500Principal.__init__(self, source, keywords)

    @jmethod("getName", "()Ljava/lang/String;")
    @jmethod("getName", "(Ljava/lang/String;)Ljava/lang/String;")
    def getName(self, style="RFC2253"):
        if style not in ("RFC1779", "RFC2253", "CANONICAL"):
            _throw("java.lang.IllegalArgumentException", "invalid format specified")
        return jstr(format_name(self._rdns, style))

    @jmethod("getEncoded", "()[B")
    def getEncoded(self):
        array = runtime.new_array("[B", 0)
        array.extend(b - 256 if b > 127 else b for b in self._der)
        return array

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return jstr(display_name(self._rdns))

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, X500Principal) and format_name(other._rdns, "CANONICAL") == format_name(self._rdns, "CANONICAL") else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(format_name(self._rdns, "CANONICAL"))


class _DistinguishedName(Object):
    """the java.security.Principal getSubjectDN() answers: the name as text"""

    def __init__(self, rdns):
        self._rdns = rdns

    def getName(self):
        return jstr(display_name(self._rdns))

    toString = getName

    def equals(self, other):
        return 1 if isinstance(other, _DistinguishedName) and format_name(other._rdns, "CANONICAL") == format_name(self._rdns, "CANONICAL") else 0

    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(format_name(self._rdns, "CANONICAL"))


host_class("sun.security.x509.X500Name", interfaces=("java.security.Principal",))(_DistinguishedName)


def _der_time(tag, raw):
    text = raw.decode("ascii")
    if tag == 0x17:
        m = re.fullmatch(r"(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)?Z", text)
        if m is None:
            raise DerError("bad UTCTime")
        year = int(m.group(1))
        year += 2000 if year < 50 else 1900
        parts = (year, int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6) or 0))
    elif tag == 0x18:
        m = re.fullmatch(r"(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(?:\.\d+)?Z", text)
        if m is None:
            raise DerError("bad GeneralizedTime")
        parts = tuple(int(g) for g in m.groups())
    else:
        raise DerError("bad time tag")
    import calendar
    return calendar.timegm(parts + (0, 0, 0)) * 1000


_SIGNATURES = {
    "1.2.840.113549.1.1.2": "MD2withRSA", "1.2.840.113549.1.1.4": "MD5withRSA", "1.2.840.113549.1.1.5": "SHA1withRSA",
    "1.2.840.113549.1.1.11": "SHA256withRSA", "1.2.840.113549.1.1.12": "SHA384withRSA", "1.2.840.113549.1.1.13": "SHA512withRSA",
    "1.2.840.113549.1.1.14": "SHA224withRSA", "1.2.840.113549.1.1.10": "RSASSA-PSS", "1.2.840.10045.4.1": "SHA1withECDSA",
    "1.2.840.10045.4.3.1": "SHA224withECDSA", "1.2.840.10045.4.3.2": "SHA256withECDSA", "1.2.840.10045.4.3.3": "SHA384withECDSA",
    "1.2.840.10045.4.3.4": "SHA512withECDSA", "1.3.101.112": "Ed25519", "1.3.101.113": "Ed448",
}
_RSA_PREFIX = {
    "SHA1": bytes.fromhex("3021300906052b0e03021a05000414"), "SHA224": bytes.fromhex("302d300d06096086480165030402040500041c"),
    "SHA256": bytes.fromhex("3031300d060960864801650304020105000420"), "SHA384": bytes.fromhex("3041300d060960864801650304020205000430"),
    "SHA512": bytes.fromhex("3051300d060960864801650304020305000440"),
}
_KEY_ALGORITHMS = {"1.2.840.113549.1.1.1": "RSA", "1.2.840.10045.2.1": "EC", "1.3.101.112": "Ed25519", "1.3.101.113": "Ed448",
                   "1.3.101.110": "X25519", "1.3.101.111": "X448", "1.2.840.113549.1.1.10": "RSASSA-PSS",
                   "1.2.840.10040.4.1": "DSA", "1.2.840.113549.1.3.1": "DH"}
_CURVES = {"1.2.840.10045.3.1.7": ("secp256r1", 256), "1.3.132.0.34": ("secp384r1", 384), "1.3.132.0.35": ("secp521r1", 521)}
_CURVE_PARAMETERS = {
    "secp256r1": (0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF,
                  0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC,
                  0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B,
                  0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296,
                  0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5,
                  0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551, 1),
    "secp384r1": (2 ** 384 - 2 ** 128 - 2 ** 96 + 2 ** 32 - 1, 2 ** 384 - 2 ** 128 - 2 ** 96 + 2 ** 32 - 4,
                  0xB3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875AC656398D8A2ED19D2A85C8EDD3EC2AEF,
                  0xAA87CA22BE8B05378EB1C71EF320AD746E1D3B628BA79B9859F741E082542A385502F25DBF55296C3A545E3872760AB7,
                  0x3617DE4A96262C6F5D9E98BF9292DC29F8F41DBD289A147CE9DA3113B5F0B8C00A60B1CE1D7E819D7A431D7C90EA0E5F,
                  0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF581A0DB248B0A77AECEC196ACCC52973, 1),
    "secp521r1": (2 ** 521 - 1, 2 ** 521 - 4,
                  0x0051953EB9618E1C9A1F929A21A0B68540EEA2DA725B99B315F3B8B489918EF109E156193951EC7E937B1652C0BD3BB1BF073573DF883D2C34F1EF451FD46B503F00,
                  0x00C6858E06B70404E9CD9E3ECB662395B4429C648139053FB521F828AF606B4D3DBAA14B5E77EFE75928FE1DC127A2FFA8DE3348B3C1856A429BF97E7E31C2E5BD66,
                  0x011839296A789A3BC0045C8A5FB42C7D1BD998F54449579B446817AFBD17273E662C97EE72995EF42640C550B9013FAD0761353C7086A272C24088BE94769FD16650,
                  0x01FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA51868783BF2F966B7FCC0148F709A5D03BB5C9B8899C47AEBB6FB71E91386409, 1),
}


_PSS_HASHES = {"1.3.14.3.2.26": "sha1", "2.16.840.1.101.3.4.2.4": "sha224", "2.16.840.1.101.3.4.2.1": "sha256",
               "2.16.840.1.101.3.4.2.2": "sha384", "2.16.840.1.101.3.4.2.3": "sha512"}


def _mgf1(hash_name, seed, length):
    out = bytearray()
    counter = 0
    while len(out) < length:
        out += hashlib.new(hash_name, seed + counter.to_bytes(4, "big")).digest()
        counter += 1
    return bytes(out[:length])


def _ec_add(curve, a, b):
    p, coefficient = curve[0], curve[1]
    if a is None:
        return b
    if b is None:
        return a
    if a[0] == b[0] and (a[1] + b[1]) % p == 0:
        return None
    if a == b:
        slope = (3 * a[0] * a[0] + coefficient) * pow(2 * a[1], -1, p) % p
    else:
        slope = (b[1] - a[1]) * pow(b[0] - a[0], -1, p) % p
    x = (slope * slope - a[0] - b[0]) % p
    return x, (slope * (a[0] - x) - a[1]) % p


def _ec_multiply(curve, k, point):
    result = None
    while k:
        if k & 1:
            result = _ec_add(curve, result, point)
        point = _ec_add(curve, point, point)
        k >>= 1
    return result


def ecdsa_verify(curve, public, digest, signature):
    """true when the DER ECDSA signature (SEQUENCE of r and s) of the digest is valid for the public point"""
    p, a, b, gx, gy, n = curve[:6]
    try:
        tag, cs, ce = der_read(signature, 0, len(signature))
        if tag != 0x30 or ce != len(signature):
            return False
        parts = der_children(signature, cs, ce, 1)
        if len(parts) != 2 or parts[0][0] != 0x02 or parts[1][0] != 0x02:
            return False
        r, s = der_int(signature, parts[0][1], parts[0][2]), der_int(signature, parts[1][1], parts[1][2])
    except DerError:
        return False
    if not (0 < r < n and 0 < s < n):
        return False
    x, y = public
    if not (0 <= x < p and 0 <= y < p) or (y * y - (x * x * x + a * x + b)) % p:
        return False
    e = int.from_bytes(digest, "big")
    excess = len(digest) * 8 - n.bit_length()
    if excess > 0:
        e >>= excess
    w = pow(s, -1, n)
    point = _ec_add(curve, _ec_multiply(curve, e * w % n, (gx, gy)), _ec_multiply(curve, r * w % n, (x, y)))
    return point is not None and point[0] % n == r


def _cert_public_key(spki):
    """the PublicKey object for the DER of a SubjectPublicKeyInfo"""
    tag, cs, ce = der_read(spki, 0, len(spki))
    items = der_children(spki, cs, ce, 1)
    algorithm = der_children(spki, items[0][1], items[0][2], 2)
    oid = der_oid(spki, algorithm[0][1], algorithm[0][2])
    if oid == "1.2.840.113549.1.1.1":
        return _rsa_from_encoded(spki, False)
    if oid == "1.2.840.10045.2.1" and len(algorithm) > 1 and algorithm[1][0] == 0x06:
        curve = der_oid(spki, algorithm[1][1], algorithm[1][2])
        point = spki[items[1][1] + 1:items[1][2]]
        return ECPublicKeyImpl(spki, curve, point)
    return GenericPublicKey(spki, _KEY_ALGORITHMS.get(oid, oid))


def _array(data):
    array = runtime.new_array("[B", 0)
    array.extend(b - 256 if b > 127 else b for b in data)
    return array


class GenericPublicKey(Object):
    def __init__(self, encoded, algorithm):
        self._encoded, self._algorithm = encoded, algorithm

    def getAlgorithm(self):
        return self._algorithm

    def getFormat(self):
        return "X.509"

    def getEncoded(self):
        return _array(self._encoded)

    def equals(self, other):
        return 1 if isinstance(other, GenericPublicKey) and other._encoded == self._encoded else 0

    def hashCode(self):
        return runtime.wrap32(int.from_bytes(hashlib.sha1(self._encoded).digest()[:4], "big"))


host_class("sun.security.x509.X509Key", interfaces=("java.security.PublicKey",))(GenericPublicKey)


class ECPublicKeyImpl(GenericPublicKey):
    def __init__(self, encoded, curve_oid, point):
        GenericPublicKey.__init__(self, encoded, "EC")
        self._curve_oid = curve_oid
        size = (len(point) - 1) // 2
        self._x = int.from_bytes(point[1:1 + size], "big")
        self._y = int.from_bytes(point[1 + size:], "big")

    def getW(self):
        return lookup_host("java.security.spec.ECPoint").py(BigInteger(self._x), BigInteger(self._y))

    def getParams(self):
        name = _CURVES.get(self._curve_oid, (None,))[0]
        parameters = _CURVE_PARAMETERS.get(name)
        if parameters is None:
            _throw("java.lang.UnsupportedOperationException", "curve %s is not known" % self._curve_oid)
        p, a, b, gx, gy, n, h = parameters
        spec = lookup_host("java.security.spec")
        field = lookup_host("java.security.spec.ECFieldFp").py(BigInteger(p))
        curve = lookup_host("java.security.spec.EllipticCurve").py(field, BigInteger(a), BigInteger(b))
        point = lookup_host("java.security.spec.ECPoint").py(BigInteger(gx), BigInteger(gy))
        return lookup_host("java.security.spec.ECParameterSpec").py(curve, point, BigInteger(n), h)


host_class("sun.security.ec.ECPublicKeyImpl", interfaces=("java.security.interfaces.ECPublicKey",))(ECPublicKeyImpl)


def _define(table):
    for line in table.strip().splitlines():
        name, parent = line.split()
        from . import api
        if name not in api._classes and api._lazy.get(name, "dexvm.jcert") == "dexvm.jcert":
            host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


_define("""
java.security.cert.CertificateException java.security.GeneralSecurityException
java.security.cert.CertificateEncodingException java.security.cert.CertificateException
java.security.cert.CertificateExpiredException java.security.cert.CertificateException
java.security.cert.CertificateNotYetValidException java.security.cert.CertificateException
java.security.cert.CertificateParsingException java.security.cert.CertificateException
java.security.cert.CRLException java.security.GeneralSecurityException
""")


@host_class("java.security.cert.X509Extension", interface=True)
class X509Extension:
    __slots__ = ()


@host_class("java.security.cert.Certificate", abstract=True, interfaces=("java.io.Serializable",))
class Certificate(Object):
    def __init__(self, type_=None):
        self._type = type_

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, type_):
        Certificate.__init__(self, type_)

    def getType(self):
        return self._type


def _bool_array(bits):
    array = runtime.new_array("[Z", 0)
    array.extend(1 if bit else 0 for bit in bits)
    return array


@host_class("java.security.cert.X509Certificate", abstract=True, interfaces=("java.security.cert.X509Extension",))
class X509Certificate(Certificate):
    pass


@host_class("sun.security.x509.X509CertImpl")
class X509CertImpl(X509Certificate):
    def __init__(self, data):
        if len(data) > MAX_CERTIFICATE:
            _cert_error("certificate is larger than %d bytes" % MAX_CERTIFICATE)
        Certificate.__init__(self, "X.509")
        self._data = bytes(data)
        self._hash = None
        try:
            self._parse()
        except (DerError, IndexError, ValueError, UnicodeError) as error:
            _cert_error("Could not parse certificate: java.io.IOException: %s" % error, "java.security.cert.CertificateParsingException")

    def _parse(self):
        d = self._data
        tag, cs, ce = der_read(d, 0, len(d))
        if tag != 0x30 or ce != len(d):
            raise DerError("not a certificate")
        top = der_children(d, cs, ce, 1)
        if len(top) != 3 or top[0][0] != 0x30:
            raise DerError("certificate has no three parts")
        self._tbs = d[top[0][3]:top[0][2]]
        tbs = der_children(d, top[0][1], top[0][2], 2)
        index = 0
        self._version = 1
        if tbs[0][0] == 0xA0:
            inner = der_children(d, tbs[0][1], tbs[0][2], 3)
            self._version = der_int(d, inner[0][1], inner[0][2]) + 1
            index = 1
        self._serial = der_int(d, tbs[index][1], tbs[index][2])
        self._sig_oid = self._algorithm_oid(d, tbs[index + 1])
        self._sig_params = self._algorithm_params(d, tbs[index + 1])
        self._issuer = parse_name(d, tbs[index + 2][1], tbs[index + 2][2])
        self._issuer_der = d[tbs[index + 2][3]:tbs[index + 2][2]]
        validity = der_children(d, tbs[index + 3][1], tbs[index + 3][2], 3)
        self._not_before = _der_time(validity[0][0], d[validity[0][1]:validity[0][2]])
        self._not_after = _der_time(validity[1][0], d[validity[1][1]:validity[1][2]])
        self._subject = parse_name(d, tbs[index + 4][1], tbs[index + 4][2])
        self._subject_der = d[tbs[index + 4][3]:tbs[index + 4][2]]
        self._spki = d[tbs[index + 5][3]:tbs[index + 5][2]]
        self._extensions = {}
        self._extension_order = []
        for item in tbs[index + 6:]:
            if item[0] == 0xA3:
                outer = der_children(d, item[1], item[2], 3)
                for ext in der_children(d, outer[0][1], outer[0][2], 4):
                    parts = der_children(d, ext[1], ext[2], 5)
                    oid = der_oid(d, parts[0][1], parts[0][2])
                    critical = len(parts) == 3 and d[parts[1][1]:parts[1][2]] != b"\x00"
                    value = parts[-1]
                    if value[0] != 0x04:
                        raise DerError("extension value is not an octet string")
                    self._extensions[oid] = (critical, d[value[1]:value[2]], d[value[3]:value[2]])
                    self._extension_order.append(oid)
        self._sig_alg_oid_outer = self._algorithm_oid(d, top[1])
        if top[2][0] != 0x03:
            raise DerError("signature is not a bit string")
        self._signature = d[top[2][1] + 1:top[2][2]]
        self._public_key = None

    @staticmethod
    def _algorithm_oid(d, item):
        parts = der_children(d, item[1], item[2], 3)
        return der_oid(d, parts[0][1], parts[0][2])

    @staticmethod
    def _algorithm_params(d, item):
        """the DER of the parameters of an AlgorithmIdentifier, None when absent or NULL"""
        parts = der_children(d, item[1], item[2], 3)
        if len(parts) < 2 or parts[1][0] == 0x05:
            return None
        return d[parts[1][3]:parts[1][2]]

    # certificate

    def getEncoded(self):
        return _array(self._data)

    def getType(self):
        return "X.509"

    def getVersion(self):
        return self._version

    def getSerialNumber(self):
        return BigInteger(self._serial)

    def getIssuerX500Principal(self):
        return X500Principal.of_der(self._issuer_der)

    def getSubjectX500Principal(self):
        return X500Principal.of_der(self._subject_der)

    def getIssuerDN(self):
        return _DistinguishedName(self._issuer)

    def getSubjectDN(self):
        return _DistinguishedName(self._subject)

    def getNotBefore(self):
        return lookup_host("java.util.Date").py(self._not_before)

    def getNotAfter(self):
        return lookup_host("java.util.Date").py(self._not_after)

    def checkValidity(self, date=None):
        now = int(time.time() * 1000) if date is None else date.getTime()
        if now > self._not_after:
            _throw("java.security.cert.CertificateExpiredException", "NotAfter: " + self.getNotAfter().toString())
        if now < self._not_before:
            _throw("java.security.cert.CertificateNotYetValidException", "NotBefore: " + self.getNotBefore().toString())

    def getTBSCertificate(self):
        return _array(self._tbs)

    def getSignature(self):
        return _array(self._signature)

    def getSigAlgName(self):
        return _SIGNATURES.get(self._sig_oid, self._sig_oid)

    def getSigAlgOID(self):
        return self._sig_oid

    def getSigAlgParams(self):
        return None if self._sig_params is None else _array(self._sig_params)

    def getPublicKey(self):
        if self._public_key is None:
            self._public_key = _cert_public_key(self._spki)
        return self._public_key

    # extensions

    def _ext(self, oid):
        return self._extensions.get(oid)

    def getBasicConstraints(self):
        found = self._ext("2.5.29.19")
        if found is None:
            return -1
        d = found[1]
        tag, cs, ce = der_read(d, 0, len(d))
        children = der_children(d, cs, ce, 1)
        if not children or children[0][0] != 0x01 or d[children[0][1]] == 0:
            return -1
        for child in children:
            if child[0] == 0x02:
                return der_int(d, child[1], child[2])
        return 0x7FFFFFFF

    def getKeyUsage(self):
        found = self._ext("2.5.29.15")
        if found is None:
            return None
        d = found[1]
        tag, cs, ce = der_read(d, 0, len(d))
        unused = d[cs]
        bits = []
        for byte in d[cs + 1:ce]:
            bits.extend((byte >> (7 - i)) & 1 for i in range(8))
        if unused:
            bits = bits[:-unused]
        bits += [0] * (9 - len(bits))
        return _bool_array(bits)

    def getExtendedKeyUsage(self):
        found = self._ext("2.5.29.37")
        if found is None:
            return None
        from .jmap import ArrayList
        d = found[1]
        tag, cs, ce = der_read(d, 0, len(d))
        result = ArrayList()
        for child in der_children(d, cs, ce, 1):
            result.add(jstr(der_oid(d, child[1], child[2])))
        return result

    def _alt_names(self, oid):
        found = self._ext(oid)
        if found is None:
            return None
        from .jmap import ArrayList
        from .jlang import Integer
        d = found[1]
        tag, cs, ce = der_read(d, 0, len(d))
        result = ArrayList()
        for child in der_children(d, cs, ce, 1):
            number = child[0] & 0x1F
            raw = d[child[1]:child[2]]
            entry = ArrayList()
            entry.add(Integer.valueOf(number))
            if number in (1, 2, 6):
                entry.add(jstr(raw.decode("ascii", "replace")))
            elif number == 7:
                if len(raw) == 4:
                    entry.add(jstr(".".join(str(b) for b in raw)))
                else:
                    groups = ["%x" % int.from_bytes(raw[i:i + 2], "big") for i in range(0, 16, 2)]
                    entry.add(jstr(":".join(groups)))
            elif number == 8:
                entry.add(jstr(der_oid(d, child[1], child[2])))
            elif number == 4:
                inner = der_children(d, child[1], child[2], 3)
                entry.add(jstr(format_name(parse_name(d, inner[0][1], inner[0][2]), "RFC2253")))
            else:
                entry.add(_array(raw))
            result.add(entry)
        return result

    def getSubjectAlternativeNames(self):
        return self._alt_names("2.5.29.17")

    def getIssuerAlternativeNames(self):
        return self._alt_names("2.5.29.18")

    def getCriticalExtensionOIDs(self):
        return self._oid_set(True)

    def getNonCriticalExtensionOIDs(self):
        return self._oid_set(False)

    def _oid_set(self, critical):
        from .jmap import HashSet
        found = [oid for oid in self._extension_order if self._extensions[oid][0] == critical]
        if not found and not self._extensions:
            return None
        result = HashSet()
        for oid in found:
            result.add(jstr(oid))
        return result

    def hasUnsupportedCriticalExtension(self):
        known = {"2.5.29.19", "2.5.29.15", "2.5.29.37", "2.5.29.17", "2.5.29.18", "2.5.29.14", "2.5.29.35", "2.5.29.31",
                 "2.5.29.32", "2.5.29.30", "2.5.29.36", "2.5.29.33", "2.5.29.54", "2.5.29.46"}
        return 1 if any(c and oid not in known for oid, (c, _, _) in self._extensions.items()) else 0

    def getExtensionValue(self, oid):
        found = self._ext(oid)
        return None if found is None else _array(self._wrapped(found))

    @staticmethod
    def _wrapped(found):
        return found[2]

    # verify

    def verify(self, key, provider=None):
        name = self.getSigAlgName()
        if self._sig_oid != self._sig_alg_oid_outer:
            _throw("java.security.cert.CertificateException", "Signature algorithm mismatch")
        if name == "RSASSA-PSS":
            self._verify_pss(key)
        elif name.endswith("withECDSA"):
            self._verify_ecdsa(key, name[:-len("withECDSA")])
        elif name.endswith("withRSA"):
            self._verify_rsa(key, name[:-len("withRSA")])
        else:
            _throw("java.lang.UnsupportedOperationException", "verification of %s signatures is not implemented" % name)

    def _verify_rsa(self, key, digest):
        if not isinstance(key, RSAPublicKeyImpl):
            _throw("java.security.InvalidKeyException", "key is not an RSA public key")
        size = (key._n.bit_length() + 7) // 8
        if digest == "MD5":
            prefix = bytes.fromhex("3020300c06082a864886f70d020505000410")
            algorithm = "md5"
        elif digest in _RSA_PREFIX:
            prefix = _RSA_PREFIX[digest]
            algorithm = digest.lower()
        else:
            _throw("java.lang.UnsupportedOperationException", "digest %s is not supported" % digest)
        message = hashlib.new(algorithm, self._tbs).digest()
        signature = int.from_bytes(self._signature, "big")
        if len(self._signature) != size or signature >= key._n:
            _throw("java.security.SignatureException", "Signature length not correct: got %d but was expecting %d" % (
                len(self._signature), size))
        recovered = pow(signature, key._x, key._n).to_bytes(size, "big")
        padded = b"\x00\x01" + b"\xff" * (size - len(prefix) - len(message) - 3) + b"\x00" + prefix + message
        if recovered != padded:
            _throw("java.security.SignatureException", "Signature does not match.")

    def _pss_parameters(self):
        """hash, mgf hash and salt length of the RSASSA-PSS parameters (rfc 4055; defaults are SHA-1, MGF1-SHA-1, 20)"""
        hash_name, mgf_name, salt = "sha1", "sha1", 20
        raw = self._sig_params
        if raw is None:
            return hash_name, mgf_name, salt
        try:
            tag, cs, ce = der_read(raw, 0, len(raw))
            for field in der_children(raw, cs, ce, 1):
                inner = der_children(raw, field[1], field[2], 2)
                if field[0] == 0xA0:
                    hash_name = _PSS_HASHES[self._oid_of(raw, inner[0])]
                elif field[0] == 0xA1:
                    parts = der_children(raw, inner[0][1], inner[0][2], 3)
                    if der_oid(raw, parts[0][1], parts[0][2]) != "1.2.840.113549.1.1.8":
                        _throw("java.security.SignatureException", "Unsupported mask generation function")
                    mgf_name = _PSS_HASHES[self._oid_of(raw, parts[1])]
                elif field[0] == 0xA2:
                    salt = der_int(raw, inner[0][1], inner[0][2])
        except (DerError, KeyError, IndexError):
            _throw("java.security.SignatureException", "Invalid RSASSA-PSS parameters")
        return hash_name, mgf_name, salt

    @staticmethod
    def _oid_of(raw, item):
        parts = der_children(raw, item[1], item[2], 4)
        return der_oid(raw, parts[0][1], parts[0][2])

    def _verify_pss(self, key):
        if not isinstance(key, RSAPublicKeyImpl):
            _throw("java.security.InvalidKeyException", "key is not an RSA public key")
        hash_name, mgf_name, salt_length = self._pss_parameters()
        bits = key._n.bit_length() - 1
        size = (key._n.bit_length() + 7) // 8
        signature = int.from_bytes(self._signature, "big")
        if len(self._signature) != size or signature >= key._n:
            _throw("java.security.SignatureException", "Signature length not correct: got %d but was expecting %d" % (
                len(self._signature), size))
        em_len = (bits + 7) // 8
        em = pow(signature, key._x, key._n).to_bytes(size, "big")[size - em_len:]
        digest_size = hashlib.new(hash_name).digest_size
        m_hash = hashlib.new(hash_name, self._tbs).digest()
        fail = lambda: _throw("java.security.SignatureException", "Signature does not match.")
        if em_len < digest_size + salt_length + 2 or em[-1] != 0xBC:
            fail()
        masked, h = em[:em_len - digest_size - 1], em[em_len - digest_size - 1:-1]
        top = 0xFF >> (8 * em_len - bits)
        if masked[0] & ~top & 0xFF:
            fail()
        db = bytearray(a ^ b for a, b in zip(masked, _mgf1(mgf_name, h, len(masked))))
        db[0] &= top
        pad = len(db) - salt_length - 1
        if any(db[:pad]) or db[pad] != 1:
            fail()
        salt = bytes(db[pad + 1:])
        if hashlib.new(hash_name, b"\x00" * 8 + m_hash + salt).digest() != h:
            fail()

    def _verify_ecdsa(self, key, digest):
        if not isinstance(key, ECPublicKeyImpl):
            _throw("java.security.InvalidKeyException", "key is not an EC public key")
        hash_name = digest.lower()
        if hash_name not in ("sha1", "sha224", "sha256", "sha384", "sha512"):
            _throw("java.lang.UnsupportedOperationException", "digest %s is not supported" % digest)
        curve = _CURVES.get(key._curve_oid)
        if curve is None or curve[0] not in _CURVE_PARAMETERS:
            _throw("java.security.InvalidKeyException", "curve %s is not supported" % key._curve_oid)
        if not ecdsa_verify(_CURVE_PARAMETERS[curve[0]], (key._x, key._y), hashlib.new(hash_name, self._tbs).digest(),
                            self._signature):
            _throw("java.security.SignatureException", "Signature does not match.")

    def equals(self, other):
        return 1 if isinstance(other, X509CertImpl) and other._data == self._data else 0

    def hashCode(self):
        if self._hash is None:
            h = 1
            for byte in self._data:
                h = (31 * h + (byte - 256 if byte > 127 else byte)) & 0xFFFFFFFF
            self._hash = runtime.wrap32(h)
        return self._hash

    def toString(self):
        key = self.getPublicKey()
        out = ["[\n[\n  Version: V%d\n  Subject: %s\n  Signature Algorithm: %s, OID = %s\n\n  Key:  %s\n  Validity: [From: %s,\n"
               "               To: %s]\n  Issuer: %s\n  SerialNumber: %s\n" % (
                   self._version, display_name(self._subject), self._sig_text(), self._sig_oid, _key_text(key),
                   self.getNotBefore().toString(), self.getNotAfter().toString(), display_name(self._issuer),
                   _serial_text(self._serial))]
        if self._extension_order:
            out.append("\nCertificate Extensions: %d\n" % len(self._extension_order))
            # the jdk keeps its extensions in a tree map keyed by name, or by oid for those it does not know
            ordered = sorted(self._extension_order, key=lambda o: _EXTENSION_NAMES.get(o, o))
            for number, oid in enumerate(ordered, 1):
                critical, content, _ = self._extensions[oid]
                out.append("[%d]: ObjectId: %s Criticality=%s\n%s\n" % (
                    number, oid, "true" if critical else "false", _extension_text(oid, content)))
            out.append("]\n")
        else:
            out.append("]\n")
        out.append("  Algorithm: [%s]\n  Signature:\n%s\n]" % (self._sig_text(), _hex_dump(self._signature)))
        return jstr("".join(out))

    def _sig_text(self):
        """the signature algorithm as the jdk prints it; RSASSA-PSS carries its parameters"""
        name = self.getSigAlgName()
        if name != "RSASSA-PSS":
            return name
        hash_name, mgf_name, salt = self._pss_parameters()
        names = {"sha1": "SHA-1", "sha224": "SHA-224", "sha256": "SHA-256", "sha384": "SHA-384", "sha512": "SHA-512"}
        return ("RSASSA-PSS, PSSParameterSpec[hashAlgorithm=%s, maskGenAlgorithm=MGF1ParameterSpec[hashAlgorithm=%s], "
                "saltLength=%d, trailerField=1]" % (names[hash_name], names[mgf_name], salt))


def _hex_dump(data):
    """sun.misc.HexDumpEncoder: offset, 16 bytes in two groups of 8, then the ascii"""
    lines = []
    for start in range(0, len(data), 16):
        chunk = data[start:start + 16]
        hexes = "".join(("%02X " % chunk[i] if i < len(chunk) else "   ") + ("  " if i == 7 else "") for i in range(16))
        text = "".join(chr(b) if 32 <= b < 0x7b else "." for b in chunk)
        lines.append("%04X: %s %s" % (start, hexes, text))
    return "\n".join(lines) + ("\n" if lines else "")


def _serial_text(serial):
    raw = serial.to_bytes((serial.bit_length() + 8) // 8, "big", signed=True) if serial >= 0 else b"\x00"
    return ":".join("%02x" % b for b in raw.lstrip(b"\x00") or b"\x00")


_CURVE_TEXT = {"1.2.840.10045.3.1.7": "secp256r1 [NIST P-256,X9.62 prime256v1]", "1.3.132.0.34": "secp384r1 [NIST P-384]",
               "1.3.132.0.35": "secp521r1 [NIST P-521]"}


def _key_text(key):
    if isinstance(key, RSAPublicKeyImpl):
        return "Sun RSA public key, %d bits\n  params: null\n  modulus: %d\n  public exponent: %d" % (
            key._n.bit_length(), key._n, key._x)
    if isinstance(key, ECPublicKeyImpl):
        return "Sun EC public key, %d bits\n  public x coord: %d\n  public y coord: %d\n  parameters: %s (%s)" % (
            _CURVES.get(key._curve_oid, (None, 0))[1], key._x, key._y, _CURVE_TEXT.get(key._curve_oid, key._curve_oid),
            key._curve_oid)
    return key.getAlgorithm() + " public key"


_EXTENSION_NAMES = {
    "2.5.29.35": "AuthorityKeyIdentifier", "2.5.29.19": "BasicConstraints", "2.5.29.14": "SubjectKeyIdentifier",
    "2.5.29.15": "KeyUsage", "2.5.29.37": "ExtendedKeyUsage", "2.5.29.17": "SubjectAlternativeName",
    "2.5.29.18": "IssuerAlternativeName", "2.5.29.31": "CRLDistributionPoints", "2.5.29.32": "CertificatePolicies",
    "2.5.29.30": "NameConstraints", "2.5.29.36": "PolicyConstraints", "2.5.29.33": "PolicyMappings",
    "2.5.29.54": "InhibitAnyPolicy", "1.3.6.1.5.5.7.1.1": "AuthorityInfoAccess", "1.3.6.1.5.5.7.1.11": "SubjectInfoAccess",
}


def _extension_text(oid, content):
    """the body of one extension: the jdk text for the common ones, a dump of the DER for the rest"""
    try:
        tag, cs, ce = der_read(content, 0, len(content))
        if oid == "2.5.29.19" and tag == 0x30:
            parts = der_children(content, cs, ce, 1)
            ca = bool(parts) and parts[0][0] == 0x01 and content[parts[0][1]:parts[0][2]] != b"\x00"
            length = [p for p in parts if p[0] == 0x02]
            return "BasicConstraints:[\n  CA:%s\n  PathLen: %s\n]\n" % (
                "true" if ca else "false", der_int(content, length[0][1], length[0][2]) if length else "no limit")
        if oid == "2.5.29.14" and tag == 0x04:
            return "SubjectKeyIdentifier [\nKeyIdentifier [\n%s]\n]\n" % _hex_dump(content[cs:ce])
        if oid == "2.5.29.35" and tag == 0x30:
            parts = der_children(content, cs, ce, 1)
            if len(parts) == 1 and parts[0][0] == 0x80:
                return "AuthorityKeyIdentifier [\nKeyIdentifier [\n%s]\n]\n" % _hex_dump(content[parts[0][1]:parts[0][2]])
    except DerError:
        pass
    return "Extension unknown: DER encoded OCTET string =\n%s\n" % _hex_dump(content_wrapped(content))


def content_wrapped(content):
    """the DER of an OCTET STRING holding the content"""
    return der_encode(0x04, content)


def _read_stream(stream):
    check_nonnull(stream)
    out = bytearray()
    buffer = runtime.new_array("[B", 8192)
    while True:
        count = stream.read(buffer, 0, 8192)
        if count is None or count < 0:
            return bytes(out)
        out.extend(b & 0xFF for b in buffer[:count])
        if len(out) > 16 * MAX_CERTIFICATE:
            _throw("java.io.IOException", "input is larger than %d bytes" % (16 * MAX_CERTIFICATE))


def split_certificates(data):
    """the DER of each certificate in PEM or DER input"""
    text = data.lstrip()
    if text[:1] == b"-":
        found = re.findall(rb"-----BEGIN (?:X509 |TRUSTED )?CERTIFICATE-----(.*?)-----END (?:X509 |TRUSTED )?CERTIFICATE-----", data, re.S)
        if not found:
            _cert_error("Could not parse certificate: java.io.IOException: Empty input")
        out = []
        for block in found:
            try:
                out.append(base64.b64decode(re.sub(rb"\s+", b"", block), validate=True))
            except ValueError:
                _cert_error("Could not parse certificate: java.io.IOException: Incomplete BER/DER data")
        return out
    out, pos = [], 0
    while pos < len(data):
        try:
            tag, cs, ce = der_read(data, pos, len(data))
        except DerError as error:
            _cert_error("Could not parse certificate: java.io.IOException: %s" % error)
        out.append(data[pos:ce])
        pos = ce
    if not out:
        _cert_error("Could not parse certificate: java.io.IOException: Empty input")
    return out


@host_class("java.security.cert.CertificateFactory")
class CertificateFactory(Object):
    def __init__(self, type_):
        self._type = type_

    @jstatic("getInstance", "(Ljava/lang/String;)Ljava/security/cert/CertificateFactory;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljava/security/cert/CertificateFactory;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/security/Provider;)Ljava/security/cert/CertificateFactory;")
    def getInstance(type_, provider=None):
        check_nonnull(type_)
        if type_.upper() not in ("X.509", "X509"):
            _cert_error("%s not found" % type_)
        return CertificateFactory("X.509")

    def getType(self):
        return self._type

    def generateCertificate(self, stream):
        data = _read_stream(stream)
        blocks = split_certificates(data)
        return X509CertImpl(blocks[0])

    def generateCertificates(self, stream):
        from .jmap import ArrayList
        found = ArrayList()
        for block in split_certificates(_read_stream(stream)):
            found.add(X509CertImpl(block))
        return found


@host_class("java.security.KeyStore$ProtectionParameter", interface=True)
class ProtectionParameter:
    __slots__ = ()


@host_class("java.security.KeyStore$Entry", interface=True)
class Entry:
    __slots__ = ()


@host_class("java.security.KeyStore$PasswordProtection", interfaces=("java.security.KeyStore$ProtectionParameter",))
class PasswordProtection(Object):
    def __init__(self, password):
        self._password = None if password is None else list(password)
        self._destroyed = False

    @jmethod("<init>", "([C)V")
    def _init(self, password):
        PasswordProtection.__init__(self, password)

    def getPassword(self):
        if self._destroyed:
            _throw("java.lang.IllegalStateException", "password has been cleared")
        return self._password

    def destroy(self):
        self._destroyed = True
        self._password = None

    def isDestroyed(self):
        return 1 if self._destroyed else 0


@host_class("java.security.KeyStore$TrustedCertificateEntry", interfaces=("java.security.KeyStore$Entry",))
class TrustedCertificateEntry(Object):
    def __init__(self, certificate):
        self._cert = check_nonnull(certificate)

    @jmethod("<init>", "(Ljava/security/cert/Certificate;)V")
    def _init(self, certificate):
        TrustedCertificateEntry.__init__(self, certificate)

    def getTrustedCertificate(self):
        return self._cert


@host_class("java.security.KeyStore$PrivateKeyEntry", interfaces=("java.security.KeyStore$Entry",))
class PrivateKeyEntry(Object):
    def __init__(self, key, chain):
        self._key, self._chain = check_nonnull(key), list(check_nonnull(chain))
        if not self._chain:
            _throw("java.lang.IllegalArgumentException", "invalid zero-length input chain")

    @jmethod("<init>", "(Ljava/security/PrivateKey;[Ljava/security/cert/Certificate;)V")
    def _init(self, key, chain):
        PrivateKeyEntry.__init__(self, key, chain)

    def getPrivateKey(self):
        return self._key

    def getCertificateChain(self):
        array = runtime.new_array("[Ljava/security/cert/Certificate;", 0)
        array.extend(self._chain)
        return array

    def getCertificate(self):
        return self._chain[0]


@host_class("java.security.KeyStore$SecretKeyEntry", interfaces=("java.security.KeyStore$Entry",))
class SecretKeyEntry(Object):
    def __init__(self, key):
        self._key = check_nonnull(key)

    @jmethod("<init>", "(Ljavax/crypto/SecretKey;)V")
    def _init(self, key):
        SecretKeyEntry.__init__(self, key)

    def getSecretKey(self):
        return self._key


_KEYSTORE_TYPES = {"PKCS12": "PKCS12", "JKS": "JKS", "BKS": "BKS", "JCEKS": "JCEKS", "PKCS12-3DES-3DES": "PKCS12", "BCPKCS12": "PKCS12"}


@host_class("java.security.KeyStore")
class KeyStore(Object):
    def __init__(self, type_):
        self._type = type_
        self._entries = {}
        self._loaded = False

    @jstatic("getDefaultType", "()Ljava/lang/String;")
    def getDefaultType():
        return "BKS"

    @jstatic("getInstance", "(Ljava/lang/String;)Ljava/security/KeyStore;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljava/security/KeyStore;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/security/Provider;)Ljava/security/KeyStore;")
    def getInstance(type_, provider=None):
        check_nonnull(type_)
        found = _KEYSTORE_TYPES.get(type_.upper())
        if found is None:
            _throw("java.security.KeyStoreException", "%s not found" % type_)
        return KeyStore(found)

    def getType(self):
        return self._type

    def _need_loaded(self):
        if not self._loaded:
            _throw("java.security.KeyStoreException", "Uninitialized keystore")

    def load(self, stream, password=None):
        if stream is not None:
            _throw("java.io.IOException", "a %s key store file cannot be read: this runtime has no password based encryption "
                   "for key store files" % self._type)
        self._entries = {}
        self._loaded = True

    def store(self, stream, password=None):
        self._need_loaded()
        _throw("java.io.IOException", "a %s key store file cannot be written by this runtime" % self._type)

    def size(self):
        self._need_loaded()
        return len(self._entries)

    def aliases(self):
        self._need_loaded()
        return PyIterator(list(self._entries))

    def containsAlias(self, alias):
        self._need_loaded()
        return 1 if check_nonnull(alias).lower() in self._entries else 0

    def _entry(self, alias):
        self._need_loaded()
        return self._entries.get(check_nonnull(alias).lower())

    def setCertificateEntry(self, alias, certificate):
        self._need_loaded()
        existing = self._entry(alias)
        if existing is not None and existing[0] != "cert":
            _throw("java.security.KeyStoreException", "Cannot overwrite own certificate")
        self._entries[alias.lower()] = ("cert", check_nonnull(certificate), None, None, int(time.time() * 1000))

    def setKeyEntry(self, alias, key, password, chain=None):
        self._need_loaded()
        check_nonnull(key)
        self._entries[alias.lower()] = ("key", key, list(chain) if chain is not None else None, password, int(time.time() * 1000))

    def getCertificate(self, alias):
        entry = self._entry(alias)
        if entry is None:
            return None
        if entry[0] == "cert":
            return entry[1]
        return entry[2][0] if entry[2] else None

    def getCertificateChain(self, alias):
        entry = self._entry(alias)
        if entry is None or entry[0] != "key" or not entry[2]:
            return None
        array = runtime.new_array("[Ljava/security/cert/Certificate;", 0)
        array.extend(entry[2])
        return array

    def getCertificateAlias(self, certificate):
        self._need_loaded()
        for alias, entry in self._entries.items():
            held = entry[1] if entry[0] == "cert" else (entry[2][0] if entry[2] else None)
            if held is not None and certificate is not None and held.equals(certificate):
                return jstr(alias)
        return None

    def getKey(self, alias, password):
        entry = self._entry(alias)
        if entry is None or entry[0] != "key":
            return None
        if entry[3] is not None and password is not None and list(password) != list(entry[3]):
            _throw("java.security.UnrecoverableKeyException", "Cannot recover key")
        return entry[1]

    def isCertificateEntry(self, alias):
        entry = self._entry(alias)
        return 1 if entry is not None and entry[0] == "cert" else 0

    def isKeyEntry(self, alias):
        entry = self._entry(alias)
        return 1 if entry is not None and entry[0] == "key" else 0

    def deleteEntry(self, alias):
        self._need_loaded()
        self._entries.pop(check_nonnull(alias).lower(), None)

    def getCreationDate(self, alias):
        entry = self._entry(alias)
        return None if entry is None else lookup_host("java.util.Date").py(entry[4])

    def getEntry(self, alias, protection=None):
        entry = self._entry(alias)
        if entry is None:
            return None
        if entry[0] == "cert":
            return TrustedCertificateEntry(entry[1])
        if hasattr(entry[1], "getEncoded") and entry[2]:
            return PrivateKeyEntry(entry[1], entry[2])
        return SecretKeyEntry(entry[1])

    def setEntry(self, alias, entry, protection=None):
        self._need_loaded()
        if isinstance(entry, TrustedCertificateEntry):
            self._entries[alias.lower()] = ("cert", entry._cert, None, None, int(time.time() * 1000))
        elif isinstance(entry, PrivateKeyEntry):
            password = protection.getPassword() if protection is not None else None
            self._entries[alias.lower()] = ("key", entry._key, entry._chain, password, int(time.time() * 1000))
        else:
            self._entries[alias.lower()] = ("key", entry._key, None, None, int(time.time() * 1000))

    def entryInstanceOf(self, alias, entry_class):
        entry = self._entry(alias)
        if entry is None:
            return 0
        wanted = entry_class.getName()
        kind = {"cert": "TrustedCertificateEntry", "key": "PrivateKeyEntry"}[entry[0]]
        return 1 if wanted.endswith("$" + kind) or wanted.endswith("$Entry") else 0
