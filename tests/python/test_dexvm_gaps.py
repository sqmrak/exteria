"""signature checks of certificates (ECDSA, RSASSA-PSS), the jdk text of a certificate, Phaser trees and Stream.count"""

import os
import sys
import threading
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fakeapp  # noqa: E402,F401

sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import dexvm  # noqa: E402,F401
from dexvm import api, runtime  # noqa: E402
from dexvm.jcert import X509CertImpl, split_certificates  # noqa: E402
from dexvm.jio import to_java_bytes as to_java  # noqa: E402
from dexvm.jstream import BaseStream  # noqa: E402

# self signed, made with openssl; the first three sign with ECDSA over P-256, P-384 and P-521, the last two with RSASSA-PSS
CERTS = {
    'prime256v1': """-----BEGIN CERTIFICATE-----
MIIBgDCCASWgAwIBAgIUE159NGV5vA6x/M2wZ0bZ1rmeRM4wCgYIKoZIzj0EAwIw
FTETMBEGA1UEAwwKcHJpbWUyNTZ2MTAeFw0yNjExMTExMDIwMzNaFw0yNjExMTQx
MDIwMzNaMBUxEzARBgNVBAMMCnByaW1lMjU2djEwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAARKqkfq2bZqQlVT4sbTBH1qIrkas/KwrAGqE8Ij6ExbCqzivgryr0af
PK+2lUU+Dcwz7Shi3Xr9BoCtqch0WOcxo1MwUTAdBgNVHQ4EFgQU/2EKg3B6sj8k
RO5rf6QRhAva2gQwHwYDVR0jBBgwFoAU/2EKg3B6sj8kRO5rf6QRhAva2gQwDwYD
VR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNJADBGAiEAryp7hD/aWY6BSwUsUuyW
XgUTbiTpyRRvfExoyaGVqS0CIQDMTI3xPLtB+aP5CmQQZBgQn1xXpUyKUTaBAlZ3
hx3Flg==
-----END CERTIFICATE-----
""",
    'secp384r1': """-----BEGIN CERTIFICATE-----
MIIBuTCCAUCgAwIBAgIUKPG9U6s+Amn91EqzE++RQtn49O4wCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJc2VjcDM4NHIxMB4XDTI2MTExMTEwMjAzM1oXDTI2MTExNDEw
MjAzM1owFDESMBAGA1UEAwwJc2VjcDM4NHIxMHYwEAYHKoZIzj0CAQYFK4EEACID
YgAERVMGHdwngMuxOuazZax9fnK76rf/yq0Te0XDZWRnJovgdSfXD219ANX/3wIz
yXeEWR4pGRkGedjZj3b3sK4jHOkRDmHgVWvJngpSWtaotS+eaeTPDl4Iak1j+zHY
8X5no1MwUTAdBgNVHQ4EFgQUP9CL9LO9iFVU8Yl8npSGjW7LyoIwHwYDVR0jBBgw
FoAUP9CL9LO9iFVU8Yl8npSGjW7LyoIwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjO
PQQDAgNnADBkAjBjzq8DitZrpSAvNmP6J+/OPr2cxE8LaSnbeJsLi7h0Yrx/Itr+
XunAZtFjeSyhuXsCMDopnLYyKOWROIXqhjq/3NAH/4ygu+5NlRj52T6W6Nhi05hg
HM0V16cAAv/yvIT6lA==
-----END CERTIFICATE-----
""",
    'secp521r1': """-----BEGIN CERTIFICATE-----
MIICBTCCAWagAwIBAgIUHDjavhRsgrgLsUd8M0euVpLw0+owCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJc2VjcDUyMXIxMB4XDTI2MTExMTEwMjAzM1oXDTI2MTExNDEw
MjAzM1owFDESMBAGA1UEAwwJc2VjcDUyMXIxMIGbMBAGByqGSM49AgEGBSuBBAAj
A4GGAAQBIJV8hbCDBSnTnEl61yf6YW5nMWxFNESsyU2AtOM1GNAJvWpM1LrH4VtG
MJiqWYf9huyPZwn27wFaKwKVyO/rpU0AvzJUbANS+KTaOSIBhe0stfTGHDe4WkS5
34nwq9fEjSvB2SWx2hBlqi8jq+J34OhObMuldWo+s/npRQoSK6oGnxSjUzBRMB0G
A1UdDgQWBBRDKIK7n7QELH+BkqQKEc1FPGSzHzAfBgNVHSMEGDAWgBRDKIK7n7QE
LH+BkqQKEc1FPGSzHzAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA4GMADCB
iAJCAYrPLJ/V/WADj8LJgCvPCLZMTcYSm3Ch2YlGj01vDIS9raOpmjPAZr7z/MaC
hKYl8jIxAcQ8+0wTkGrADk26/KbVAkIBm8IStutr7hHzSF7gnt1f3xL0isKTsCmU
TpTR0yQXX8dcpDIHq2PS8B+APDMwunz8XuPBmhcS9rRxj2tdjTDeWrs=
-----END CERTIFICATE-----
""",
    'pss': """-----BEGIN CERTIFICATE-----
MIIDZTCCAhmgAwIBAgIUYTnzBSeLWNN58jaEZLGiqqHNe/wwQQYJKoZIhvcNAQEK
MDSgDzANBglghkgBZQMEAgEFAKEcMBoGCSqGSIb3DQEBCDANBglghkgBZQMEAgEF
AKIDAgEgMA4xDDAKBgNVBAMMA3BzczAeFw0yNjExMTExMDIwMzNaFw0yNjExMTQx
MDIwMzNaMA4xDDAKBgNVBAMMA3BzczCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
AQoCggEBALjTxuuPjtNOoohqEf8MZZB1pY1XBqwnOYeV76TwKJwEIMywN2CcuuNv
5BuDM/ou3OsIE7tGP/lOonyHmVPe/JQGuXPXqasOE3QtcHAEUMcvSM9JalKAGxY0
wkHkdGD/uBYmZ6JtRj6/upcLZkMnuFV23pLcfF/79/eVuIJYpD0wk+OF4Fs858dK
vqlAe4XXUM+BtlW2gPXDeKlNAjKYPI92UudYcMTq1JO+RCi8k6+Ly7XeuLlbkIUK
R68CYtoaWEFihMYIFF0m/Ypsvj7cQutVUkqX3LGbEaTG9MaLew/l6TEhswCcqmAB
pKq2gjFFHDtRK3sp8PGklaXBn6YTxScCAwEAAaNTMFEwHQYDVR0OBBYEFNyoyUKb
rY19sv9+43xfWBZexoUQMB8GA1UdIwQYMBaAFNyoyUKbrY19sv9+43xfWBZexoUQ
MA8GA1UdEwEB/wQFMAMBAf8wQQYJKoZIhvcNAQEKMDSgDzANBglghkgBZQMEAgEF
AKEcMBoGCSqGSIb3DQEBCDANBglghkgBZQMEAgEFAKIDAgEgA4IBAQAndjF3kYND
wVlNpNhtv6xkfEyDoGFL6waCDUA4OUBkh1VW7OrEeUpEa9HNCBrWd7FAWZTiuSpv
mXUOLCbuOV8wAXWhImqKi+kHEhi69fnkt6gekBdmbQpNZ0xLADYJCro0BWQNMoSK
DbBcuCpkJGQJvFwP2avwNmlJS67b+/FEzJg/ZdIsiNO5Al93jrFkNXmcqgPIBYzA
QUWvna34skT6Ou1IeAQN7VbnMGZMpH7076JIV5R1WYNMmgH9mGmGwWFNpFVkqtiD
P9DYQZmUPiwvDe59FEVWB90/vUHY92kbL1hmlZ4JKh8UZ4TB59hWuriAY5c4/co8
o3AvGIbi2hOe
-----END CERTIFICATE-----
""",
    'pss2': """-----BEGIN CERTIFICATE-----
MIIDZzCCAhugAwIBAgIUGU4YCkBWo6oUXrkxvd6e8r2vGkQwQQYJKoZIhvcNAQEK
MDSgDzANBglghkgBZQMEAgIFAKEcMBoGCSqGSIb3DQEBCDANBglghkgBZQMEAgIF
AKIDAgEwMA8xDTALBgNVBAMMBHBzczIwHhcNMjYxMTExMTAyMDMzWhcNMjYxMTE0
MTAyMDMzWjAPMQ0wCwYDVQQDDARwc3MyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
MIIBCgKCAQEA0iLnXCqdi9OY5DCtveDjz9Jevm4rSwBuwSdoyGFxSc6BiF/IGyzb
KfNhxq0r2BUw+llopAcW91dz6tVII9izcIU/7RO90im+5wNJ3YsbCZxIdOYGIZb/
hq90FHXWCRvcJdzvzH41aKrJNu0/BiVaXe5JohgF/f1kGndcIRe4dTuOZrKWb786
yUdrmY2RyfFLahOBe6bU0q6b3VxD7Whnrl4UjWg9bKuZOIsFa2IRJI5mjkIu5D0O
tNszAA+8BKddOy2d6pINEeLTUpw1rUxw93YMZAfziCj6IXakq8mKmfDQF8jl6/q2
LlZ1E/U7KhLevx32QLydsmvvkNmLernGCQIDAQABo1MwUTAdBgNVHQ4EFgQUrcyc
K4vdVw8dNBkJzc1PZD6YSqAwHwYDVR0jBBgwFoAUrcycK4vdVw8dNBkJzc1PZD6Y
SqAwDwYDVR0TAQH/BAUwAwEB/zBBBgkqhkiG9w0BAQowNKAPMA0GCWCGSAFlAwQC
AgUAoRwwGgYJKoZIhvcNAQEIMA0GCWCGSAFlAwQCAgUAogMCATADggEBAD/bLsWw
XkZHqXzhQE4VQclc6/3ncNwvQ619tKlAjH2kWW/Cn20nJ+IWt+n3JVxHxJ5rBWGm
U7Ulg/C2e7p1WM9EhaX44ANWQPg/9Z8Ew0lJviysTpWh5W6PUm8OAtlVba+ExUR3
3HscVYc05OkmAPRFPwplKBMRRu5IPOmtGKhhyNMYfGnT5BsDWXTvf+WsDUNRtHRU
Jk7xgw9vc6CcmtU5uic4/KA0PzMi8QGYiaD/7y+imPeViMzxszpUM0H4GLTGynAW
78+BdptHZ3twMyhMP9UNQI+DeMhvseUN7S81J2hDtYuKlmqG/3VLtKuRr+cGI77k
ifPFATPonH75MTQ=
-----END CERTIFICATE-----
""",
}

# openssl keys: (algorithm, private key of a, public key of b, shared secret)
AGREE = [
    ('ECDH', "308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b02010104209d45bf463f5be6def0533dee9675333c8e2cd0431a8331dcf49bfc040a29958ba14403420004235bc7476efcb05de0f0cba973411ce7d1aae745282e990af2bf3662d1b614279fd350a7725a80586475f1c11b1e5abaa7ad7454d8ff31accc50973db0f4e69d",
     "3059301306072a8648ce3d020106082a8648ce3d0301070342000403c28f0dcd249f60aeb1df9c576ba32eeba9b3b3db1e52f05352541483442f12d73b3d417f930ad69b594dacabbf84e38f03b3358ba16f8bb8688b32a882b124",
     "5e75065e04aad84f717c6690bd8af91cb73b740b1121a0955b10a278b6a5eb06"),
    ('ECDH', "3081b6020100301006072a8648ce3d020106052b8104002204819e30819b02010104305f3568a7908bde3d84f8bc08e7e119ad5a847b9623ccb3664a253f1c39c53b67d3980ae4a68c52954d7ca7a4dd0982a6a1640362000481d0a59b308b7a8970f5ccbd6f4ca85d0ad531a42a39a5934c98226c5539535bfba0cff3b075ddd464ef244c59b8221b58782f87ca64fb7c97f060749e72d191ce052cbd9394f571048ba9e442c8313ca25d7a091a022b76104e8481e5b8d8fc",
     "3076301006072a8648ce3d020106052b8104002203620004c90c5277c5dd62a60e3d80170ea7ce6c14d2973bd2fae9053469aaed6d687c8cf95501bf51567da65bbd1e13eb3637b45e28a713cbb6e9684bf4eecd58b4a9d30eb8abf45ed26fbf436680c687fd45eda25884f4f38d6b0b1b65a8e59ef6ee36",
     "40c93db5bfc29179913391354037f029cdba6476dbf54f94d4ceab1d2e3e54ffe4193aba5a0f7c78a527e54c809698c9"),
    ('ECDH', "3081ee020100301006072a8648ce3d020106052b810400230481d63081d3020101044200011abff5d58e92f4a7d98ca3fa823cdfec3bed27b17b4b6b0e8378383f2fdea3867acec5e7a9fcc330ad0da744816e63086ed540f84d078bb04bb8215989306b77a181890381860004004309e7cf0cfdf07960e15dd09a25d009d4c39007dc4e4c783513ea4a5dcb0c90c17848ab87a8984f3f88799fcb6637c725c72583f705f12058b5ba9ff056df221501ae13f1586f61c82c22ab1b1cc36dd981053dd3a62aad147fa83f77bae90277cd1434a9d08a0348a8f22e162a330361906fc5b22318f8c919c3b6b20251142ffac1",
     "30819b301006072a8648ce3d020106052b81040023038186000400000a89d70f6f59f3da10a0bef5c27d8ad3a1f123e238df17ec196580f320ab793907bf98e5ab27c9c8da0dfe18d8e9042fda47e76beb24aa2beaa829cc1ee4b7a80174b7690bca3a5b01ae1a3e7d233cde19692555f873a8ee8eb5af12164ba506b0258f1b2def038f1f21de584c41078a2666c8c88ccd36b66184e1054e59b31a24e0",
     "0155269c7e3183cc760fa1d5794acfb0c36527dc375efb9a798121812203687baf5b083b485e8d1bcd3a66b0cfd2107692dc12c6a5582294a876e2b69e314f359d71"),
    ('X25519', "302e020100300506032b656e0422042020a931e598900515cb0c38c2a0af830e512a6e42bb60b12d2eff6e650cada272",
     "302a300506032b656e032100a61e8509846005949bed2b49ada1ff9c062e9a373d1986d4ba46ca12ad571e12",
     "6d46f413058d0bad63c8256434b57e3282cd3add0c9949b80f9ae64c143b9004"),
    ('X448', "3046020100300506032b656f043a043888f3376c5c08762a731c0c6dd1c5bceb0ec5e7c7b492145ec01ee221dbb6042fc69618833f2b1eb2b37a92e6b7c74a0b31894edbb83cf1db",
     "3042300506032b656f03390015dfc15a3e960585a02053291fa52988ee1920b12600f791e6e92a94131425b863254ffe65dad24a3f23abbc7e79254ce13cfdfe525e63b2",
     "79e36e0738564ba02589b1147d68d5005aa49e9cabfb5b90b2a152a1af2d202b2ba046923426f6ced5b4cde40f9d49475bc41afa2207b23b"),
    ('DH', "3082013f0201003082011706092a864886f70d010301308201080282010100ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b139b22514a08798e3404ddef9519b3cd3a431b302b0a6df25f14374fe1356d6d51c245e485b576625e7ec6f44c42e9a637ed6b0bff5cb6f406b7edee386bfb5a899fa5ae9f24117c4b1fe649286651ece45b3dc2007cb8a163bf0598da48361c55d39a69163fa8fd24cf5f83655d23dca3ad961c62f356208552bb9ed529077096966d670c354e4abc9804f1746c08ca18217c32905e462e36ce3be39e772c180e86039b2783a2ec07a28fb5c55df06f4c52c9de2bcbf6955817183995497cea956ae515d2261898fa051015728e5a8aacaa68ffffffffffffffff020102041f021d01683a56f8cbfbc4bd938d6f9ad01bfc53ae57a838058cf77d7b3ed851",
     "308202253082011706092a864886f70d010301308201080282010100ffffffffffffffffc90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b139b22514a08798e3404ddef9519b3cd3a431b302b0a6df25f14374fe1356d6d51c245e485b576625e7ec6f44c42e9a637ed6b0bff5cb6f406b7edee386bfb5a899fa5ae9f24117c4b1fe649286651ece45b3dc2007cb8a163bf0598da48361c55d39a69163fa8fd24cf5f83655d23dca3ad961c62f356208552bb9ed529077096966d670c354e4abc9804f1746c08ca18217c32905e462e36ce3be39e772c180e86039b2783a2ec07a28fb5c55df06f4c52c9de2bcbf6955817183995497cea956ae515d2261898fa051015728e5a8aacaa68ffffffffffffffff02010203820106000282010100c73254b8f1c3a8f8eca4f260f3f30f039d12c3a948be2dfca8bd3069d34d8a3fc9519054a49a93d9def98ec8309b7bf79314c38674c13ac190fefd0187a9958354099a0b93b1a84c63b24fcf5d6a377daa78f5b7488421aff3ca08eb2647c5980dc2d28901d544d5e53206cb1829f30fdc1659ee992cbb46e4517426f5d23b8d7b92a218bbc6b892c4046f65c77b21fda3c44b534a4e1274dcb3cabff9f635c6e028087454c97e194b4e7a573cb3bdb55045672f8b25112e3cecc818ffae0aa5df0af1bb82052adfd7c42562b504c6bd9e885d9b7e0704ea656cdb31beace03b2ea9f3f3b7194ee5c59b557301002496dc60cffc252954fffe3a8548088ffb03",
     "1c8c40b390c8328271c07ac89577e7aa214ed200ee24d51a8f8d65a02bb8bd06516dde469d3fca1bb771ebf12dada6c79e2e5e88e2370d10912537da4d94ec52f14778f0fe10873567c2a583ca59647eda41a6fd761ba0956185bb27d990728875de225b6af23a7208ac9dc20db039b3dc0082205e08690cc7628ff4d0734d1922748799476bb31ad0da93107e2b86dd2bd8e3979b87062b5b82a546daee5c2bb8721d77f083ca8e301c09680212e96c5b8e2c9ee28276bb733f99368acaffb48352ad158a7612194b5fe52a9cb4c7fa7512d89b8ec58d72a98b21032b67d8bc45956960949635800f8f6517dc1c008bc6b19ff52c80b9ecbf3d80e5bfa6a12b"),
]



def J(name):
    return api.lookup_host(name).py


def load(name):
    return X509CertImpl(split_certificates(CERTS[name].encode())[0])


class Signatures(unittest.TestCase):
    def test_self_signed_verify(self):
        for name in CERTS:
            cert = load(name)
            cert.verify(cert.getPublicKey())

    def test_tampered_signature_is_rejected(self):
        for name in CERTS:
            der = bytearray(split_certificates(CERTS[name].encode())[0])
            der[-3] ^= 1
            cert = X509CertImpl(bytes(der))
            with self.assertRaises(J("java.security.SignatureException")):
                cert.verify(cert.getPublicKey())

    def test_tampered_body_is_rejected(self):
        der = bytearray(split_certificates(CERTS["prime256v1"].encode())[0])
        der[40] ^= 1
        try:
            cert = X509CertImpl(bytes(der))
            cert.verify(cert.getPublicKey())
        except (J("java.security.SignatureException"), J("java.security.cert.CertificateException"), Exception):
            return
        self.fail("accepted")

    def test_pss_parameters(self):
        self.assertEqual(load("pss")._pss_parameters(), ("sha256", "sha256", 32))
        self.assertEqual(load("pss2")._pss_parameters()[:2], ("sha384", "sha384"))

    def test_wrong_key_type(self):
        with self.assertRaises(J("java.security.InvalidKeyException")):
            load("prime256v1").verify(load("pss").getPublicKey())


def bytes_of(array):
    return bytes(b & 255 for b in array)


class KeyAgreement(unittest.TestCase):
    def test_secrets_equal_openssl(self):
        for algorithm, private, public, secret in AGREE:
            kf = J("java.security.KeyFactory").getInstance("EC" if algorithm == "ECDH" else "XDH" if algorithm.startswith("X") else "DH")
            a = kf.generatePrivate(J("java.security.spec.PKCS8EncodedKeySpec")(to_java(bytes.fromhex(private))))
            b = kf.generatePublic(J("java.security.spec.X509EncodedKeySpec")(to_java(bytes.fromhex(public))))
            ka = J("javax.crypto.KeyAgreement").getInstance(algorithm)
            ka.init(a)
            ka.doPhase(b, 1)
            self.assertEqual(bytes_of(ka.generateSecret()), bytes.fromhex(secret), algorithm)

    def test_encodings_equal_the_jdk(self):
        for algorithm, private, public, secret in AGREE[3:]:
            kf = J("java.security.KeyFactory").getInstance("XDH" if algorithm.startswith("X") else "DH")
            a = kf.generatePrivate(J("java.security.spec.PKCS8EncodedKeySpec")(to_java(bytes.fromhex(private))))
            b = kf.generatePublic(J("java.security.spec.X509EncodedKeySpec")(to_java(bytes.fromhex(public))))
            self.assertEqual(bytes_of(a.getEncoded()), bytes.fromhex(private))
            self.assertEqual(bytes_of(b.getEncoded()), bytes.fromhex(public))

    def test_rfc7748_vector(self):
        from dexvm import jkeys
        scalar = bytes.fromhex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4")
        u = int.from_bytes(bytes.fromhex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"), "little")
        out = jkeys.x_multiply("X25519", scalar, u).to_bytes(32, "little")
        self.assertEqual(out.hex(), "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")

    def test_generated_pairs_agree(self):
        for algorithm in ("EC", "DH", "X25519", "X448", "XDH"):
            g = J("java.security.KeyPairGenerator").getInstance(algorithm)
            a, b = g.generateKeyPair(), g.generateKeyPair()
            ka = J("javax.crypto.KeyAgreement").getInstance("ECDH" if algorithm == "EC" else algorithm)
            kb = J("javax.crypto.KeyAgreement").getInstance("ECDH" if algorithm == "EC" else algorithm)
            ka.init(a.getPrivate())
            ka.doPhase(b.getPublic(), 1)
            kb.init(b.getPrivate())
            kb.doPhase(a.getPublic(), 1)
            self.assertEqual(bytes_of(ka.generateSecret()), bytes_of(kb.generateSecret()))

    def test_wrong_curve_is_rejected(self):
        g = J("java.security.KeyPairGenerator").getInstance("EC")
        g.initialize(256)
        a = g.generateKeyPair()
        g.initialize(384)
        b = g.generateKeyPair()
        ka = J("javax.crypto.KeyAgreement").getInstance("ECDH")
        ka.init(a.getPrivate())
        with self.assertRaises(J("java.security.InvalidKeyException")):
            ka.doPhase(b.getPublic(), 1)

    def test_ecdsa_sign_and_verify(self):
        for bits in (256, 384, 521):
            g = J("java.security.KeyPairGenerator").getInstance("EC")
            g.initialize(bits)
            pair = g.generateKeyPair()
            signer = J("java.security.Signature").getInstance("SHA256withECDSA")
            signer.initSign(pair.getPrivate())
            signer.update(to_java(b"message"))
            signature = signer.sign()
            for text, expect in ((b"message", 1), (b"other", 0)):
                verifier = J("java.security.Signature").getInstance("SHA256withECDSA")
                verifier.initVerify(pair.getPublic())
                verifier.update(to_java(text))
                self.assertEqual(verifier.verify(signature), expect)


class Text(unittest.TestCase):
    def test_text_layout(self):
        text = str(load("prime256v1").toString())
        self.assertIn("  Key:  Sun EC public key, 256 bits\n  public x coord: ", text)
        self.assertIn("parameters: secp256r1 [NIST P-256,X9.62 prime256v1] (1.2.840.10045.3.1.7)", text)
        self.assertIn("Certificate Extensions: 3\n[1]: ObjectId: 2.5.29.35 Criticality=false\nAuthorityKeyIdentifier [", text)
        self.assertIn("[2]: ObjectId: 2.5.29.19 Criticality=true\nBasicConstraints:[\n  CA:true\n  PathLen: no limit\n]\n", text)
        self.assertIn("  Algorithm: [SHA256withECDSA]\n  Signature:\n0000: 30 ", text)
        self.assertTrue(text.endswith("\n\n]"))

    def test_pss_text(self):
        text = str(load("pss").toString())
        self.assertIn("Signature Algorithm: RSASSA-PSS, PSSParameterSpec[hashAlgorithm=SHA-256, maskGenAlgorithm=MGF1ParameterSpec"
                      "[hashAlgorithm=SHA-256], saltLength=32, trailerField=1], OID = 1.2.840.113549.1.1.10", text)
        self.assertIn("Sun RSA public key, 2048 bits\n  params: null\n  modulus: ", text)


class PhaserTree(unittest.TestCase):
    def test_child_advances_with_the_root(self):
        Phaser = J("java.util.concurrent.Phaser")
        root = Phaser(None, 1)
        child = Phaser(root, 2)
        self.assertEqual(root.getRegisteredParties(), 2)
        self.assertIs(child.getParent(), root)
        self.assertIs(child.getRoot(), root)
        self.assertEqual(child.arrive(), 0)
        self.assertEqual(root.getPhase(), 0)
        self.assertEqual(child.arrive(), 0)
        self.assertEqual(root.getArrivedParties(), 1)
        self.assertEqual(root.arrive(), 0)
        self.assertEqual(root.getPhase(), 1)
        self.assertEqual(child.getPhase(), 1)
        self.assertEqual(child.getArrivedParties(), 0)

    def test_empty_child_leaves_the_parent(self):
        Phaser = J("java.util.concurrent.Phaser")
        root = Phaser(None, 1)
        child = Phaser(root, 1)
        self.assertEqual(root.getRegisteredParties(), 2)
        child.arriveAndDeregister()
        self.assertEqual(root.getRegisteredParties(), 1)
        self.assertEqual(root.getPhase(), 0)
        root.arrive()
        self.assertEqual(root.getPhase(), 1)

    def test_threads_cross_a_tree(self):
        Phaser = J("java.util.concurrent.Phaser")
        root = Phaser()
        children = [Phaser(root, 2) for _ in range(2)]
        seen = []

        def worker(phaser):
            seen.append(phaser.arriveAndAwaitAdvance())
        threads = [threading.Thread(target=worker, args=(c,)) for c in children for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(10)
        self.assertEqual(seen, [1, 1, 1, 1])
        self.assertEqual(root.getPhase(), 1)


class StreamCount(unittest.TestCase):
    def test_sized_pipeline_is_skipped(self):
        seen = []

        class Peek:
            def accept(self, x):
                seen.append(x)

        class Fn:
            def apply(self, x):
                seen.append(x)
                return x
        self.assertEqual(BaseStream.from_items([1, 2, 3]).peek(Peek()).count(), 3)
        self.assertEqual(BaseStream.from_items([1, 2, 3]).map(Fn()).count(), 3)
        self.assertEqual(BaseStream.from_items(range(10)).skip(4).limit(3).count(), 3)
        self.assertEqual(seen, [])

    def test_unsized_pipeline_runs(self):
        seen = []

        class Peek:
            def accept(self, x):
                seen.append(x)

        class Pred:
            def test(self, x):
                return x > 1
        self.assertEqual(BaseStream.from_items([1, 2, 3]).peek(Peek()).filter(Pred()).count(), 2)
        self.assertEqual(seen, [1, 2, 3])
        self.assertEqual(BaseStream.from_items(iter([1, 2, 3])).peek(Peek()).count(), 3)


if __name__ == "__main__":
    unittest.main()
