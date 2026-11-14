"""java.math, digests, base64 and checksums over the python standard library

BigInteger is a python int. BigDecimal keeps an unscaled int and a scale and rounds with the RoundingMode it is given.
ciphers (javax.crypto.Cipher) are not here: the standard library has no AES, and the vm does not ship one"""

import base64
import hashlib
import hmac
import os
import zlib

from . import runtime
from .api import host_class, jmethod, jstatic
from .jfunc import jequals
from .jio import ByteArrayInputStream, ByteArrayOutputStream, FilterInputStream, InputStream, OutputStream, to_java_bytes, to_py_bytes
from .jlang import Enum, Number, Object, Integer, Long, _StringImpl, jstr, pystr
from .jutil import check_nonnull


def _bad(message):
    runtime.throw_new("java.lang.ArithmeticException", message)


@host_class("java.math.BigInteger", interfaces=("java.lang.Comparable", "java.io.Serializable"))
class BigInteger(Number):
    def __init__(self, value=0, radix=10):
        if isinstance(value, str):
            try:
                value = int(value, radix)
            except ValueError:
                runtime.throw_new("java.lang.NumberFormatException", 'For input string: "%s"' % value)
        self._v = int(value)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;I)V")
    def _init(self, text, radix=10):
        BigInteger.__init__(self, check_nonnull(text), radix)

    @jmethod("<init>", "(I[B)V")
    def _init_signum(self, signum, magnitude):
        BigInteger.__init__(self, signum * int.from_bytes(to_py_bytes(magnitude), "big"))

    @jmethod("<init>", "([B)V")
    def _init_bytes(self, data):
        BigInteger.__init__(self, int.from_bytes(to_py_bytes(data), "big", signed=True))

    @jstatic("valueOf", "(J)Ljava/math/BigInteger;")
    def valueOf(value):
        return BigInteger(value)

    def __eq__(self, other):
        return self is other

    __hash__ = object.__hash__

    @jmethod("add", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def add(self, other):
        return BigInteger(self._v + other._v)

    @jmethod("subtract", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def subtract(self, other):
        return BigInteger(self._v - other._v)

    @jmethod("multiply", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def multiply(self, other):
        return BigInteger(self._v * other._v)

    @jmethod("divide", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def divide(self, other):
        if other._v == 0:
            _bad("BigInteger divide by zero")
        q = abs(self._v) // abs(other._v)
        return BigInteger(-q if (self._v < 0) != (other._v < 0) else q)

    @jmethod("remainder", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def remainder(self, other):
        if other._v == 0:
            _bad("BigInteger divide by zero")
        r = abs(self._v) % abs(other._v)
        return BigInteger(-r if self._v < 0 else r)

    @jmethod("mod", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def mod(self, other):
        if other._v <= 0:
            _bad("BigInteger: modulus not positive")
        return BigInteger(self._v % other._v)

    @jmethod("pow", "(I)Ljava/math/BigInteger;")
    def pow(self, exponent):
        if exponent < 0:
            _bad("Negative exponent")
        return BigInteger(self._v ** exponent)

    @jmethod("modPow", "(Ljava/math/BigInteger;Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def modPow(self, exponent, modulus):
        if modulus._v <= 0:
            _bad("BigInteger: modulus not positive")
        return BigInteger(pow(self._v, exponent._v, modulus._v))

    @jmethod("modInverse", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def modInverse(self, modulus):
        try:
            return BigInteger(pow(self._v, -1, modulus._v))
        except ValueError:
            _bad("BigInteger not invertible.")

    @jmethod("gcd", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def gcd(self, other):
        import math
        return BigInteger(math.gcd(self._v, other._v))

    @jmethod("negate", "()Ljava/math/BigInteger;")
    def negate(self):
        return BigInteger(-self._v)

    @jmethod("abs", "()Ljava/math/BigInteger;")
    def abs(self):
        return BigInteger(abs(self._v))

    @jmethod("signum", "()I")
    def signum(self):
        return (self._v > 0) - (self._v < 0)

    @jmethod("and", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def and_(self, other):
        return BigInteger(self._v & other._v)

    @jmethod("or", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def or_(self, other):
        return BigInteger(self._v | other._v)

    @jmethod("xor", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def xor(self, other):
        return BigInteger(self._v ^ other._v)

    @jmethod("not", "()Ljava/math/BigInteger;")
    def not_(self):
        return BigInteger(~self._v)

    @jmethod("shiftLeft", "(I)Ljava/math/BigInteger;")
    def shiftLeft(self, n):
        return BigInteger(self._v << n if n >= 0 else self._v >> -n)

    @jmethod("shiftRight", "(I)Ljava/math/BigInteger;")
    def shiftRight(self, n):
        return BigInteger(self._v >> n if n >= 0 else self._v << -n)

    @jmethod("testBit", "(I)Z")
    def testBit(self, n):
        return (self._v >> n) & 1

    @jmethod("bitLength", "()I")
    def bitLength(self):
        return (self._v if self._v >= 0 else ~self._v).bit_length()

    @jmethod("bitCount", "()I")
    def bitCount(self):
        return bin(self._v if self._v >= 0 else ~self._v).count("1")

    @jmethod("compareTo", "(Ljava/math/BigInteger;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        return (self._v > other._v) - (self._v < other._v)

    @jmethod("max", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def max(self, other):
        return self if self._v >= other._v else other

    @jmethod("min", "(Ljava/math/BigInteger;)Ljava/math/BigInteger;")
    def min(self, other):
        return self if self._v <= other._v else other

    @jmethod("isProbablePrime", "(I)Z")
    def isProbablePrime(self, certainty):
        n = self._v
        if n < 2:
            return 0
        for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
            if n % p == 0:
                return 1 if n == p else 0
        d, r = n - 1, 0
        while d % 2 == 0:
            d //= 2
            r += 1
        for a in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
            x = pow(a, d, n)
            if x in (1, n - 1):
                continue
            for _ in range(r - 1):
                x = x * x % n
                if x == n - 1:
                    break
            else:
                return 0
        return 1

    @jmethod("intValue", "()I")
    def intValue(self):
        return runtime.wrap32(self._v)

    @jmethod("longValue", "()J")
    def longValue(self):
        return runtime.wrap64(self._v)

    @jmethod("doubleValue", "()D")
    def doubleValue(self):
        try:
            return float(self._v)
        except OverflowError:
            return float("inf") if self._v > 0 else float("-inf")

    @jmethod("floatValue", "()F")
    def floatValue(self):
        return runtime.f32(self.doubleValue())

    @jmethod("longValueExact", "()J")
    def longValueExact(self):
        if not runtime.LONG_MIN <= self._v <= runtime.LONG_MAX:
            _bad("BigInteger out of long range")
        return self._v

    @jmethod("intValueExact", "()I")
    def intValueExact(self):
        if not runtime.INT_MIN <= self._v <= runtime.INT_MAX:
            _bad("BigInteger out of int range")
        return self._v

    @jmethod("toByteArray", "()[B")
    def toByteArray(self):
        length = (self.bitLength() // 8) + 1
        return to_java_bytes(self._v.to_bytes(length, "big", signed=True))

    @jmethod("toString", "()Ljava/lang/String;")
    @jmethod("toString", "(I)Ljava/lang/String;")
    def toString(self, radix=10):
        from .jlang import _to_radix
        return str(self._v) if radix == 10 else _to_radix(self._v, radix)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, BigInteger) and other._v == self._v else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        magnitude = abs(self._v)
        h = 0
        words = []
        while magnitude:
            words.append(magnitude & 0xFFFFFFFF)
            magnitude >>= 32
        for word in reversed(words):
            h = (31 * h + word) & 0xFFFFFFFF
        h = runtime.wrap32(h)
        return runtime.wrap32(h * ((self._v > 0) - (self._v < 0)))


BigInteger.ZERO = BigInteger(0)
BigInteger.ONE = BigInteger(1)
BigInteger.TWO = BigInteger(2)
BigInteger.TEN = BigInteger(10)


@host_class("java.math.RoundingMode", final=True)
class RoundingMode(Enum):
    pass


for _index, _name in enumerate(("UP", "DOWN", "CEILING", "FLOOR", "HALF_UP", "HALF_DOWN", "HALF_EVEN", "UNNECESSARY")):
    _mode = RoundingMode.__new__(RoundingMode)
    _mode._name = _name
    _mode._ordinal = _index
    setattr(RoundingMode, _name, _mode)


def _divide_round(numerator, denominator, mode):
    """numerator / denominator rounded to an int with a java RoundingMode"""
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    quotient, remainder = divmod(numerator, denominator)
    if remainder == 0:
        return quotient
    name = mode._name
    negative = numerator < 0
    twice = 2 * abs(remainder) if not negative else 2 * (denominator - remainder)
    # quotient is floored; remainder in [0, denominator)
    if name == "UNNECESSARY":
        _bad("Rounding necessary")
    if name == "FLOOR":
        return quotient
    if name == "CEILING":
        return quotient + 1
    if name == "DOWN":
        return quotient + 1 if negative else quotient
    if name == "UP":
        return quotient if negative else quotient + 1
    half = 2 * remainder - denominator
    if half > 0:
        return quotient + 1
    if half < 0:
        return quotient
    if name == "HALF_UP":
        return quotient if negative else quotient + 1
    if name == "HALF_DOWN":
        return quotient + 1 if negative else quotient
    return quotient + (quotient & 1)


@host_class("java.math.BigDecimal", interfaces=("java.lang.Comparable",))
class BigDecimal(Number):
    def __init__(self, unscaled=0, scale=0):
        self._u = unscaled
        self._s = scale

    @staticmethod
    def _parse(text):
        text = text.strip()
        try:
            mantissa, _, exponent = text.lower().partition("e")
            sign = -1 if mantissa.startswith("-") else 1
            mantissa = mantissa.lstrip("+-")
            integer, _, fraction = mantissa.partition(".")
            if not (integer + fraction).isdigit():
                raise ValueError(text)
            return BigDecimal(sign * int(integer + fraction), len(fraction) - (int(exponent) if exponent else 0))
        except ValueError:
            runtime.throw_new("java.lang.NumberFormatException", None)

    @jmethod("longValueExact", "()J")
    def longValueExact(self):
        value = self._u / (10 ** self._s) if self._s >= 0 else self._u * 10 ** -self._s
        whole = self._u // 10 ** self._s if self._s >= 0 else self._u * 10 ** -self._s
        if self._s > 0 and self._u % 10 ** self._s:
            runtime.throw_new("java.lang.ArithmeticException", "Rounding necessary")
        if not -0x8000000000000000 <= whole <= 0x7FFFFFFFFFFFFFFF:
            runtime.throw_new("java.lang.ArithmeticException", "Overflow")
        return whole

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, text):
        parsed = BigDecimal._parse(check_nonnull(text))
        self._u, self._s = parsed._u, parsed._s

    @jmethod("<init>", "(D)V")
    def _init_double(self, value):
        from fractions import Fraction
        if value != value or value in (float("inf"), float("-inf")):
            runtime.throw_new("java.lang.NumberFormatException", "Infinite or NaN")
        exact = Fraction(value)
        scale = 0
        while exact.denominator != 1:
            exact *= 10
            scale += 1
        self._u, self._s = int(exact), scale

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(J)V")
    def _init_int(self, value):
        self._u, self._s = value, 0

    @jmethod("<init>", "(Ljava/math/BigInteger;)V")
    def _init_big(self, value):
        self._u, self._s = value._v, 0

    @jmethod("<init>", "(Ljava/math/BigInteger;I)V")
    def _init_big_scale(self, value, scale):
        self._u, self._s = value._v, scale

    @jstatic("valueOf", "(J)Ljava/math/BigDecimal;")
    def valueOf(value):
        return BigDecimal(value, 0)

    @jstatic("valueOf", "(JI)Ljava/math/BigDecimal;")
    def valueOf_scaled(value, scale):
        return BigDecimal(value, scale)

    @jstatic("valueOf", "(D)Ljava/math/BigDecimal;")
    def valueOf_double(value):
        from .jlang import float_to_string
        return BigDecimal._parse(float_to_string(value, False))

    def __eq__(self, other):
        return self is other

    __hash__ = object.__hash__

    def _aligned(self, other):
        scale = max(self._s, other._s)
        return self._u * 10 ** (scale - self._s), other._u * 10 ** (scale - other._s), scale

    @jmethod("add", "(Ljava/math/BigDecimal;)Ljava/math/BigDecimal;")
    def add(self, other):
        a, b, scale = self._aligned(other)
        return BigDecimal(a + b, scale)

    @jmethod("subtract", "(Ljava/math/BigDecimal;)Ljava/math/BigDecimal;")
    def subtract(self, other):
        a, b, scale = self._aligned(other)
        return BigDecimal(a - b, scale)

    @jmethod("multiply", "(Ljava/math/BigDecimal;)Ljava/math/BigDecimal;")
    def multiply(self, other):
        return BigDecimal(self._u * other._u, self._s + other._s)

    @jmethod("divide", "(Ljava/math/BigDecimal;)Ljava/math/BigDecimal;")
    @jmethod("divide", "(Ljava/math/BigDecimal;Ljava/math/RoundingMode;)Ljava/math/BigDecimal;")
    @jmethod("divide", "(Ljava/math/BigDecimal;ILjava/math/RoundingMode;)Ljava/math/BigDecimal;")
    def divide(self, other, first=None, second=None):
        if other._u == 0:
            _bad("Division by zero" if self._u else "Division undefined")
        if first is None:
            from fractions import Fraction
            ratio = Fraction(self._u, other._u)
            denominator = ratio.denominator
            while denominator % 2 == 0:
                denominator //= 2
            while denominator % 5 == 0:
                denominator //= 5
            if denominator != 1:
                _bad("Non-terminating decimal expansion; no exact representable decimal result.")
            scale = self._s - other._s
            while ratio.denominator != 1:
                ratio *= 10
                scale += 1
            return BigDecimal(int(ratio), scale)
        if isinstance(first, RoundingMode):
            mode, scale = first, self._s
        else:
            scale, mode = first, second
        shift = scale - (self._s - other._s)
        numerator = self._u * 10 ** shift if shift >= 0 else self._u
        denominator = other._u if shift >= 0 else other._u * 10 ** -shift
        return BigDecimal(_divide_round(numerator, denominator, mode), scale)

    @jmethod("setScale", "(I)Ljava/math/BigDecimal;")
    @jmethod("setScale", "(ILjava/math/RoundingMode;)Ljava/math/BigDecimal;")
    def setScale(self, scale, mode=None):
        mode = mode or RoundingMode.UNNECESSARY
        if scale >= self._s:
            return BigDecimal(self._u * 10 ** (scale - self._s), scale)
        return BigDecimal(_divide_round(self._u, 10 ** (self._s - scale), mode), scale)

    @jmethod("negate", "()Ljava/math/BigDecimal;")
    def negate(self):
        return BigDecimal(-self._u, self._s)

    @jmethod("abs", "()Ljava/math/BigDecimal;")
    def abs(self):
        return BigDecimal(abs(self._u), self._s)

    @jmethod("signum", "()I")
    def signum(self):
        return (self._u > 0) - (self._u < 0)

    @jmethod("scale", "()I")
    def scale(self):
        return self._s

    @jmethod("precision", "()I")
    def precision(self):
        return len(str(abs(self._u))) if self._u else 1

    @jmethod("unscaledValue", "()Ljava/math/BigInteger;")
    def unscaledValue(self):
        return BigInteger(self._u)

    @jmethod("stripTrailingZeros", "()Ljava/math/BigDecimal;")
    def stripTrailingZeros(self):
        if self._u == 0:
            return BigDecimal(0, 0)
        u, s = self._u, self._s
        while u % 10 == 0:
            u //= 10
            s -= 1
        return BigDecimal(u, s)

    @jmethod("pow", "(I)Ljava/math/BigDecimal;")
    def pow(self, n):
        return BigDecimal(self._u ** n, self._s * n)

    @jmethod("compareTo", "(Ljava/math/BigDecimal;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        a, b, _ = self._aligned(other)
        return (a > b) - (a < b)

    @jmethod("max", "(Ljava/math/BigDecimal;)Ljava/math/BigDecimal;")
    def max(self, other):
        return self if self.compareTo(other) >= 0 else other

    @jmethod("min", "(Ljava/math/BigDecimal;)Ljava/math/BigDecimal;")
    def min(self, other):
        return self if self.compareTo(other) <= 0 else other

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, BigDecimal) and other._u == self._u and other._s == self._s else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return runtime.wrap32(31 * BigInteger(self._u).hashCode() + self._s)

    @jmethod("intValue", "()I")
    def intValue(self):
        return runtime.wrap32(self.toBigInteger()._v)

    @jmethod("longValue", "()J")
    def longValue(self):
        return runtime.wrap64(self.toBigInteger()._v)

    @jmethod("doubleValue", "()D")
    def doubleValue(self):
        return float(self.toPlainString())

    @jmethod("floatValue", "()F")
    def floatValue(self):
        return runtime.f32(self.doubleValue())

    @jmethod("toBigInteger", "()Ljava/math/BigInteger;")
    def toBigInteger(self):
        if self._s <= 0:
            return BigInteger(self._u * 10 ** -self._s)
        q = abs(self._u) // 10 ** self._s
        return BigInteger(-q if self._u < 0 else q)

    @jmethod("toPlainString", "()Ljava/lang/String;")
    def toPlainString(self):
        digits = str(abs(self._u))
        sign = "-" if self._u < 0 else ""
        if self._s <= 0:
            return sign + digits + ("0" * -self._s if self._u else "")
        if len(digits) <= self._s:
            digits = "0" * (self._s - len(digits) + 1) + digits
        return sign + digits[:-self._s] + "." + digits[-self._s:]

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        if self._s == 0:
            return str(self._u)
        digits = str(abs(self._u))
        adjusted = -self._s + len(digits) - 1
        if self._s >= 0 and adjusted >= -6:
            return self.toPlainString()
        sign = "-" if self._u < 0 else ""
        body = digits[0] + ("." + digits[1:] if len(digits) > 1 else "")
        return "%s%sE%s%d" % (sign, body, "+" if adjusted >= 0 else "-", abs(adjusted))


BigDecimal.ZERO = BigDecimal(0, 0)
BigDecimal.ONE = BigDecimal(1, 0)
BigDecimal.TEN = BigDecimal(10, 0)


@host_class("java.security.MessageDigest")
class MessageDigest(Object):
    _NAMES = {"md5": "md5", "sha-1": "sha1", "sha1": "sha1", "sha-224": "sha224", "sha-256": "sha256",
              "sha-384": "sha384", "sha-512": "sha512", "sha3-256": "sha3_256", "sha3-512": "sha3_512"}

    def __init__(self, name):
        self._name = name
        self._h = hashlib.new(MessageDigest._NAMES[name.lower()])

    @jstatic("getInstance", "(Ljava/lang/String;)Ljava/security/MessageDigest;")
    def getInstance(name):
        if name.lower() not in MessageDigest._NAMES:
            runtime.throw_new("java.security.NoSuchAlgorithmException", "%s MessageDigest not available" % name)
        return MessageDigest(name)

    @jmethod("update", "([B)V")
    @jmethod("update", "([BII)V")
    def update(self, data, offset=0, length=None):
        self._h.update(to_py_bytes(data, offset, length))

    @jmethod("update", "(B)V")
    def update_byte(self, value):
        self._h.update(bytes((value & 0xFF,)))

    @jmethod("digest", "()[B")
    @jmethod("digest", "([B)[B")
    def digest(self, data=None):
        if data is not None:
            self.update(data)
        result = to_java_bytes(self._h.digest())
        self._h = hashlib.new(MessageDigest._NAMES[self._name.lower()])
        return result

    @jmethod("reset", "()V")
    def reset(self):
        self._h = hashlib.new(MessageDigest._NAMES[self._name.lower()])

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return self._name

    @jmethod("getDigestLength", "()I")
    def getDigestLength(self):
        return self._h.digest_size

    @jstatic("isEqual", "([B[B)Z")
    def isEqual(a, b):
        return 1 if hmac.compare_digest(to_py_bytes(a), to_py_bytes(b)) else 0


@host_class("javax.crypto.spec.SecretKeySpec", interfaces=("java.security.Key",))
class SecretKeySpec(Object):
    def __init__(self, key, algorithm):
        self._k = to_py_bytes(key)
        self._a = algorithm

    @jmethod("<init>", "([BLjava/lang/String;)V")
    def _init(self, key, algorithm):
        SecretKeySpec.__init__(self, key, algorithm)

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return self._a

    @jmethod("getEncoded", "()[B")
    def getEncoded(self):
        return to_java_bytes(self._k)


host_class("java.security.Key", interface=True)(type("Key", (), {"__slots__": ()}))


@host_class("javax.crypto.Mac")
class Mac(Object):
    _NAMES = {"hmacmd5": "md5", "hmacsha1": "sha1", "hmacsha224": "sha224", "hmacsha256": "sha256",
              "hmacsha384": "sha384", "hmacsha512": "sha512"}

    def __init__(self, name):
        self._name = name
        self._digest = Mac._NAMES[name.lower()]
        self._h = None

    @jstatic("getInstance", "(Ljava/lang/String;)Ljavax/crypto/Mac;")
    def getInstance(name):
        if name.lower() not in Mac._NAMES:
            runtime.throw_new("java.security.NoSuchAlgorithmException", "Algorithm %s not available" % name)
        return Mac(name)

    @jmethod("init", "(Ljava/security/Key;)V")
    def init(self, key):
        self._key = key._k
        self._h = hmac.new(self._key, digestmod=self._digest)

    def _ready(self):
        if self._h is None:
            runtime.throw_new("java.lang.IllegalStateException", "MAC not initialized")

    @jmethod("update", "([B)V")
    @jmethod("update", "([BII)V")
    def update(self, data, offset=0, length=None):
        self._ready()
        self._h.update(to_py_bytes(data, offset, length))

    @jmethod("doFinal", "()[B")
    @jmethod("doFinal", "([B)[B")
    def doFinal(self, data=None):
        self._ready()
        if data is not None:
            self._h.update(to_py_bytes(data))
        result = to_java_bytes(self._h.digest())
        self._h = hmac.new(self._key, digestmod=self._digest)
        return result

    @jmethod("getMacLength", "()I")
    def getMacLength(self):
        return hashlib.new(self._digest).digest_size


@host_class("java.security.SecureRandom")
class SecureRandom(Object):
    def __init__(self, seed=None):
        pass

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("nextBytes", "([B)V")
    def nextBytes(self, target):
        target[:] = [b - 256 if b > 127 else b for b in os.urandom(len(target))]

    @jmethod("nextInt", "()I")
    @jmethod("nextInt", "(I)I")
    def nextInt(self, bound=None):
        value = int.from_bytes(os.urandom(4), "big", signed=True)
        if bound is None:
            return value
        if bound <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "bound must be positive")
        return (value & 0x7FFFFFFF) % bound

    @jmethod("nextLong", "()J")
    def nextLong(self):
        return int.from_bytes(os.urandom(8), "big", signed=True)

    @jmethod("nextDouble", "()D")
    def nextDouble(self):
        return (int.from_bytes(os.urandom(8), "big") >> 11) * (1.0 / (1 << 53))

    @jmethod("nextBoolean", "()Z")
    def nextBoolean(self):
        return os.urandom(1)[0] & 1


@host_class("java.util.Base64", final=True)
class Base64(Object):
    def __init__(self, kind):
        self._kind = kind

    @jstatic("getEncoder", "()Ljava/util/Base64$Encoder;")
    def getEncoder():
        return Base64Encoder("std", True)

    @jstatic("getUrlEncoder", "()Ljava/util/Base64$Encoder;")
    def getUrlEncoder():
        return Base64Encoder("url", True)

    @jstatic("getMimeEncoder", "()Ljava/util/Base64$Encoder;")
    def getMimeEncoder():
        return Base64Encoder("mime", True)

    @jstatic("getDecoder", "()Ljava/util/Base64$Decoder;")
    def getDecoder():
        return Base64Decoder("std")

    @jstatic("getUrlDecoder", "()Ljava/util/Base64$Decoder;")
    def getUrlDecoder():
        return Base64Decoder("url")

    @jstatic("getMimeDecoder", "()Ljava/util/Base64$Decoder;")
    def getMimeDecoder():
        return Base64Decoder("mime")


@host_class("java.util.Base64$Encoder")
class Base64Encoder(Object):
    def __init__(self, kind, padding):
        self._kind, self._padding = kind, padding

    @jmethod("encode", "([B)[B")
    def encode(self, data):
        return to_java_bytes(self._encode(to_py_bytes(data)).encode("ascii"))

    @jmethod("encodeToString", "([B)Ljava/lang/String;")
    def encodeToString(self, data):
        return self._encode(to_py_bytes(data))

    def _encode(self, data):
        text = (base64.urlsafe_b64encode if self._kind == "url" else base64.b64encode)(data).decode("ascii")
        if not self._padding:
            text = text.rstrip("=")
        if self._kind == "mime":
            text = "\r\n".join(text[i:i + 76] for i in range(0, len(text), 76))
        return text

    @jmethod("withoutPadding", "()Ljava/util/Base64$Encoder;")
    def withoutPadding(self):
        return Base64Encoder(self._kind, False)


@host_class("java.util.Base64$Decoder")
class Base64Decoder(Object):
    def __init__(self, kind):
        self._kind = kind

    @jmethod("decode", "([B)[B")
    @jmethod("decode", "(Ljava/lang/String;)[B")
    def decode(self, data):
        text = data if isinstance(data, str) else to_py_bytes(data).decode("latin-1")
        if self._kind == "mime":
            text = "".join(c for c in text if c.isalnum() or c in "+/=")
        text = text.replace("\n", "") if self._kind == "mime" else text
        alphabet = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789=" + ("-_" if self._kind == "url" else "+/"))
        if any(c not in alphabet for c in text):
            runtime.throw_new("java.lang.IllegalArgumentException", "Illegal base64 character")
        stripped = text.rstrip("=")
        if len(text) - len(stripped) > 2 or "=" in stripped:
            runtime.throw_new("java.lang.IllegalArgumentException", "Input byte array has incorrect ending byte")
        if len(stripped) % 4 == 1:
            runtime.throw_new("java.lang.IllegalArgumentException", "Last unit does not have enough valid bits")
        padded = stripped + "=" * (-len(stripped) % 4)
        decoder = base64.urlsafe_b64decode if self._kind == "url" else base64.b64decode
        return to_java_bytes(decoder(padded))


@host_class("java.util.zip.Checksum", interface=True)
class Checksum:
    __slots__ = ()


@host_class("java.util.zip.CRC32", interfaces=("java.util.zip.Checksum",))
class CRC32(Object):
    def __init__(self):
        self._v = 0

    @jmethod("<init>", "()V")
    def _init(self):
        self._v = 0

    @jmethod("update", "(I)V")
    def update_byte(self, value):
        self._v = zlib.crc32(bytes((value & 0xFF,)), self._v)

    @jmethod("update", "([B)V")
    @jmethod("update", "([BII)V")
    def update(self, data, offset=0, length=None):
        self._v = zlib.crc32(to_py_bytes(data, offset, length), self._v)

    @jmethod("getValue", "()J")
    def getValue(self):
        return self._v & 0xFFFFFFFF

    @jmethod("reset", "()V")
    def reset(self):
        self._v = 0


@host_class("java.util.zip.Adler32", interfaces=("java.util.zip.Checksum",))
class Adler32(CRC32):
    def __init__(self):
        self._v = 1

    @jmethod("update", "([B)V")
    @jmethod("update", "([BII)V")
    def update(self, data, offset=0, length=None):
        self._v = zlib.adler32(to_py_bytes(data, offset, length), self._v)

    @jmethod("reset", "()V")
    def reset(self):
        self._v = 1


@host_class("java.util.zip.Deflater")
class Deflater(Object):
    def __init__(self, level=-1, nowrap=False):
        self._level = level
        self._nowrap = nowrap
        self._c = zlib.compressobj(level, zlib.DEFLATED, -15 if nowrap else 15)
        self._in = bytearray()
        self._out = bytearray()
        self._finish = False
        self._done = False

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(IZ)V")
    def _init(self, level=-1, nowrap=False):
        Deflater.__init__(self, level, nowrap)

    @jmethod("setLevel", "(I)V")
    def setLevel(self, level):
        if level < -1 or level > 9:
            runtime.throw_new("java.lang.IllegalArgumentException", "invalid compression level")
        self._level = level
        self._c = zlib.compressobj(level, zlib.DEFLATED, -15 if self._nowrap else 15)

    @jmethod("setInput", "([B)V")
    @jmethod("setInput", "([BII)V")
    def setInput(self, data, offset=0, length=None):
        self._in += to_py_bytes(data, offset, length)

    @jmethod("finish", "()V")
    def finish(self):
        self._finish = True

    @jmethod("deflate", "([B)I")
    @jmethod("deflate", "([BII)I")
    def deflate(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        if self._in:
            self._out += self._c.compress(bytes(self._in))
            self._in.clear()
        if self._finish and not self._done:
            self._out += self._c.flush()
            self._done = True
        chunk = self._out[:length]
        del self._out[:length]
        buffer[offset:offset + len(chunk)] = [b - 256 if b > 127 else b for b in chunk]
        return len(chunk)

    @jmethod("finished", "()Z")
    def finished(self):
        return 1 if self._done and not self._out else 0

    @jmethod("needsInput", "()Z")
    def needsInput(self):
        return 0 if self._in else 1

    @jmethod("end", "()V")
    @jmethod("reset", "()V")
    def end(self):
        return None


@host_class("java.util.zip.Inflater")
class Inflater(Object):
    def __init__(self, nowrap=False):
        self._d = zlib.decompressobj(-15 if nowrap else 15)
        self._out = bytearray()
        self._finished = False

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Z)V")
    def _init(self, nowrap=False):
        Inflater.__init__(self, nowrap)

    @jmethod("setInput", "([B)V")
    @jmethod("setInput", "([BII)V")
    def setInput(self, data, offset=0, length=None):
        try:
            self._out += self._d.decompress(to_py_bytes(data, offset, length))
        except zlib.error as error:
            runtime.throw_new("java.util.zip.DataFormatException", str(error))
        self._finished = self._d.eof

    @jmethod("inflate", "([B)I")
    @jmethod("inflate", "([BII)I")
    def inflate(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        chunk = self._out[:length]
        del self._out[:length]
        buffer[offset:offset + len(chunk)] = [b - 256 if b > 127 else b for b in chunk]
        return len(chunk)

    @jmethod("finished", "()Z")
    def finished(self):
        return 1 if self._finished and not self._out else 0

    @jmethod("needsInput", "()Z")
    def needsInput(self):
        return 0 if self._out else 1

    @jmethod("end", "()V")
    def end(self):
        return None


@host_class("java.util.zip.GZIPOutputStream")
class GZIPOutputStream(OutputStream):
    def __init__(self, sink, size=512):
        self._sink = sink
        self._buf = bytearray()

    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;I)V")
    def _init(self, sink, size=512):
        GZIPOutputStream.__init__(self, sink)

    def write_byte(self, value):
        self._buf.append(value & 0xFF)

    def write(self, buffer, offset=0, length=None):
        self._buf += to_py_bytes(buffer, offset, length)

    @jmethod("finish", "()V")
    def finish(self):
        import gzip
        data = gzip.compress(bytes(self._buf), mtime=0)
        self._buf.clear()
        self._sink.write(to_java_bytes(data), 0, len(data))

    def close(self):
        self.finish()
        self._sink.close()


@host_class("java.util.zip.GZIPInputStream")
class GZIPInputStream(ByteArrayInputStream):
    def __init__(self, source, size=512):
        import gzip
        raw = source.readAllBytes()
        try:
            data = gzip.decompress(to_py_bytes(raw))
        except (OSError, EOFError, zlib.error) as error:
            runtime.throw_new("java.util.zip.ZipException", "Not in GZIP format" if isinstance(error, OSError) else str(error))
        ByteArrayInputStream.__init__(self, to_java_bytes(data))

    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;I)V")
    def _init(self, source, size=512):
        GZIPInputStream.__init__(self, source)
