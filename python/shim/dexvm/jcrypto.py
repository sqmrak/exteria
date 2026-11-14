"""javax.crypto and java.security beyond digests and macs: Cipher (AES in ECB, CBC, CTR and GCM; RSA with PKCS1 and OAEP), KeyGenerator,
SecretKeyFactory (PBKDF2), KeyFactory and KeyPairGenerator for RSA, Signature (SHA-1, SHA-256, SHA-384 and SHA-512 with RSA), the parameter and key
specs, and the exceptions and marker types around them

the ciphers are written in python: AES and RSA here are for keys and messages of a plugin (settings, tokens, small files), not for megabytes. an
algorithm that is not here (EC, ChaCha20, DES, a provider name) is a NoSuchAlgorithmException by name. the keys come from os.urandom; a
KeyPairGenerator for RSA 2048 needs seconds on a phone, and 4096 minutes"""

import hashlib
import hmac as _hmac
import os
import struct

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jio import to_java_bytes, to_py_bytes
from .jlang import Object
from .jnum import BigInteger
from .jutil import check_nonnull


def _taken(name):
    from . import api
    return name in api._classes or api._lazy.get(name, "dexvm.jcrypto") != "dexvm.jcrypto"


def _define(table):
    for line in table.strip().splitlines():
        name, parent = line.split()
        if not _taken(name):
            host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


def _interfaces(table):
    for line in table.strip().splitlines():
        name, *parents = line.split()
        if not _taken(name):
            host_class(name, interface=True, interfaces=tuple(parents))(type(name.rsplit(".", 1)[1], (), {"__slots__": ()}))


_define("""
java.security.KeyException java.security.GeneralSecurityException
java.security.KeyManagementException java.security.KeyException
java.security.KeyStoreException java.security.GeneralSecurityException
java.security.NoSuchProviderException java.security.GeneralSecurityException
java.security.InvalidAlgorithmParameterException java.security.GeneralSecurityException
java.security.InvalidParameterException java.lang.IllegalArgumentException
java.security.ProviderException java.lang.RuntimeException
java.security.UnrecoverableEntryException java.security.GeneralSecurityException
java.security.UnrecoverableKeyException java.security.UnrecoverableEntryException
java.security.AccessControlException java.lang.SecurityException
java.security.PrivilegedActionException java.lang.Exception
java.security.spec.InvalidKeySpecException java.security.GeneralSecurityException
java.security.spec.InvalidParameterSpecException java.security.GeneralSecurityException
javax.crypto.BadPaddingException java.security.GeneralSecurityException
javax.crypto.AEADBadTagException javax.crypto.BadPaddingException
javax.crypto.IllegalBlockSizeException java.security.GeneralSecurityException
javax.crypto.NoSuchPaddingException java.security.GeneralSecurityException
javax.crypto.ShortBufferException java.security.GeneralSecurityException
javax.crypto.ExemptionMechanismException java.security.GeneralSecurityException
""")

_interfaces("""
java.security.PublicKey java.security.Key
java.security.PrivateKey java.security.Key
javax.crypto.SecretKey java.security.Key
java.security.Principal
java.security.PrivilegedAction
java.security.PrivilegedExceptionAction
java.security.Guard
java.security.spec.KeySpec
java.security.spec.AlgorithmParameterSpec
java.security.interfaces.RSAKey
java.security.interfaces.RSAPublicKey java.security.PublicKey java.security.interfaces.RSAKey
java.security.interfaces.RSAPrivateKey java.security.PrivateKey java.security.interfaces.RSAKey
java.security.interfaces.RSAPrivateCrtKey java.security.interfaces.RSAPrivateKey
java.security.interfaces.ECKey
java.security.interfaces.ECPublicKey java.security.PublicKey java.security.interfaces.ECKey
java.security.interfaces.ECPrivateKey java.security.PrivateKey java.security.interfaces.ECKey
""")


def _throw(name, message=None):
    runtime.throw_new(name, message)


def _bytes(array):
    return to_py_bytes(array)


def _array(data):
    return to_java_bytes(bytes(data))


def _build_tables():
    sbox = [0] * 256
    p = q = 1
    while True:
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        x = q ^ ((q << 1) | (q >> 7)) & 0xFF ^ ((q << 2) | (q >> 6)) & 0xFF ^ ((q << 3) | (q >> 5)) & 0xFF ^ ((q << 4) | (q >> 4)) & 0xFF
        sbox[p] = (x ^ 0x63) & 0xFF
        if p == 1:
            break
    sbox[0] = 0x63
    inverse = [0] * 256
    for i, v in enumerate(sbox):
        inverse[v] = i
    return sbox, inverse


_SBOX, _INV_SBOX = _build_tables()


def _xtime(a):
    return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else a << 1


def _mul(a, b):
    result = 0
    while b:
        if b & 1:
            result ^= a
        a = _xtime(a)
        b >>= 1
    return result


_MUL = {n: [_mul(i, n) for i in range(256)] for n in (2, 3, 9, 11, 13, 14)}


class _AES:
    def __init__(self, key):
        if len(key) not in (16, 24, 32):
            _throw("java.security.InvalidKeyException", "Invalid AES key length: %d bytes" % len(key))
        self._rounds = {16: 10, 24: 12, 32: 14}[len(key)]
        words = [list(key[i:i + 4]) for i in range(0, len(key), 4)]
        nk = len(words)
        rcon = 1
        for i in range(nk, 4 * (self._rounds + 1)):
            temp = list(words[i - 1])
            if i % nk == 0:
                temp = temp[1:] + temp[:1]
                temp = [_SBOX[b] for b in temp]
                temp[0] ^= rcon
                rcon = _xtime(rcon)
            elif nk > 6 and i % nk == 4:
                temp = [_SBOX[b] for b in temp]
            words.append([a ^ b for a, b in zip(words[i - nk], temp)])
        self._keys = [sum(words[4 * r:4 * r + 4], []) for r in range(self._rounds + 1)]

    def encrypt_block(self, block):
        state = [b ^ k for b, k in zip(block, self._keys[0])]
        for rnd in range(1, self._rounds + 1):
            state = [_SBOX[b] for b in state]
            state = [state[(i + 4 * (i % 4)) % 16] for i in range(16)]
            if rnd != self._rounds:
                out = []
                for c in range(0, 16, 4):
                    a0, a1, a2, a3 = state[c:c + 4]
                    out += [_MUL[2][a0] ^ _MUL[3][a1] ^ a2 ^ a3, a0 ^ _MUL[2][a1] ^ _MUL[3][a2] ^ a3,
                            a0 ^ a1 ^ _MUL[2][a2] ^ _MUL[3][a3], _MUL[3][a0] ^ a1 ^ a2 ^ _MUL[2][a3]]
                state = out
            state = [b ^ k for b, k in zip(state, self._keys[rnd])]
        return bytes(state)

    def decrypt_block(self, block):
        state = [b ^ k for b, k in zip(block, self._keys[self._rounds])]
        for rnd in range(self._rounds - 1, -1, -1):
            state = [state[(i - 4 * (i % 4)) % 16] for i in range(16)]
            state = [_INV_SBOX[b] for b in state]
            state = [b ^ k for b, k in zip(state, self._keys[rnd])]
            if rnd:
                out = []
                for c in range(0, 16, 4):
                    a0, a1, a2, a3 = state[c:c + 4]
                    out += [_MUL[14][a0] ^ _MUL[11][a1] ^ _MUL[13][a2] ^ _MUL[9][a3], _MUL[9][a0] ^ _MUL[14][a1] ^ _MUL[11][a2] ^ _MUL[13][a3],
                            _MUL[13][a0] ^ _MUL[9][a1] ^ _MUL[14][a2] ^ _MUL[11][a3], _MUL[11][a0] ^ _MUL[13][a1] ^ _MUL[9][a2] ^ _MUL[14][a3]]
                state = out
        return bytes(state)


def _xor(a, b):
    return bytes(x ^ y for x, y in zip(a, b))


def _ghash(h, data):
    y = 0
    hv = int.from_bytes(h, "big")
    for i in range(0, len(data), 16):
        block = int.from_bytes(data[i:i + 16].ljust(16, b"\0"), "big")
        y = _gf_mul(y ^ block, hv)
    return y


def _gf_mul(x, y):
    z = 0
    v = y
    for i in range(127, -1, -1):
        if (x >> i) & 1:
            z ^= v
        v = (v >> 1) ^ (0xE1 << 120) if v & 1 else v >> 1
    return z


def _ctr_stream(aes, counter_block, data, bits=128):
    out = bytearray()
    counter = int.from_bytes(counter_block, "big")
    mask = (1 << bits) - 1
    high = counter & ~mask
    for i in range(0, len(data), 16):
        out += _xor(data[i:i + 16], aes.encrypt_block(counter.to_bytes(16, "big")))
        counter = high | ((counter + 1) & mask)
    return bytes(out)


def _pad(data):
    n = 16 - len(data) % 16
    return data + bytes([n]) * n


def _unpad(data):
    if not data or len(data) % 16:
        _throw("javax.crypto.IllegalBlockSizeException", "last block incomplete in decryption")
    n = data[-1]
    if not 1 <= n <= 16 or data[-n:] != bytes([n]) * n:
        _throw("javax.crypto.BadPaddingException", "pad block corrupted")
    return data[:-n]


@host_class("javax.crypto.spec.IvParameterSpec", interfaces=("java.security.spec.AlgorithmParameterSpec",))
class IvParameterSpec(Object):
    def __init__(self, iv, offset=0, length=None):
        self._iv = _bytes(iv)[offset:offset + (len(iv) - offset if length is None else length)]

    @jmethod("<init>", "([B)V")
    @jmethod("<init>", "([BII)V")
    def _init(self, iv, offset=0, length=None):
        IvParameterSpec.__init__(self, check_nonnull(iv), offset, length)

    @jmethod("getIV", "()[B")
    def getIV(self):
        return _array(self._iv)


@host_class("javax.crypto.spec.GCMParameterSpec", interfaces=("java.security.spec.AlgorithmParameterSpec",))
class GCMParameterSpec(Object):
    def __init__(self, tag_bits, iv, offset=0, length=None):
        if tag_bits < 0:
            _throw("java.lang.IllegalArgumentException", "Length argument is negative")
        self._t = tag_bits
        self._iv = _bytes(iv)[offset:offset + (len(iv) - offset if length is None else length)]

    @jmethod("<init>", "(I[B)V")
    @jmethod("<init>", "(I[BII)V")
    def _init(self, tag_bits, iv, offset=0, length=None):
        GCMParameterSpec.__init__(self, tag_bits, check_nonnull(iv), offset, length)

    @jmethod("getIV", "()[B")
    def getIV(self):
        return _array(self._iv)

    @jmethod("getTLen", "()I")
    def getTLen(self):
        return self._t


@host_class("javax.crypto.spec.PBEKeySpec", interfaces=("java.security.spec.KeySpec",))
class PBEKeySpec(Object):
    def __init__(self, password, salt=None, iterations=0, key_length=0):
        self._pw = "".join(chr(c) for c in password)
        self._salt = _bytes(salt) if salt is not None else None
        self._it, self._len = iterations, key_length

    @jmethod("<init>", "([C)V")
    @jmethod("<init>", "([C[BII)V")
    @jmethod("<init>", "([C[BI)V")
    def _init(self, password, salt=None, iterations=0, key_length=0):
        PBEKeySpec.__init__(self, password, salt, iterations, key_length)

    @jmethod("getPassword", "()[C")
    def getPassword(self):
        array = runtime.new_array("[C", 0)
        array.extend(ord(c) for c in self._pw)
        return array

    @jmethod("getSalt", "()[B")
    def getSalt(self):
        return _array(self._salt)

    @jmethod("getIterationCount", "()I")
    def getIterationCount(self):
        return self._it

    @jmethod("getKeyLength", "()I")
    def getKeyLength(self):
        return self._len

    @jmethod("clearPassword", "()V")
    def clearPassword(self):
        self._pw = ""


class _EncodedSpec(Object):
    def __init__(self, data):
        self._d = _bytes(data)

    @jmethod("<init>", "([B)V")
    def _init(self, data):
        type(self).__init__(self, data)

    @jmethod("getEncoded", "()[B")
    def getEncoded(self):
        return _array(self._d)


host_class("java.security.spec.EncodedKeySpec", interfaces=("java.security.spec.KeySpec",))(type("EncodedKeySpec", (_EncodedSpec,), {}))
host_class("java.security.spec.X509EncodedKeySpec", interfaces=("java.security.spec.KeySpec",))(type("X509EncodedKeySpec", (_EncodedSpec,), {}))
host_class("java.security.spec.PKCS8EncodedKeySpec", interfaces=("java.security.spec.KeySpec",))(type("PKCS8EncodedKeySpec", (_EncodedSpec,), {}))


@host_class("java.security.spec.RSAPublicKeySpec", interfaces=("java.security.spec.KeySpec",))
class RSAPublicKeySpec(Object):
    def __init__(self, modulus, exponent):
        self._n, self._e = modulus._v, exponent._v

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    def _init(self, modulus, exponent):
        RSAPublicKeySpec.__init__(self, modulus, exponent)

    @jmethod("getModulus", "()Ljava/math/BigInteger;")
    def getModulus(self):
        return BigInteger(self._n)

    @jmethod("getPublicExponent", "()Ljava/math/BigInteger;")
    def getPublicExponent(self):
        return BigInteger(self._e)


@host_class("java.security.spec.RSAPrivateKeySpec", interfaces=("java.security.spec.KeySpec",))
class RSAPrivateKeySpec(Object):
    def __init__(self, modulus, exponent):
        self._n, self._d = modulus._v, exponent._v

    @jmethod("<init>", "(Ljava/math/BigInteger;Ljava/math/BigInteger;)V")
    def _init(self, modulus, exponent):
        RSAPrivateKeySpec.__init__(self, modulus, exponent)

    @jmethod("getModulus", "()Ljava/math/BigInteger;")
    def getModulus(self):
        return BigInteger(self._n)

    @jmethod("getPrivateExponent", "()Ljava/math/BigInteger;")
    def getPrivateExponent(self):
        return BigInteger(self._d)


@host_class("java.security.spec.RSAKeyGenParameterSpec", interfaces=("java.security.spec.AlgorithmParameterSpec",))
class RSAKeyGenParameterSpec(Object):
    F0 = BigInteger(3)
    F4 = BigInteger(65537)

    def __init__(self, bits, exponent):
        self._bits, self._e = bits, exponent

    @jmethod("<init>", "(ILjava/math/BigInteger;)V")
    def _init(self, bits, exponent):
        RSAKeyGenParameterSpec.__init__(self, bits, exponent)

    @jmethod("getKeysize", "()I")
    def getKeysize(self):
        return self._bits

    @jmethod("getPublicExponent", "()Ljava/math/BigInteger;")
    def getPublicExponent(self):
        return self._e


def _der_read(data, pos=0):
    tag = data[pos]
    length = data[pos + 1]
    pos += 2
    if length & 0x80:
        count = length & 0x7F
        length = int.from_bytes(data[pos:pos + count], "big")
        pos += count
    return tag, data[pos:pos + length], pos + length


def _der_items(data):
    items, pos = [], 0
    while pos < len(data):
        tag, body, pos = _der_read(data, pos)
        items.append((tag, body))
    return items


def _der_len(n):
    if n < 128:
        return bytes([n])
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def _der(tag, body):
    return bytes([tag]) + _der_len(len(body)) + body


def _der_int(n):
    raw = n.to_bytes(max(1, (n.bit_length() + 8) // 8), "big")
    return _der(2, raw)


_RSA_ALGORITHM = _der(0x30, _der(6, bytes.fromhex("2a864886f70d010101")) + _der(5, b""))


class _RSAKey(Object):
    def __init__(self, n, exponent, private=False, crt=None):
        self._n, self._x, self._private, self._crt = n, exponent, private, crt

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return "RSA"

    @jmethod("getFormat", "()Ljava/lang/String;")
    def getFormat(self):
        return "PKCS#8" if self._private else "X.509"

    @jmethod("getModulus", "()Ljava/math/BigInteger;")
    def getModulus(self):
        return BigInteger(self._n)

    @jmethod("getPublicExponent", "()Ljava/math/BigInteger;")
    def getPublicExponent(self):
        return BigInteger(self._x)

    @jmethod("getPrivateExponent", "()Ljava/math/BigInteger;")
    def getPrivateExponent(self):
        return BigInteger(self._x)

    @jmethod("getEncoded", "()[B")
    def getEncoded(self):
        if not self._private:
            body = _der(0x30, _der_int(self._n) + _der_int(self._x))
            return _array(_der(0x30, _RSA_ALGORITHM + _der(3, b"\0" + body)))
        e, p, q = self._crt[0], self._crt[1], self._crt[2]
        d = self._x
        inner = _der(0x30, b"".join(_der_int(v) for v in (0, self._n, e, d, p, q, d % (p - 1), d % (q - 1), pow(q, -1, p))))
        return _array(_der(0x30, _der_int(0) + _RSA_ALGORITHM + _der(4, inner)))

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, _RSAKey) and (other._n, other._x, other._private) == (self._n, self._x, self._private) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return runtime.wrap32(self._n ^ self._x)


class RSAPublicKeyImpl(_RSAKey):
    pass


class RSAPrivateKeyImpl(_RSAKey):
    pass


host_class("sun.security.rsa.RSAPublicKeyImpl", interfaces=("java.security.interfaces.RSAPublicKey",))(RSAPublicKeyImpl)
host_class("sun.security.rsa.RSAPrivateCrtKeyImpl", interfaces=("java.security.interfaces.RSAPrivateCrtKey",))(RSAPrivateKeyImpl)


def _rsa_from_encoded(data, private):
    try:
        _, outer, _ = _der_read(data)
        items = _der_items(outer)
        if not private:
            _, bits = items[1]
            _, key_seq, _ = _der_read(bits[1:])
            n, e = (int.from_bytes(b, "big") for _, b in _der_items(key_seq))
            return RSAPublicKeyImpl(n, e)
        _, octets = items[2]
        _, key_seq, _ = _der_read(octets)
        values = [int.from_bytes(b, "big") for _, b in _der_items(key_seq)]
        return RSAPrivateKeyImpl(values[1], values[3], True, (values[2], values[4], values[5]))
    except (IndexError, ValueError):
        _throw("java.security.spec.InvalidKeySpecException", "invalid key encoding")


def _is_probable_prime(n, rounds=24):
    if n < 4:
        return n in (2, 3)
    if n % 2 == 0:
        return False
    for p in (3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0:
            return n == p
    d, s = n - 1, 0
    while d % 2 == 0:
        d //= 2
        s += 1
    for _ in range(rounds):
        a = int.from_bytes(os.urandom((n.bit_length() + 7) // 8), "big") % (n - 3) + 2
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(s - 1):
            x = x * x % n
            if x == n - 1:
                break
        else:
            return False
    return True


def _random_prime(bits):
    while True:
        candidate = int.from_bytes(os.urandom((bits + 7) // 8), "big")
        candidate |= (1 << (bits - 1)) | (1 << (bits - 2)) | 1
        candidate &= (1 << bits) - 1
        if _is_probable_prime(candidate):
            return candidate


@host_class("java.security.KeyPair")
class KeyPair(Object):
    def __init__(self, public, private):
        self._pub, self._priv = public, private

    @jmethod("<init>", "(Ljava/security/PublicKey;Ljava/security/PrivateKey;)V")
    def _init(self, public, private):
        KeyPair.__init__(self, public, private)

    @jmethod("getPublic", "()Ljava/security/PublicKey;")
    def getPublic(self):
        return self._pub

    @jmethod("getPrivate", "()Ljava/security/PrivateKey;")
    def getPrivate(self):
        return self._priv


@host_class("java.security.KeyPairGenerator")
class KeyPairGenerator(Object):
    def __init__(self, algorithm):
        from . import jkeys
        self._bits = 2048
        self._e = 65537
        self._algorithm = algorithm
        family = jkeys.key_family(algorithm)
        self._other = jkeys.Generator(family, algorithm) if family else None

    @jstatic("getInstance", "(Ljava/lang/String;)Ljava/security/KeyPairGenerator;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljava/security/KeyPairGenerator;")
    def getInstance(algorithm, provider=None):
        from . import jkeys
        if algorithm.upper() != "RSA" and jkeys.key_family(algorithm) is None:
            _throw("java.security.NoSuchAlgorithmException", "%s KeyPairGenerator not available" % algorithm)
        return KeyPairGenerator(algorithm)

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return self._algorithm

    @jmethod("initialize", "(I)V")
    @jmethod("initialize", "(ILjava/security/SecureRandom;)V")
    @jmethod("initialize", "(Ljava/security/spec/AlgorithmParameterSpec;)V")
    @jmethod("initialize", "(Ljava/security/spec/AlgorithmParameterSpec;Ljava/security/SecureRandom;)V")
    def initialize(self, first, random=None):
        if self._other is not None:
            return self._other.initialize(first)
        if isinstance(first, int):
            self._bits = first
        else:
            self._bits, self._e = first._bits, first._e._v
        if self._bits < 512 or self._bits > 8192 or self._bits % 8:
            _throw("java.security.InvalidParameterException", "RSA keys must be at least 512 bits long")

    @jmethod("generateKeyPair", "()Ljava/security/KeyPair;")
    @jmethod("genKeyPair", "()Ljava/security/KeyPair;")
    def generateKeyPair(self):
        if self._other is not None:
            return KeyPair(*self._other.generate())
        while True:
            p = _random_prime(self._bits // 2)
            q = _random_prime(self._bits - self._bits // 2)
            if p == q:
                continue
            n = p * q
            if n.bit_length() != self._bits:
                continue
            phi = (p - 1) * (q - 1)
            if phi % self._e == 0:
                continue
            d = pow(self._e, -1, phi)
            return KeyPair(RSAPublicKeyImpl(n, self._e), RSAPrivateKeyImpl(n, d, True, (self._e, p, q)))


@host_class("java.security.KeyFactory")
class KeyFactory(Object):
    def __init__(self, algorithm="RSA"):
        from . import jkeys
        self._algorithm = algorithm
        self._family = jkeys.key_family(algorithm)

    @jstatic("getInstance", "(Ljava/lang/String;)Ljava/security/KeyFactory;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljava/security/KeyFactory;")
    def getInstance(algorithm, provider=None):
        from . import jkeys
        if algorithm.upper() != "RSA" and jkeys.key_family(algorithm) is None:
            _throw("java.security.NoSuchAlgorithmException", "%s KeyFactory not available" % algorithm)
        return KeyFactory(algorithm)

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return self._algorithm

    @jmethod("generatePublic", "(Ljava/security/spec/KeySpec;)Ljava/security/PublicKey;")
    def generatePublic(self, spec):
        if self._family:
            from . import jkeys
            return jkeys.key_spec_public(self._family, spec)
        if isinstance(spec, RSAPublicKeySpec):
            return RSAPublicKeyImpl(spec._n, spec._e)
        if isinstance(spec, _EncodedSpec):
            return _rsa_from_encoded(spec._d, False)
        _throw("java.security.spec.InvalidKeySpecException", "unsupported key spec")

    @jmethod("generatePrivate", "(Ljava/security/spec/KeySpec;)Ljava/security/PrivateKey;")
    def generatePrivate(self, spec):
        if self._family:
            from . import jkeys
            return jkeys.key_spec_private(self._family, spec)
        if isinstance(spec, RSAPrivateKeySpec):
            return RSAPrivateKeyImpl(spec._n, spec._d, True, None)
        if isinstance(spec, _EncodedSpec):
            return _rsa_from_encoded(spec._d, True)
        _throw("java.security.spec.InvalidKeySpecException", "unsupported key spec")


_DIGEST_INFO = {"sha1": bytes.fromhex("3021300906052b0e03021a05000414"), "sha256": bytes.fromhex("3031300d060960864801650304020105000420"),
                "sha384": bytes.fromhex("3041300d060960864801650304020205000430"), "sha512": bytes.fromhex("3051300d060960864801650304020305000440")}


def _emsa(digest_name, message, size):
    digest = hashlib.new(digest_name, message).digest()
    info = _DIGEST_INFO[digest_name] + digest
    return b"\x00\x01" + b"\xff" * (size - len(info) - 3) + b"\x00" + info


@host_class("java.security.Signature")
class Signature(Object):
    _NAMES = {"sha1withrsa": "sha1", "sha256withrsa": "sha256", "sha384withrsa": "sha384", "sha512withrsa": "sha512",
              "sha1withecdsa": "sha1", "sha224withecdsa": "sha224", "sha256withecdsa": "sha256", "sha384withecdsa": "sha384",
              "sha512withecdsa": "sha512"}

    def __init__(self, algorithm, digest):
        self._algorithm, self._digest, self._buf, self._key, self._mode = algorithm, digest, bytearray(), None, None

    @jstatic("getInstance", "(Ljava/lang/String;)Ljava/security/Signature;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljava/security/Signature;")
    def getInstance(algorithm, provider=None):
        digest = Signature._NAMES.get(algorithm.lower())
        if digest is None:
            _throw("java.security.NoSuchAlgorithmException", "%s Signature not available" % algorithm)
        return Signature(algorithm, digest)

    @jmethod("initSign", "(Ljava/security/PrivateKey;)V")
    def initSign(self, key):
        if self._algorithm.lower().endswith("ecdsa"):
            from . import jkeys
            if not isinstance(key, jkeys.ECPrivateKeyImpl):
                _throw("java.security.InvalidKeyException", "No installed provider supports this key: " + type(key).__name__)
            self._key, self._mode, self._buf = key, "sign", bytearray()
            return
        if not isinstance(key, _RSAKey) or not key._private:
            _throw("java.security.InvalidKeyException", "not an RSA private key")
        self._key, self._mode, self._buf = key, "sign", bytearray()

    @jmethod("initVerify", "(Ljava/security/PublicKey;)V")
    def initVerify(self, key):
        if self._algorithm.lower().endswith("ecdsa"):
            from . import jkeys
            if not isinstance(key, jkeys.ECPublicKeyImpl):
                _throw("java.security.InvalidKeyException", "No installed provider supports this key: " + type(key).__name__)
            self._key, self._mode, self._buf = key, "verify", bytearray()
            return
        if not isinstance(key, _RSAKey) or key._private:
            _throw("java.security.InvalidKeyException", "not an RSA public key")
        self._key, self._mode, self._buf = key, "verify", bytearray()

    @jmethod("update", "([B)V")
    @jmethod("update", "([BII)V")
    @jmethod("update", "(B)V")
    def update(self, data, offset=0, length=None):
        if self._mode is None:
            _throw("java.security.SignatureException", "object not initialized for signing or verification")
        self._buf += bytes((data & 0xFF,)) if isinstance(data, int) else to_py_bytes(data, offset, length)

    @jmethod("sign", "()[B")
    def sign(self):
        if self._mode != "sign":
            _throw("java.security.SignatureException", "object not initialized for signing")
        if self._algorithm.lower().endswith("ecdsa"):
            from . import jkeys
            digest = hashlib.new(self._digest, bytes(self._buf)).digest()
            self._buf = bytearray()
            return _array(jkeys.ecdsa_sign(self._key, digest))
        size = (self._key._n.bit_length() + 7) // 8
        em = int.from_bytes(_emsa(self._digest, bytes(self._buf), size), "big")
        self._buf = bytearray()
        return _array(pow(em, self._key._x, self._key._n).to_bytes(size, "big"))

    @jmethod("verify", "([B)Z")
    def verify(self, signature):
        if self._mode != "verify":
            _throw("java.security.SignatureException", "object not initialized for verification")
        if self._algorithm.lower().endswith("ecdsa"):
            from . import jkeys
            digest = hashlib.new(self._digest, bytes(self._buf)).digest()
            self._buf = bytearray()
            return 1 if jkeys.ecdsa_verify_key(self._key, digest, _bytes(signature)) else 0
        size = (self._key._n.bit_length() + 7) // 8
        raw = _bytes(signature)
        message, self._buf = bytes(self._buf), bytearray()
        if len(raw) != size:
            return 0
        decoded = pow(int.from_bytes(raw, "big"), self._key._x, self._key._n).to_bytes(size, "big")
        return 1 if _hmac.compare_digest(decoded, _emsa(self._digest, message, size)) else 0

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return self._algorithm


@host_class("javax.crypto.KeyGenerator")
class KeyGenerator(Object):
    def __init__(self, algorithm):
        self._alg = algorithm
        self._bits = 256 if algorithm.upper() == "AES" else 256

    @jstatic("getInstance", "(Ljava/lang/String;)Ljavax/crypto/KeyGenerator;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/KeyGenerator;")
    def getInstance(algorithm, provider=None):
        if algorithm.upper() not in ("AES",) and not algorithm.upper().startswith("HMAC"):
            _throw("java.security.NoSuchAlgorithmException", "%s KeyGenerator not available" % algorithm)
        return KeyGenerator(algorithm)

    @jmethod("init", "(I)V")
    @jmethod("init", "(ILjava/security/SecureRandom;)V")
    @jmethod("init", "(Ljava/security/SecureRandom;)V")
    def init(self, first, random=None):
        if isinstance(first, int):
            if self._alg.upper() == "AES" and first not in (128, 192, 256):
                _throw("java.security.InvalidParameterException", "Wrong keysize: must be equal to 128, 192 or 256")
            self._bits = first

    @jmethod("generateKey", "()Ljavax/crypto/SecretKey;")
    def generateKey(self):
        return lookup_host("javax.crypto.spec.SecretKeySpec").py(_array(os.urandom(self._bits // 8)), self._alg)


@host_class("javax.crypto.SecretKeyFactory")
class SecretKeyFactory(Object):
    _DIGESTS = {"pbkdf2withhmacsha1": "sha1", "pbkdf2withhmacsha224": "sha224", "pbkdf2withhmacsha256": "sha256", "pbkdf2withhmacsha384": "sha384",
                "pbkdf2withhmacsha512": "sha512"}

    def __init__(self, algorithm, digest):
        self._alg, self._digest = algorithm, digest

    @jstatic("getInstance", "(Ljava/lang/String;)Ljavax/crypto/SecretKeyFactory;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/SecretKeyFactory;")
    def getInstance(algorithm, provider=None):
        digest = SecretKeyFactory._DIGESTS.get(algorithm.lower())
        if digest is None:
            _throw("java.security.NoSuchAlgorithmException", "%s SecretKeyFactory not available" % algorithm)
        return SecretKeyFactory(algorithm, digest)

    @jmethod("generateSecret", "(Ljava/security/spec/KeySpec;)Ljavax/crypto/SecretKey;")
    def generateSecret(self, spec):
        if not isinstance(spec, PBEKeySpec) or spec._salt is None or spec._it <= 0 or spec._len <= 0:
            _throw("java.security.spec.InvalidKeySpecException", "Salt not found" if getattr(spec, "_salt", 1) is None else "Invalid key spec")
        derived = hashlib.pbkdf2_hmac(self._digest, spec._pw.encode("utf-8"), spec._salt, spec._it, spec._len // 8)
        return lookup_host("javax.crypto.spec.SecretKeySpec").py(_array(derived), self._alg)

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return self._alg


@host_class("javax.crypto.Cipher")
class Cipher(Object):
    ENCRYPT_MODE = 1
    DECRYPT_MODE = 2
    WRAP_MODE = 3
    UNWRAP_MODE = 4

    def __init__(self, transformation):
        parts = transformation.split("/")
        algorithm = parts[0].upper()
        mode = parts[1].upper() if len(parts) > 1 else "ECB"
        padding = parts[2].upper() if len(parts) > 2 else "PKCS5PADDING"
        if algorithm == "AES" and mode in ("ECB", "CBC", "CTR", "GCM") and padding in ("PKCS5PADDING", "PKCS7PADDING", "NOPADDING"):
            if mode in ("CTR", "GCM") and padding != "NOPADDING":
                _throw("javax.crypto.NoSuchPaddingException", "Padding %s is not available for %s" % (parts[2], mode))
        elif algorithm == "RSA" and mode in ("ECB", "NONE") and padding in ("PKCS1PADDING", "OAEPPADDING", "OAEPWITHSHA-1ANDMGF1PADDING",
                                                                            "OAEPWITHSHA-256ANDMGF1PADDING", "NOPADDING"):
            pass
        else:
            _throw("java.security.NoSuchAlgorithmException", "Cannot find any provider supporting %s" % transformation)
        self._t = transformation
        self._algorithm, self._mode, self._padding = algorithm, mode, padding
        self._op = None
        self._buf = bytearray()
        self._aad = bytearray()
        self._iv = None
        self._tag = 128
        self._key = None

    @jstatic("getInstance", "(Ljava/lang/String;)Ljavax/crypto/Cipher;")
    @jstatic("getInstance", "(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/Cipher;")
    def getInstance(transformation, provider=None):
        return Cipher(check_nonnull(transformation))

    @jmethod("init", "(ILjava/security/Key;)V")
    @jmethod("init", "(ILjava/security/Key;Ljava/security/SecureRandom;)V")
    @jmethod("init", "(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V")
    @jmethod("init", "(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;Ljava/security/SecureRandom;)V")
    def init(self, op, key, spec=None, random=None):
        if op not in (1, 2, 3, 4):
            _throw("java.security.InvalidParameterException", "Invalid operation mode")
        self._op = 2 if op in (2, 4) else 1
        self._buf, self._aad = bytearray(), bytearray()
        if self._algorithm == "AES":
            raw = _bytes(key.getEncoded())
            self._aes = _AES(raw)
            self._iv = None
            if isinstance(spec, IvParameterSpec):
                self._iv = spec._iv
            elif isinstance(spec, GCMParameterSpec):
                self._iv, self._tag = spec._iv, spec._t
            elif spec is not None and not hasattr(spec, "nextBytes"):
                _throw("java.security.InvalidAlgorithmParameterException", "unsupported parameter spec")
            if self._mode != "ECB":
                need = 12 if self._mode == "GCM" else 16
                if self._iv is None:
                    if self._op == 2:
                        _throw("java.security.InvalidKeyException" if False else "java.security.InvalidAlgorithmParameterException",
                               "Parameters missing")
                    self._iv = os.urandom(need)
                elif self._mode != "GCM" and len(self._iv) != 16:
                    _throw("java.security.InvalidAlgorithmParameterException", "Wrong IV length: must be 16 bytes long")
        else:
            if not isinstance(key, _RSAKey):
                _throw("java.security.InvalidKeyException", "No installed provider supports this key: %s" % type(key).__name__)
            self._key = key

    @jmethod("getIV", "()[B")
    def getIV(self):
        return _array(self._iv) if self._iv is not None else None

    @jmethod("getBlockSize", "()I")
    def getBlockSize(self):
        return 16 if self._algorithm == "AES" else 0

    @jmethod("getAlgorithm", "()Ljava/lang/String;")
    def getAlgorithm(self):
        return self._t

    @jmethod("getOutputSize", "(I)I")
    def getOutputSize(self, n):
        total = len(self._buf) + n
        if self._algorithm == "AES" and self._mode == "GCM":
            return total + self._tag // 8 if self._op == 1 else max(0, total - self._tag // 8)
        if self._algorithm == "AES" and self._padding != "NOPADDING" and self._mode in ("ECB", "CBC"):
            return (total // 16 + 1) * 16 if self._op == 1 else total
        return total

    @jmethod("updateAAD", "([B)V")
    @jmethod("updateAAD", "([BII)V")
    def updateAAD(self, data, offset=0, length=None):
        if self._mode != "GCM":
            _throw("java.lang.IllegalStateException", "AAD is only supported by GCM")
        self._aad += to_py_bytes(data, offset, length)

    def _need_init(self):
        if self._op is None:
            _throw("java.lang.IllegalStateException", "Cipher not initialized")

    @jmethod("update", "([B)[B")
    @jmethod("update", "([BII)[B")
    def update(self, data, offset=0, length=None):
        self._need_init()
        self._buf += to_py_bytes(data, offset, length)
        return _array(b"")

    @jmethod("doFinal", "()[B")
    @jmethod("doFinal", "([B)[B")
    @jmethod("doFinal", "([BII)[B")
    def doFinal(self, data=None, offset=0, length=None):
        self._need_init()
        if data is not None:
            self._buf += to_py_bytes(data, offset, length)
        message, self._buf = bytes(self._buf), bytearray()
        result = self._aes_final(message) if self._algorithm == "AES" else self._rsa_final(message)
        return _array(result)

    def _aes_final(self, message):
        aes = self._aes
        if self._mode == "GCM":
            return self._gcm(message)
        if self._mode == "CTR":
            return _ctr_stream(aes, self._iv, message)
        if self._padding == "NOPADDING":
            if len(message) % 16:
                _throw("javax.crypto.IllegalBlockSizeException", "Input length not multiple of 16 bytes")
        elif self._op == 1:
            message = _pad(message)
        elif len(message) % 16:
            _throw("javax.crypto.IllegalBlockSizeException", "Input length must be multiple of 16 when decrypting with padded cipher")
        out = bytearray()
        previous = self._iv
        for i in range(0, len(message), 16):
            block = message[i:i + 16]
            if self._op == 1:
                if self._mode == "CBC":
                    block = _xor(block, previous)
                encrypted = aes.encrypt_block(block)
                out += encrypted
                previous = encrypted
            else:
                decrypted = aes.decrypt_block(block)
                if self._mode == "CBC":
                    decrypted = _xor(decrypted, previous)
                    previous = block
                out += decrypted
        result = bytes(out)
        return _unpad(result) if self._op == 2 and self._padding != "NOPADDING" else result

    def _gcm(self, message):
        aes, iv = self._aes, self._iv
        h = aes.encrypt_block(b"\0" * 16)
        if len(iv) == 12:
            j0 = iv + b"\0\0\0\1"
        else:
            j0 = _ghash(h, iv.ljust((len(iv) + 15) // 16 * 16, b"\0") + b"\0" * 8 + (len(iv) * 8).to_bytes(8, "big")).to_bytes(16, "big")
        counter = (int.from_bytes(j0, "big") & ~0xFFFFFFFF) | (((int.from_bytes(j0, "big") & 0xFFFFFFFF) + 1) & 0xFFFFFFFF)
        tag_len = self._tag // 8
        if self._op == 2:
            if len(message) < tag_len:
                _throw("javax.crypto.AEADBadTagException", "Input too short - need tag")
            ciphertext, received = message[:-tag_len], message[-tag_len:]
        else:
            ciphertext = None
        data = ciphertext if self._op == 2 else message
        stream = _ctr_stream(aes, counter.to_bytes(16, "big"), data, 32)
        cipher = data if self._op == 2 else stream
        aad = bytes(self._aad)
        padded = aad.ljust((len(aad) + 15) // 16 * 16, b"\0") + cipher.ljust((len(cipher) + 15) // 16 * 16, b"\0") + (
            (len(aad) * 8).to_bytes(8, "big") + (len(cipher) * 8).to_bytes(8, "big"))
        s = _ghash(h, padded).to_bytes(16, "big")
        tag = _xor(aes.encrypt_block(j0), s)[:tag_len]
        self._aad = bytearray()
        if self._op == 1:
            return stream + tag
        if not _hmac.compare_digest(tag, received):
            _throw("javax.crypto.AEADBadTagException", "Tag mismatch")
        return stream

    def _rsa_final(self, message):
        key = self._key
        size = (key._n.bit_length() + 7) // 8
        encrypting = self._op == 1
        if self._padding == "NOPADDING":
            m = int.from_bytes(message, "big")
            if m >= key._n:
                _throw("javax.crypto.IllegalBlockSizeException", "Data must not be longer than %d bytes" % size)
            return pow(m, key._x, key._n).to_bytes(size, "big")
        if self._padding == "PKCS1PADDING":
            if encrypting:
                if len(message) > size - 11:
                    _throw("javax.crypto.IllegalBlockSizeException", "Data must not be longer than %d bytes" % (size - 11))
                if key._private:
                    block = b"\x00\x01" + b"\xff" * (size - len(message) - 3) + b"\x00" + message
                else:
                    pad = bytearray()
                    while len(pad) < size - len(message) - 3:
                        pad += bytes(b for b in os.urandom(size) if b)
                    block = b"\x00\x02" + bytes(pad[:size - len(message) - 3]) + b"\x00" + message
                return pow(int.from_bytes(block, "big"), key._x, key._n).to_bytes(size, "big")
            if len(message) != size:
                _throw("javax.crypto.IllegalBlockSizeException", "Data must not be longer than %d bytes" % size)
            block = pow(int.from_bytes(message, "big"), key._x, key._n).to_bytes(size, "big")
            if block[0] != 0 or block[1] not in (1, 2) or 0 not in block[2:]:
                _throw("javax.crypto.BadPaddingException", "Decryption error")
            return block[block.index(0, 2) + 1:]
        digest = "sha256" if "256" in self._padding else "sha1"
        hlen = hashlib.new(digest).digest_size
        return self._oaep_encrypt(message, size, digest, hlen) if encrypting else self._oaep_decrypt(message, size, digest, hlen)

    @staticmethod
    def _mgf1(seed, length, digest):
        out = b""
        counter = 0
        while len(out) < length:
            out += hashlib.new(digest, seed + counter.to_bytes(4, "big")).digest()
            counter += 1
        return out[:length]

    def _oaep_encrypt(self, message, size, digest, hlen):
        if len(message) > size - 2 * hlen - 2:
            _throw("javax.crypto.IllegalBlockSizeException", "Data must not be longer than %d bytes" % (size - 2 * hlen - 2))
        lhash = hashlib.new(digest, b"").digest()
        db = lhash + b"\0" * (size - len(message) - 2 * hlen - 2) + b"\x01" + message
        seed = os.urandom(hlen)
        masked_db = _xor(db, self._mgf1(seed, len(db), digest))
        masked_seed = _xor(seed, self._mgf1(masked_db, hlen, digest))
        em = b"\0" + masked_seed + masked_db
        return pow(int.from_bytes(em, "big"), self._key._x, self._key._n).to_bytes(size, "big")

    def _oaep_decrypt(self, message, size, digest, hlen):
        if len(message) != size:
            _throw("javax.crypto.IllegalBlockSizeException", "Data must not be longer than %d bytes" % size)
        em = pow(int.from_bytes(message, "big"), self._key._x, self._key._n).to_bytes(size, "big")
        masked_seed, masked_db = em[1:1 + hlen], em[1 + hlen:]
        seed = _xor(masked_seed, self._mgf1(masked_db, hlen, digest))
        db = _xor(masked_db, self._mgf1(seed, len(masked_db), digest))
        lhash = hashlib.new(digest, b"").digest()
        rest = db[hlen:].lstrip(b"\0")
        if em[0] != 0 or not _hmac.compare_digest(db[:hlen], lhash) or not rest.startswith(b"\x01"):
            _throw("javax.crypto.BadPaddingException", "Decryption error")
        return rest[1:]


@host_class("javax.crypto.CipherOutputStream", superclass="java.io.FilterOutputStream")
class CipherOutputStream(lookup_host("java.io.FilterOutputStream").py):
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljavax/crypto/Cipher;)V")
    def _init(self, sink, cipher):
        lookup_host("java.io.FilterOutputStream").py.__init__(self, sink)
        self._cipher = cipher

    def write_byte(self, value):
        self._cipher.update(_array(bytes((value & 0xFF,))))

    def write(self, buffer, offset=0, length=None):
        self._cipher.update(buffer, offset, length)

    def close(self):
        data = self._cipher.doFinal()
        self._out.write(data, 0, len(data))
        self._out.close()


@host_class("javax.crypto.CipherInputStream", superclass="java.io.FilterInputStream")
class CipherInputStream(lookup_host("java.io.FilterInputStream").py):
    @jmethod("<init>", "(Ljava/io/InputStream;Ljavax/crypto/Cipher;)V")
    def _init(self, source, cipher):
        lookup_host("java.io.FilterInputStream").py.__init__(self, source)
        self._cipher = cipher
        self._data = None
        self._pos = 0

    def _load(self):
        if self._data is None:
            self._data = _bytes(self._cipher.doFinal(self._in.readAllBytes()))

    def read_byte(self):
        self._load()
        if self._pos >= len(self._data):
            return -1
        self._pos += 1
        return self._data[self._pos - 1]


@host_class("java.security.DigestInputStream", superclass="java.io.FilterInputStream")
class DigestInputStream(lookup_host("java.io.FilterInputStream").py):
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/security/MessageDigest;)V")
    def _init(self, source, digest):
        lookup_host("java.io.FilterInputStream").py.__init__(self, source)
        self._md = digest

    def read_byte(self):
        value = self._in.read_byte()
        if value != -1:
            self._md.update(value if False else _array(bytes((value,))))
        return value

    def read(self, buffer, offset=0, length=None):
        count = self._in.read(buffer, offset, length) if length is not None else self._in.read(buffer)
        if count > 0:
            self._md.update(buffer, offset, count)
        return count

    @jmethod("getMessageDigest", "()Ljava/security/MessageDigest;")
    def getMessageDigest(self):
        return self._md


@host_class("java.security.DigestOutputStream", superclass="java.io.FilterOutputStream")
class DigestOutputStream(lookup_host("java.io.FilterOutputStream").py):
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/security/MessageDigest;)V")
    def _init(self, sink, digest):
        lookup_host("java.io.FilterOutputStream").py.__init__(self, sink)
        self._md = digest

    def write_byte(self, value):
        self._md.update(_array(bytes((value & 0xFF,))))
        self._out.write_byte(value)

    def write(self, buffer, offset=0, length=None):
        length = len(buffer) - offset if length is None else length
        self._md.update(buffer, offset, length)
        self._out.write(buffer, offset, length)

    @jmethod("getMessageDigest", "()Ljava/security/MessageDigest;")
    def getMessageDigest(self):
        return self._md


@host_class("java.security.AccessController", final=True)
class AccessController(Object):
    @jstatic("doPrivileged", "(Ljava/security/PrivilegedAction;)Ljava/lang/Object;")
    @jstatic("doPrivileged", "(Ljava/security/PrivilegedExceptionAction;)Ljava/lang/Object;")
    def doPrivileged(action):
        return action.run()


@host_class("java.security.Provider")
class Provider(Object):
    def __init__(self, name="exteria", version=1.0, info=""):
        self._name, self._v, self._info = name, version, info

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("getVersion", "()D")
    def getVersion(self):
        return self._v

    @jmethod("getInfo", "()Ljava/lang/String;")
    def getInfo(self):
        return self._info


@host_class("java.security.Security", final=True)
class Security(Object):
    _providers = [Provider("exteria", 1.0, "AES, RSA, PBKDF2, SHA digests, HMAC")]

    @jstatic("getProviders", "()[Ljava/security/Provider;")
    def getProviders():
        array = runtime.new_array("[Ljava/security/Provider;", 0)
        array.extend(Security._providers)
        return array

    @jstatic("getProvider", "(Ljava/lang/String;)Ljava/security/Provider;")
    def getProvider(name):
        return next((p for p in Security._providers if p._name == name), None)

    @jstatic("addProvider", "(Ljava/security/Provider;)I")
    def addProvider(provider):
        if any(p._name == provider._name for p in Security._providers):
            return -1
        Security._providers.append(provider)
        return len(Security._providers)

    @jstatic("insertProviderAt", "(Ljava/security/Provider;I)I")
    def insertProviderAt(provider, position):
        return Security.addProvider(provider)

    @jstatic("removeProvider", "(Ljava/lang/String;)V")
    def removeProvider(name):
        Security._providers[:] = [p for p in Security._providers if p._name != name]

    @jstatic("getProperty", "(Ljava/lang/String;)Ljava/lang/String;")
    def getProperty(key):
        return None
