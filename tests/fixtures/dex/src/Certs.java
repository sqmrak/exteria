import java.io.*;
import java.math.BigInteger;
import java.security.*;
import java.security.cert.*;
import java.security.interfaces.*;
import java.security.spec.*;
import java.util.*;
import javax.security.auth.x500.X500Principal;

/** X.509 parsing, X500Principal, CertificateFactory and KeyStore. the certificates were made with openssl for this test */
public class Certs {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    static final String CA =
        "-----BEGIN CERTIFICATE-----\n" +
        "MIIDljCCAn6gAwIBAgIUCxBFfCnMsltfob//z3iojEQK/lgwDQYJKoZIhvcNAQEL\n" +
        "BQAwUTELMAkGA1UEBhMCVVMxFTATBgNVBAoMDEV4dGVyaWEgVGVzdDEUMBIGA1UE\n" +
        "CwwLRGV4IFJ1bnRpbWUxFTATBgNVBAMMDFRlc3QgUm9vdCBDQTAeFw0yNjExMTEw\n" +
        "ODQ3MjNaFw00NjExMDYwODQ3MjNaMFExCzAJBgNVBAYTAlVTMRUwEwYDVQQKDAxF\n" +
        "eHRlcmlhIFRlc3QxFDASBgNVBAsMC0RleCBSdW50aW1lMRUwEwYDVQQDDAxUZXN0\n" +
        "IFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCq75BRU1wa\n" +
        "0gTn5Kfl+dyW7K2P7gHtzEVGw5Tr7SECSNNwrLCGivXYyyWAFS2kdwdafYk6fmQ+\n" +
        "b/+t90R3lFgXwpLNKoMVRZNS8SDs75FrHmwhlSm5JzeLyPJOCE4n8P9u+Ak/Bahr\n" +
        "6PxYeSJLd2RxgT/Q9TUkccXO4F1kgQDkW+mUQ2K+FYyEVONaANEFTxmlLfXFIrFR\n" +
        "AMYc3x4EcnQQqtovv5jGsJRz/bZvKe2XskH1hudVmUYc5SwwhZ9ptrSugruk4x2e\n" +
        "P5NrpP/z+oKjhl+ObyPX7lmy1O36nkVznwZ98CC4iI22kRkl0FJIEWQCoPyCmPS4\n" +
        "6zeGhQeFgZBnAgMBAAGjZjBkMB0GA1UdDgQWBBTHr0weaP3EKXz8b7M07ITtxz3q\n" +
        "LDAfBgNVHSMEGDAWgBTHr0weaP3EKXz8b7M07ITtxz3qLDASBgNVHRMBAf8ECDAG\n" +
        "AQH/AgECMA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEAfaeIA2XZ\n" +
        "uWcS8ol2hpBrnAjbNKBHSTMRqwyRN8tHq0fBshIv/xPUPgtgdfhOdyZJUB2cQu/F\n" +
        "VKExg8tpTuMRcMx8m9cX6E35OG0+HuMpc5o0UAIZnfWxS7/VEeNMBwepVBK3Kmp5\n" +
        "qltihMd9wxtKZ2P/4ijTetK19HK6nUvaFWqRlkqQsyGHZYiqfH+89pd4GfuEABpI\n" +
        "USTk06kMZrEdsmvf27Qzk4QGvWmx9FMPt9+qY6Xnupei8ay3jUKDQVUXjXTgMBkt\n" +
        "EJNIANUs9RYfPr0VU8gqYWqoXDDdJCiKX2EbL5ieZBGjf7u8a6uGMNpwomjTKWOV\n" +
        "ldWWSHm7OZ/aAw==\n" +
        "-----END CERTIFICATE-----\n";
    static final String LEAF =
        "-----BEGIN CERTIFICATE-----\n" +
        "MIIEEjCCAvqgAwIBAgIUOcQle/28JFjfu6xnnfukgG+WDpAwDQYJKoZIhvcNAQEM\n" +
        "BQAwUTELMAkGA1UEBhMCVVMxFTATBgNVBAoMDEV4dGVyaWEgVGVzdDEUMBIGA1UE\n" +
        "CwwLRGV4IFJ1bnRpbWUxFTATBgNVBAMMDFRlc3QgUm9vdCBDQTAeFw0yNjExMTEw\n" +
        "ODQ3NDFaFw0zNjExMDgwODQ3NDFaMGIxCzAJBgNVBAYTAkRFMQ8wDQYDVQQIDAZC\n" +
        "YXllcm4xETAPBgNVBAcMCE3DvG5jaGVuMRQwEgYDVQQKDAtUw6lzdCwgSW5jLjEZ\n" +
        "MBcGA1UEAwwQTcO8bGxlciArIFPDtmhuZTCCASIwDQYJKoZIhvcNAQEBBQADggEP\n" +
        "ADCCAQoCggEBAN3XIEP4jJsoLTTQmOCCrKnYKyDhHJAkEJKz5LMWOL9xAGj1IjUC\n" +
        "ZHfwa5JQO8t6vA8VwHp0Rk9Jhvj0tVTNg5n7HQjH3Ld+/gi4/mL8o2qcV61XMG5K\n" +
        "pEjFUJkY70dzkcHDrgVTYgfiEvSnsDmwsSSNmnJ2Eyz8gPSrVQCv8ci59EwZEp33\n" +
        "AJ9zumg9lVMBEfKN9YzoSRynyOK3K/hU6X8rXhJrcTOVtMs+gHeqa3H7ZM/PMVuq\n" +
        "l3AZfjLPCat5KybJWO/w042qqKqfpo/n3txzrtoKTG7qV0YK9QGQ/Qfo33S7SjRC\n" +
        "DJ5fdk2qs/T6OsPf1Ak5rwliWAtICQrE16MCAwEAAaOB0DCBzTBOBgNVHREERzBF\n" +
        "ghB0ZXN0LmV4YW1wbGUuY29tgg0qLmV4YW1wbGUub3JnhwQKAQIDgQVhQGIuY4YV\n" +
        "aHR0cHM6Ly9leGFtcGxlLmNvbS94MAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQD\n" +
        "AgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAdBgNVHQ4EFgQU+hJW\n" +
        "1tBT+8rLzaozgkakYNqKT9QwHwYDVR0jBBgwFoAUx69MHmj9xCl8/G+zNOyE7cc9\n" +
        "6iwwDQYJKoZIhvcNAQEMBQADggEBAA1rqGYqaTbFZmBQ8ZuOFD4BIZUx1tY3/I0g\n" +
        "mGo5V1dw+Q4DEV5maNu3b+cRRG3EBYoqGEYuXrb5pKvX37/BLEswv0499adUOAhv\n" +
        "TQXwyK/EZtSATOf9SgXpJB3+Sto2yASXEV8P2gvR3mvPeOVChx6rvMZb1QSlj+FO\n" +
        "VvVEk7BfLJnospE8tnIiBA5TLKBMpdmRCGP0BbsdNG9/LtYKbO2BDMIpd/3DmGPv\n" +
        "/5AsgxXgaLL4M0cS/H4bBiMK11lNQPbXo4W93aQWSzjE8peqx3h4zQDoefuvWISi\n" +
        "sHPhmBPcOgUPZIbAZztUyluxlSAjOzt8ecjipW0+enFNA95BOFA=\n" +
        "-----END CERTIFICATE-----\n";
    static final String EC =
        "-----BEGIN CERTIFICATE-----\n" +
        "MIIBqTCCAU+gAwIBAgIUFCwsapbjYsrJHTxhWv5oMFyTZ0QwCgYIKoZIzj0EAwIw\n" +
        "KjEXMBUGA1UEAwwOZWMuZXhhbXBsZS5jb20xDzANBgNVBAoMBkVDIE9yZzAeFw0y\n" +
        "NjExMTEwODQ3MjNaFw0zNjExMDgwODQ3MjNaMCoxFzAVBgNVBAMMDmVjLmV4YW1w\n" +
        "bGUuY29tMQ8wDQYDVQQKDAZFQyBPcmcwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNC\n" +
        "AARrgL6/xUBOwkf/gapRz3vuuEyD0cLARHgZYhYvgXf3I04dYRgMuAcbTxEoDXD2\n" +
        "ONytQ88VsaFGX6xjjCUxcsLFo1MwUTAdBgNVHQ4EFgQUdysF1GlmisrXBqP9v99Q\n" +
        "LxlNR9gwHwYDVR0jBBgwFoAUdysF1GlmisrXBqP9v99QLxlNR9gwDwYDVR0TAQH/\n" +
        "BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiBjiNNLkWqAqGHmjZZsy0yA2hQdY2ZB\n" +
        "KtdQxoqgm7NgcwIhAOMWUgvV1cZlFD+nU/HyXUBeLGowX+5ztfqcBQ+2GtKR\n" +
        "-----END CERTIFICATE-----\n";
    static final String EXPIRED =
        "-----BEGIN CERTIFICATE-----\n" +
        "MIIDgzCCAmugAwIBAgIUOcQle/28JFjfu6xnnfukgG+WDpEwDQYJKoZIhvcNAQEL\n" +
        "BQAwUTELMAkGA1UEBhMCVVMxFTATBgNVBAoMDEV4dGVyaWEgVGVzdDEUMBIGA1UE\n" +
        "CwwLRGV4IFJ1bnRpbWUxFTATBgNVBAMMDFRlc3QgUm9vdCBDQTAeFw0wMDAxMDEw\n" +
        "MDAwMDBaFw0wMTAxMDEwMDAwMDBaMGIxCzAJBgNVBAYTAkRFMQ8wDQYDVQQIDAZC\n" +
        "YXllcm4xETAPBgNVBAcMCE3DvG5jaGVuMRQwEgYDVQQKDAtUw6lzdCwgSW5jLjEZ\n" +
        "MBcGA1UEAwwQTcO8bGxlciArIFPDtmhuZTCCASIwDQYJKoZIhvcNAQEBBQADggEP\n" +
        "ADCCAQoCggEBAN3XIEP4jJsoLTTQmOCCrKnYKyDhHJAkEJKz5LMWOL9xAGj1IjUC\n" +
        "ZHfwa5JQO8t6vA8VwHp0Rk9Jhvj0tVTNg5n7HQjH3Ld+/gi4/mL8o2qcV61XMG5K\n" +
        "pEjFUJkY70dzkcHDrgVTYgfiEvSnsDmwsSSNmnJ2Eyz8gPSrVQCv8ci59EwZEp33\n" +
        "AJ9zumg9lVMBEfKN9YzoSRynyOK3K/hU6X8rXhJrcTOVtMs+gHeqa3H7ZM/PMVuq\n" +
        "l3AZfjLPCat5KybJWO/w042qqKqfpo/n3txzrtoKTG7qV0YK9QGQ/Qfo33S7SjRC\n" +
        "DJ5fdk2qs/T6OsPf1Ak5rwliWAtICQrE16MCAwEAAaNCMEAwHQYDVR0OBBYEFPoS\n" +
        "VtbQU/vKy82qM4JGpGDaik/UMB8GA1UdIwQYMBaAFMevTB5o/cQpfPxvszTshO3H\n" +
        "PeosMA0GCSqGSIb3DQEBCwUAA4IBAQCOjH0uxHxJjiLLXAVg6QhiJGKk136gL1v1\n" +
        "dxhIxIVvg8DSXCP43AxD+tXH9/3EK0Wys1PYDLZ4SwZBNQh7TZvzGHBIcEqpoHWh\n" +
        "aQb0MmIKz1YrYvtgmhAS6tyy630HE2/DqUlcB9GAlluG8Bu6wyjY4CIfpY0gsyvt\n" +
        "VgXvHCJGA+31zCSaNGVQ96cp4EQJ6TEpAO2ZQrpQtMJ2pePzV+Oq57PXUN0agA4K\n" +
        "iCtqVSKFZ1NBVIfDb5AIJKjork2nNSVobZ/x4nq8VWrsIxqYNuDkynxJ66+GMLT+\n" +
        "ICLryBK8dzl/7HPpm9qGCsMr1CukvGeefn0NbF2310+FTaeova8Y\n" +
        "-----END CERTIFICATE-----\n";
    static final String FUTURE =
        "-----BEGIN CERTIFICATE-----\n" +
        "MIIDhzCCAm+gAwIBAgIUOcQle/28JFjfu6xnnfukgG+WDpIwDQYJKoZIhvcNAQEL\n" +
        "BQAwUTELMAkGA1UEBhMCVVMxFTATBgNVBAoMDEV4dGVyaWEgVGVzdDEUMBIGA1UE\n" +
        "CwwLRGV4IFJ1bnRpbWUxFTATBgNVBAMMDFRlc3QgUm9vdCBDQTAiGA8yMDkwMDEw\n" +
        "MTAwMDAwMFoYDzIxMDAwMTAxMDAwMDAwWjBiMQswCQYDVQQGEwJERTEPMA0GA1UE\n" +
        "CAwGQmF5ZXJuMREwDwYDVQQHDAhNw7xuY2hlbjEUMBIGA1UECgwLVMOpc3QsIElu\n" +
        "Yy4xGTAXBgNVBAMMEE3DvGxsZXIgKyBTw7ZobmUwggEiMA0GCSqGSIb3DQEBAQUA\n" +
        "A4IBDwAwggEKAoIBAQDd1yBD+IybKC000Jjggqyp2Csg4RyQJBCSs+SzFji/cQBo\n" +
        "9SI1AmR38GuSUDvLerwPFcB6dEZPSYb49LVUzYOZ+x0Ix9y3fv4IuP5i/KNqnFet\n" +
        "VzBuSqRIxVCZGO9Hc5HBw64FU2IH4hL0p7A5sLEkjZpydhMs/ID0q1UAr/HIufRM\n" +
        "GRKd9wCfc7poPZVTARHyjfWM6Ekcp8jityv4VOl/K14Sa3EzlbTLPoB3qmtx+2TP\n" +
        "zzFbqpdwGX4yzwmreSsmyVjv8NONqqiqn6aP597cc67aCkxu6ldGCvUBkP0H6N90\n" +
        "u0o0QgyeX3ZNqrP0+jrD39QJOa8JYlgLSAkKxNejAgMBAAGjQjBAMB0GA1UdDgQW\n" +
        "BBT6ElbW0FP7ysvNqjOCRqRg2opP1DAfBgNVHSMEGDAWgBTHr0weaP3EKXz8b7M0\n" +
        "7ITtxz3qLDANBgkqhkiG9w0BAQsFAAOCAQEAa3hdj+Yf+xdjYisJSxUT5xBelLyT\n" +
        "jnHQsCW9LDf/hsnj2QBoS/GDIIsxF9rAtg6cMW7jHs9wJBCE63CewV+LboX3vbU1\n" +
        "ng+QpmAO7IODkeQdcrgZJ4amgE3c7bUNmkY82QenfclmfTeWsgYFR2MZfCaiDP76\n" +
        "Qaz2PmZ3HkWG1djhO16NVZyKBvJArHvPHXgjgjDCcYqxUf8+UZUVyJuknnJWtQ4g\n" +
        "vKymnbFyqazu+nQFT0684wTIIuO0M3tq11rpRdUfUiYQ1LroZU4mJP/X94tGZrIQ\n" +
        "mf6F3dlHR3MqoY5OORtHlE+su3t82BJX5eWeADCUkBNzc0nPnPpQ+O/OeA==\n" +
        "-----END CERTIFICATE-----\n";

    static X509Certificate cert(String pem) throws Exception {
        return (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(pem.getBytes("US-ASCII")));
    }
    static String hex(byte[] b) { StringBuilder s = new StringBuilder(); for (byte x : b) s.append(String.format("%02x", x)); return s.toString(); }
    static String sortedOids(Set<String> set) { return set == null ? "null" : new TreeSet<>(set).toString(); }

    static void describe(String label, X509Certificate c) throws Exception {
        p(label + " basics", c.getVersion() + "," + c.getSerialNumber().toString(16).length() + "," + c.getType() + "," + c.getSigAlgName() + "," + c.getSigAlgOID() + "," + c.getEncoded().length
            + "," + c.getNotBefore().getTime() + "," + c.getNotAfter().getTime());
        p(label + " subject", c.getSubjectX500Principal().getName() + " | " + c.getSubjectX500Principal().getName(X500Principal.RFC1779) + " | " + c.getSubjectX500Principal().getName(X500Principal.CANONICAL));
        p(label + " issuer", c.getIssuerX500Principal().getName());
        p(label + " dn", c.getSubjectDN().getName() + " | " + c.getIssuerDN());
        p(label + " principal", c.getSubjectX500Principal());
        p(label + " constraints", c.getBasicConstraints() + "," + Arrays.toString(c.getKeyUsage()) + "," + c.getExtendedKeyUsage());
        p(label + " san", c.getSubjectAlternativeNames() + "," + c.getIssuerAlternativeNames());
        p(label + " ext oids", sortedOids(c.getCriticalExtensionOIDs()) + " " + sortedOids(c.getNonCriticalExtensionOIDs()) + " " + c.hasUnsupportedCriticalExtension());
        p(label + " key", c.getPublicKey().getAlgorithm() + "," + c.getPublicKey().getFormat() + "," + c.getPublicKey().getEncoded().length);
        PublicKey k = c.getPublicKey();
        if (k instanceof RSAPublicKey) p(label + " rsa", ((RSAPublicKey) k).getModulus().bitLength() + "," + ((RSAPublicKey) k).getPublicExponent());
        if (k instanceof ECPublicKey) {
            ECPublicKey e = (ECPublicKey) k;
            p(label + " ec", e.getW().getAffineX().bitLength() > 200 ? "x-ok" : "x-short");
            p(label + " ec params", e.getParams().getCurve().getField().getFieldSize() + "," + e.getParams().getCofactor() + "," + e.getParams().getOrder().bitLength());
        }
    }

    public static String run() throws Exception {
        out = new StringBuilder();
        X509Certificate ca = cert(CA), leaf = cert(LEAF), ec = cert(EC);
        describe("ca", ca);
        describe("leaf", leaf);
        describe("ec", ec);

        p("equals", leaf.equals(cert(LEAF)) + "," + leaf.equals(ca) + "," + (leaf.hashCode() == cert(LEAF).hashCode()) + "," + (leaf.hashCode() == ca.hashCode()) + "," + Arrays.equals(leaf.getEncoded(), cert(LEAF).getEncoded()));
        p("hash", leaf.hashCode() + "," + ca.hashCode());
        p("ext value", hex(leaf.getExtensionValue("2.5.29.15")) + "," + leaf.getExtensionValue("1.2.3.4"));
        p("tbs", leaf.getTBSCertificate().length + "," + leaf.getSignature().length);

        leaf.verify(ca.getPublicKey());
        ca.verify(ca.getPublicKey());
        p("verify", "ok");
        try { leaf.verify(leaf.getPublicKey()); } catch (SignatureException e) { p("verify wrong key", e.getMessage()); }
        try { leaf.verify(ec.getPublicKey()); } catch (InvalidKeyException e) { p("verify ec key", e.getClass().getSimpleName()); } catch (Exception e) { p("verify ec key", e.getClass().getSimpleName()); }

        ca.checkValidity();
        leaf.checkValidity(new Date(leaf.getNotBefore().getTime() + 1000));
        p("valid", "ok");
        X509Certificate expired = cert(EXPIRED), future = cert(FUTURE);
        try { expired.checkValidity(); } catch (CertificateExpiredException e) { p("expired", e.getClass().getSimpleName() + ":" + e.getMessage().startsWith("NotAfter: ")); }
        try { future.checkValidity(); } catch (CertificateNotYetValidException e) { p("future", e.getClass().getSimpleName() + ":" + e.getMessage().startsWith("NotBefore: ")); }
        try { leaf.checkValidity(new Date(0)); } catch (CertificateNotYetValidException e) { p("before epoch", "not yet valid"); }

        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        p("factory", cf.getType());
        Collection<? extends java.security.cert.Certificate> several = cf.generateCertificates(new ByteArrayInputStream((CA + LEAF + EC).getBytes("US-ASCII")));
        StringBuilder sb = new StringBuilder();
        for (java.security.cert.Certificate c : several) sb.append(((X509Certificate) c).getSubjectX500Principal().getName().length()).append(' ');
        p("several", several.size() + " " + sb);
        X509Certificate fromDer = (X509Certificate) cf.generateCertificate(new ByteArrayInputStream(ca.getEncoded()));
        p("der input", fromDer.equals(ca) + "," + fromDer.getSerialNumber().equals(ca.getSerialNumber()));
        try { cf.generateCertificate(new ByteArrayInputStream("garbage".getBytes())); } catch (CertificateException e) { p("garbage", e.getClass().getSimpleName()); }
        try { cf.generateCertificate(new ByteArrayInputStream(new byte[]{0x30, 0x03, 0x01, 0x01})); } catch (CertificateException e) { p("short der", e.getClass().getSimpleName()); }
        try { CertificateFactory.getInstance("NoSuchType"); } catch (CertificateException e) { p("unknown type", e.getMessage()); }

        X500Principal built = new X500Principal("CN=Duke, OU=JavaSoft, O=Sun Microsystems, C=US");
        p("principal", built.getName() + "|" + built.getName(X500Principal.RFC1779) + "|" + built.getName(X500Principal.CANONICAL) + "|" + built + "|" + built.getEncoded().length);
        p("principal equal", built.equals(new X500Principal("cn=duke,ou=javasoft,o=sun microsystems,c=us")) + "," + built.equals(new X500Principal("CN=Other")) + ","
            + (built.hashCode() == new X500Principal("cn=DUKE, ou=JavaSoft, o=Sun  Microsystems, c=US").hashCode()));
        X500Principal escaped = new X500Principal("CN=Smith\\, John + OU=a\\+b, O=\"Quoted, Co\"");
        p("principal escapes", escaped.getName() + "|" + escaped.getName(X500Principal.RFC1779));
        p("principal round trip", new X500Principal(built.getEncoded()).equals(built) + "," + new X500Principal(leaf.getSubjectX500Principal().getEncoded()).getName());
        p("principal oid", new X500Principal("1.2.3.4=#0c0141, CN=x").getName() + "|" + new X500Principal("EMAILADDRESS=a@b.c, CN=x").getName());
        try { new X500Principal("not a name"); } catch (IllegalArgumentException e) { p("bad name", "iae"); }
        try { built.getName("BOGUS"); } catch (IllegalArgumentException e) { p("bad format", e.getMessage()); }

        KeyStore ks = KeyStore.getInstance("PKCS12");
        try { ks.size(); } catch (KeyStoreException e) { p("unloaded", e.getMessage()); }
        ks.load(null, null);
        ks.setCertificateEntry("Root", ca);
        ks.setCertificateEntry("leaf", leaf);
        List<String> aliases = Collections.list(ks.aliases());
        Collections.sort(aliases);
        p("keystore", ks.size() + "," + aliases + "," + ks.containsAlias("ROOT") + "," + ks.isCertificateEntry("root") + "," + ks.isKeyEntry("root") + "," + ks.getType());
        p("keystore get", ks.getCertificate("root").equals(ca) + "," + ks.getCertificateAlias(leaf) + "," + ks.getCertificate("nope") + "," + ks.getCertificateAlias(ec));
        KeyStore.Entry entry = ks.getEntry("leaf", null);
        p("keystore entry", (entry instanceof KeyStore.TrustedCertificateEntry) + "," + ((KeyStore.TrustedCertificateEntry) entry).getTrustedCertificate().equals(leaf) + "," + ks.entryInstanceOf("leaf", KeyStore.TrustedCertificateEntry.class));
        ks.deleteEntry("leaf");
        p("keystore delete", ks.size() + "," + ks.containsAlias("leaf") + "," + (ks.getCreationDate("root") != null));
        try { ks.load(new ByteArrayInputStream(new byte[]{1, 2, 3}), "x".toCharArray()); } catch (IOException e) { p("keystore file", "ioe"); }
        try { KeyStore.getInstance("Nope"); } catch (KeyStoreException e) { p("keystore type", e.getMessage()); }
        return out.toString();
    }
}
