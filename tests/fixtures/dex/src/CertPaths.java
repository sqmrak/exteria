import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.PublicKey;
import java.security.KeyFactory;
import java.security.cert.*;
import java.util.*;
import javax.security.auth.x500.X500Principal;

/** certification paths, CRLs, selectors, cert stores, PKIX validation and path building */
public class CertPaths {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }
    interface Thrower { Object run() throws Exception; }
    static void t(String name, Thrower r) {
        try { p(name, r.run()); }
        catch (Throwable e) {
            StringBuilder sb = new StringBuilder(e.getClass().getName() + ": " + e.getMessage());
            if (e instanceof CertPathValidatorException) {
                CertPathValidatorException c = (CertPathValidatorException) e;
                sb.append(" | index=").append(c.getIndex()).append(" reason=").append(c.getReason());
                if (c.getCause() != null) sb.append(" cause=").append(c.getCause().getClass().getName()).append(": ").append(norm(String.valueOf(c.getCause().getMessage())));
            } else if (e instanceof CertPathBuilderException) {
                if (e.getCause() != null) sb.append(" | cause=").append(e.getCause().getClass().getName());
            }
            p(name, norm(sb.toString()));
        }
    }
    /** dates and ids that change from one run to the next are not shown */
    static String norm(String s) { return s.replaceAll("[A-Z][a-z]{2} [A-Z][a-z]{2} \\d{2} \\d{2}:\\d{2}:\\d{2} [A-Z0-9+:]+ \\d{4}", "DATE").replaceAll("@[0-9a-f]+", "@"); }

    static final String[] NAMES = {"root", "root2", "inter", "leaf", "leafrev", "leafexp", "leaffut", "leaf2", "noca", "underno", "deep", "underdeep"};
    static final String[] PEMS = {
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIC+jCCAeKgAwIBAgIUb2OwE/UMM6nn5JvYCUtyLVpjNRUwDQYJKoZIhvcNAQEL\n" +
            "BQAwFDESMBAGA1UEAwwJVGVzdCBSb290MCAXDTI2MTExMTExMDYxN1oYDzIwNTEw\n" +
            "NzAzMTEwNjE3WjAUMRIwEAYDVQQDDAlUZXN0IFJvb3QwggEiMA0GCSqGSIb3DQEB\n" +
            "AQUAA4IBDwAwggEKAoIBAQCUAUwYqhe2r6ysqa8F3s8x3BrUn9JXnnhHAgcqD/wA\n" +
            "yWYlAGJom7RGUzVBNHu+Hn+mt/J3j7CcWbf1jUE9VxF8TiFUWeNbjRR7Nva3hWpk\n" +
            "4RU0HOoonw48bXcLW4+m/RR/2nAyJsg+P865wDKQcRdoj5ut/oyDeD/XijbqGSVO\n" +
            "PGJhBDG4RQZ2aNXuChTldsbWI71ryCDp2JWKKEdc32UoWnu53UWFKWq8LKsj86yp\n" +
            "PlMK4/VNAxKaEXn77kOkn9kAFoT4TqHRx4zlYS831cQWrMO53S+JxSnMQIUq7bsa\n" +
            "YpqtOdGxYa800SF17iAq+Q8D0o7t4+I7CohSSOlMNI5nAgMBAAGjQjBAMA8GA1Ud\n" +
            "EwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBR7cLHVP4Yo2Ke2\n" +
            "x1EA1h6Hl9b6XTANBgkqhkiG9w0BAQsFAAOCAQEAhlLKbJQCoRUwXc/P4mHE0Llr\n" +
            "5xShXjXUKxnzdztwvmRl6keyHiGxHYA177ZyjEI9z0KEM4Mya+3Vtjf0Tfu5rax7\n" +
            "1eySG+m2PtlO5exAqFtdq84Xod5FMMQNclbbyfA0nSKzsyJxM8DukDFVCwack7Hk\n" +
            "asPEsnuAYtyFKBiammUMMB3Acw+I8+k3PJPfm7zfkBvMwLixD/IHwqDRbc9few5C\n" +
            "XdZATIIzpKeEIVCDYu4LarqN68CM7kjMNhZAdjpf0CidH3XY+SDQ2xKIVra1wCCY\n" +
            "t2sJcXvbw0fFNGvQ7hCMf2MsV7pD7YYo0gqbYbe2exQHQGT+QNcYyUvvSXXi2A==\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIC/DCCAeSgAwIBAgIUetYmAokwXwiO/aBEb6qRCDEWWoEwDQYJKoZIhvcNAQEL\n" +
            "BQAwFTETMBEGA1UEAwwKT3RoZXIgUm9vdDAgFw0yNjExMTExMTA2MTdaGA8yMDUx\n" +
            "MDcwMzExMDYxN1owFTETMBEGA1UEAwwKT3RoZXIgUm9vdDCCASIwDQYJKoZIhvcN\n" +
            "AQEBBQADggEPADCCAQoCggEBAOOIYlMwrtisvm0CB5bVJ3OLz1uyPwl+Q7A2aL9r\n" +
            "i2wo3Q0Qu3tEXIRfTr4rr/6w3JOXV5RjZcb6FsWIy5MeIlRMOwXMVWur6Qh0Ax33\n" +
            "cx0b8H4zXxVrDTl4IO6EqUvKYLCSogEIiQpGQE7tu32V7o4uRyaNWKHMTbBx5KKN\n" +
            "0IawtXIq6JPZsFL3M6aW8GjenWda9Onr4WrNttsC64zZXSlCAE81RHoUWuT6DOzX\n" +
            "I16t4j7ifCeWGOTnTMovYUceebb/yneaNhfa1mrWkLRv/mwcl/HWzu+vtr5FlyMI\n" +
            "fw5N38xxobF1TFbwfc+J2BHnbCJpM9K9PV2hvJ2T7eW+n0MCAwEAAaNCMEAwDwYD\n" +
            "VR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFKCjntQPJMQh\n" +
            "u1YSV8aHbV89dJrQMA0GCSqGSIb3DQEBCwUAA4IBAQAGeK4B/9w9BtbYfmPLvRc9\n" +
            "+ZGXtZ/mAPFeeSorKYbo4ADe0sRnGq0GPzKfnLRzWdCcq/CddL+njofkpjxg838a\n" +
            "8Izu9x3daaM0QS6ik6OXU/E3e+GYiZh5EAMLGn2s02lrJLCcC0C+aX/hNo+Vfrck\n" +
            "CgFPwKi7rCM7TQbHTmacLsWc/oY/JHlAKIqaxk1YwEMsSBCS8onRvMHwiY7modLG\n" +
            "s6d2NGuTcP3EbMYN7zcDiMngnXcyDM6jRrPw1cp+ZShJKUT+bHGAXIgk4aFdCmaK\n" +
            "RmjBS7PWeo5ghYkuveaDj8kvOS60Uysfbqy8i4FRX7TRYKfxj1ZaigM4VUDfVe6V\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDFDCCAfygAwIBAgICEAAwDQYJKoZIhvcNAQELBQAwFDESMBAGA1UEAwwJVGVz\n" +
            "dCBSb290MCAXDTIwMDEwMTAwMDAwMFoYDzIwNTAwMTAxMDAwMDAwWjAcMRowGAYD\n" +
            "VQQDDBFUZXN0IEludGVybWVkaWF0ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC\n" +
            "AQoCggEBAL399W0zTUQlKkCm/wV1V7SvNm6ttCkocOMkttXjEqvXcZK52FoO16WC\n" +
            "Z9nvO3U1+5e0d5gOmhXGkbadsL54Vgjzn0xvSr1GCUFRHDZupUZVUU+bgRTlzps7\n" +
            "yxAnDqQjmkUwepqjAzf/WAx7JEsNQpA/21i2GxY2hOUBQilZWYpwF5Iiut61R/Z8\n" +
            "1jpaqKYe29dznT6IhiK9t5/mfYoFO7MC+Io42/jzzm/HVX+ofCjpidKQ2XkvNCFL\n" +
            "tTLWl2NC1PU+RHx1ZVInkV/jQ8iAAvcorvXV5cR3JHcvPgfM/59VnW5XebH4TQEt\n" +
            "bC7BJb7u3rwAwUOQo8/pLZ9fZSOkc1cCAwEAAaNmMGQwEgYDVR0TAQH/BAgwBgEB\n" +
            "/wIBADAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFHy1hmJ0+rge/29cgsBUS/MO\n" +
            "lTHAMB8GA1UdIwQYMBaAFHtwsdU/hijYp7bHUQDWHoeX1vpdMA0GCSqGSIb3DQEB\n" +
            "CwUAA4IBAQAlirn6rv2YU+kaenS0QE/Mj3bgpv6kpLb1exT1dYVI7amcDkZicewH\n" +
            "M5Bz2iMjMEyhJXJsGPdsMOLEBnCezCLhi8NKVBnn7cecyMEhNJYBqghOaoCn5+Ft\n" +
            "OrUKLt/bZt6ODuRmzsiy6BqA3SY/vgyjEohUz0ot5o6mxAcufEs84mhaTDOqFd7u\n" +
            "GwzNOoNRnK6ium45DooUTmZls6WiQPkIBUQyYFZUvZDjIK6GIt2kfHTfXquuGbt0\n" +
            "vpWiRHHSZ/2Mkt97h/rLvm6BmrYggLID3xGeCImgPC8tiT+iEB03bF1p3BSdjbH3\n" +
            "2gwE8dJ2jkt1F6tY/GXYK3BO+yFAZrUy\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDSjCCAjKgAwIBAgICEAEwDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRVGVz\n" +
            "dCBJbnRlcm1lZGlhdGUwIBcNMjAwMTAxMDAwMDAwWhgPMjA1MDAxMDEwMDAwMDBa\n" +
            "MBwxGjAYBgNVBAMMEWxlYWYuZXhhbXBsZS50ZXN0MIIBIjANBgkqhkiG9w0BAQEF\n" +
            "AAOCAQ8AMIIBCgKCAQEA3lFXqjOPzIoTIGGSqy33+ylSpE7C7Z8sKOAMTAMD+ciS\n" +
            "MNe8Q8AuLjWWovXmCF1+gPt+Gi6LmSAKxVUBMei2Fi684WS3aqoZaq2kMN4WqrYO\n" +
            "UXLpj1xVW+92SUd3owLW9VFEWsj8vFRBb+2BDUzoq8YZSZGFmzoDSN9at/zkKkHJ\n" +
            "hxlih5+mxwnIAzBjalnm/WQA214ZjOm4Xpge1toc7gwpFBuztbAlM74clFoQFikn\n" +
            "ULJJvdOsDfJCiVZdbGciTekaF0AgxgICZXckNd09kw5r6zv/Z98zsTxL3g1rECqh\n" +
            "puvj+KSd2hHabGKkZ1YsC9Lg85N8+Pcrqwkcbhf/awIDAQABo4GTMIGQMAkGA1Ud\n" +
            "EwQCMAAwCwYDVR0PBAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcD\n" +
            "AjAXBgNVHREEEDAOggxleGFtcGxlLnRlc3QwHwYDVR0jBBgwFoAUfLWGYnT6uB7/\n" +
            "b1yCwFRL8w6VMcAwHQYDVR0OBBYEFKf06Cesr/vSaN85/1Q9phVEB663MA0GCSqG\n" +
            "SIb3DQEBCwUAA4IBAQBZ1OEeXxk4lWh1DlfFAfvYh5nsu6Vz6gR5bLMje8vUEDG/\n" +
            "0IfRHkcyYU2l0rUYt1ky3VIkZXPlTiM/pWIEvaoUvRc5VECYqIor+meg35spNsUu\n" +
            "T0L11s/7iGULuxZyPjLfU3OoH94luM/08NN+4jKZM3dU12O40f9qe+oo4QZJpbUS\n" +
            "NxwYkHK+oc9hJxRh84aqGk9/w1Eq1nhEg+sU2Z1P+69PEo5X4fOFSTdQtR7rcZMk\n" +
            "TQ4qgrshNGDlbQqH2U2S7EI/6X5snHa4/QvZilxxtSdyqnA+wKWQs0G1tPXCnoPz\n" +
            "3g8kUhIciaF4CRvoU/YBlYJUaOMuIj8url+irdYS\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDTTCCAjWgAwIBAgICEAIwDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRVGVz\n" +
            "dCBJbnRlcm1lZGlhdGUwIBcNMjAwMTAxMDAwMDAwWhgPMjA1MDAxMDEwMDAwMDBa\n" +
            "MB8xHTAbBgNVBAMMFHJldm9rZWQuZXhhbXBsZS50ZXN0MIIBIjANBgkqhkiG9w0B\n" +
            "AQEFAAOCAQ8AMIIBCgKCAQEA5WhrQn3UAopk7ljUTI2zaa1l7M09JVrId+s2wvpw\n" +
            "4GuHwWZ/stbJWtSxsO4mRht6RGGjlwcDjbaVIgEhGltFmJdwXfx0rg8jwL1B4BZa\n" +
            "3MorDKiCP4fUzX8iw6wW+w657JQCMX6xE23OHTLSFoet8t8bfMcrG/ij+q/Yq8ho\n" +
            "m9EQHvNneGVcaXGPU3Y8W+9i928TH0j40YhUGu5yuD8vJMT6X31fM2XPKAER77Nv\n" +
            "yMo43357ShXQUiyXdxH/tMiGonGQuVA1yL9mt6sEhTHWRsGRX4eiQB6eoxOUpmth\n" +
            "jkG1ipjmZxjJaZtoEMwm6Dji0CFmpiADVLL1l0F6D2+9qQIDAQABo4GTMIGQMAkG\n" +
            "A1UdEwQCMAAwCwYDVR0PBAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEF\n" +
            "BQcDAjAXBgNVHREEEDAOggxleGFtcGxlLnRlc3QwHwYDVR0jBBgwFoAUfLWGYnT6\n" +
            "uB7/b1yCwFRL8w6VMcAwHQYDVR0OBBYEFLTwwmhsYD7qu43z6Trl+Q1afTnfMA0G\n" +
            "CSqGSIb3DQEBCwUAA4IBAQAOXtLq1nU4Z9tuph41lqui9OuMkJhGe5Pgu3yGqsF5\n" +
            "BJxaI++vdHp7frS8T7983g8Qure/U5noTRORiasbNktZGZj8MzddKEQU0a9q9c9I\n" +
            "DVXpjqSL7DNeSoYZi+0bV4eyUlOpH0MFuaTj03+rZOSS6IIRnQ9r9FOb86MMbr3t\n" +
            "xGs5Z2gCE8LQECYCgXMNZW3HoIY8tdkswqdPQaf3XUEGYFlzSV9Y8gKxvQ+vkrQn\n" +
            "hBVwuC7VBGRIMYG/+c2ouHdK2q2nKIzPSYXLRB02Y1PLSnJ6SbeZ6XnRCplxDEMZ\n" +
            "SN2Lr0BgG8NcXOtSZKupPQlWMFdn3cwLpOkjYTCJ7K6X\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDSzCCAjOgAwIBAgICEAMwDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRVGVz\n" +
            "dCBJbnRlcm1lZGlhdGUwHhcNMjAwMTAxMDAwMDAwWhcNMjEwMTAxMDAwMDAwWjAf\n" +
            "MR0wGwYDVQQDDBRleHBpcmVkLmV4YW1wbGUudGVzdDCCASIwDQYJKoZIhvcNAQEB\n" +
            "BQADggEPADCCAQoCggEBAP9Bp5+vPHHUlQEOJw8Zcpo1OZ3YiIC5mJx3HpQXOSbJ\n" +
            "Q/qAU5eRybEvKLdOhWOxe/ClpyWQmP7tSMLFsswG/vh3YyYEy/uGnbQentzkuFY0\n" +
            "Xru0Y3XweWGqG37PpYqW1cYDii+mRQchunvP0sXS6r9jabNDAytwxD0U6s7UhVxv\n" +
            "CvG0dcDMyTpKRW6Sc/hHZPaWswuly5HZRFb6c7jhMUfietcHYztYrrEFZd0dSEG2\n" +
            "D/HFaTGzBzs9M2k5sR9RqhvfFG/d83tA7jBnRgnxSnRxhQ+rx05c68cXZjuDpapJ\n" +
            "0QMMfdVSasZcUHFgm/3BsEcADb2CROJSLXbFIDsaTfsCAwEAAaOBkzCBkDAJBgNV\n" +
            "HRMEAjAAMAsGA1UdDwQEAwIFoDAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUH\n" +
            "AwIwFwYDVR0RBBAwDoIMZXhhbXBsZS50ZXN0MB8GA1UdIwQYMBaAFHy1hmJ0+rge\n" +
            "/29cgsBUS/MOlTHAMB0GA1UdDgQWBBRe2mEHqx4E9b5cBsou5gYajWVvCjANBgkq\n" +
            "hkiG9w0BAQsFAAOCAQEAcliE+vGPyl8pKSHQ1ps8sMLC9LGjopxkZ7z8iXrKe5K9\n" +
            "awAAJtY2n3O1cR35gBi3UQLKIfoapcAf+I0naXBsjXMqVPsd7m6i0+XVjpuVFNKD\n" +
            "ldh6P7Iw8Pxnynfl8QSO/6tigpB1Pm5H/OiFDfVhyKy1TPV3UVGDKDBSaGjeqjkD\n" +
            "PtlkHnjDP+T/Mm3iEMMsFZaMsnd85fnJgxa1WM2raLCwBbcEfGRpMgS6DHyOll5O\n" +
            "fVb0ozKVkYLa3HYdKtv99/bHKyArIpTqYElUfQ6H0JBFthxi5Zpx4WviBA1E4q2F\n" +
            "Nl3ieU038vPzmlc0zhf0F1epRg6CCNAkUlGV8zrjQA==\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDTDCCAjSgAwIBAgICEAQwDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRVGVz\n" +
            "dCBJbnRlcm1lZGlhdGUwIBcNNDAwMTAxMDAwMDAwWhgPMjA1MDAxMDEwMDAwMDBa\n" +
            "MB4xHDAaBgNVBAMME2Z1dHVyZS5leGFtcGxlLnRlc3QwggEiMA0GCSqGSIb3DQEB\n" +
            "AQUAA4IBDwAwggEKAoIBAQDLpGb6e1JeDpY+KNnLwJTXLGmtntKKchuVb3zGPouK\n" +
            "fWMOL+8TaUDUTRmEzfDCa9h6ufvWzrMIkgbOYlOMSC8xOghX8Aw+XW/f+UO6IbZ5\n" +
            "LqsZOyRBHwY6d82sLFInms19Lk9+Y3rEBJF1+/P/tLBToibt/CPowQrF8g2OkxAb\n" +
            "2Cd+5aSofxEiagdLLuhCc/Xloqa09ZKN5O+ouFU7VgyUx6wMjsEvjv31WWSVaVXk\n" +
            "sK23qeFYTWtCcLxwYg9SCGhW98wkE0XarHSifMqg0H85h83pUG5fx68HMWFVYIC/\n" +
            "x2RDahBf7kvAE8CyOKWs8Vvpar7tOQNCzdh1sBXcJaFfAgMBAAGjgZMwgZAwCQYD\n" +
            "VR0TBAIwADALBgNVHQ8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUF\n" +
            "BwMCMBcGA1UdEQQQMA6CDGV4YW1wbGUudGVzdDAfBgNVHSMEGDAWgBR8tYZidPq4\n" +
            "Hv9vXILAVEvzDpUxwDAdBgNVHQ4EFgQUDKowyN4oC9oLHSatSprjHTBevxowDQYJ\n" +
            "KoZIhvcNAQELBQADggEBAF5YD4wWaig0Ga7e16DE4/HlO/UH4k5YyNYRS/4Zkpru\n" +
            "HaHX6hAdKKm3kvUxSWX2p/YfBGBRZWGf4IgXc+7ztJSeVO+Tker/2iN/8SIvY3Ar\n" +
            "+QUMp5TcLuQcb0GGZ5Ylc2thNL4dwGsFMrh7OLb1dr9imS88TNYKtsOmCwvc4DtM\n" +
            "pl5pWElBSBtFYRu1jE3B/K5fkh+IWiudIazfmkJYDJGRVLziQCgcQBc3ETNH+1Ty\n" +
            "cffFIoGKc1EGz48in9oyjDqufIzyGvUVHsIQ11lXVI81EZUIfn6T5DzSEIZVg+at\n" +
            "2CosjlzTKalE0XeJ+fzkTH7/wR+Pud4t6qmSLgjSiPo=\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDRDCCAiygAwIBAgICEAUwDQYJKoZIhvcNAQELBQAwFTETMBEGA1UEAwwKT3Ro\n" +
            "ZXIgUm9vdDAgFw0yMDAxMDEwMDAwMDBaGA8yMDUwMDEwMTAwMDAwMFowHTEbMBkG\n" +
            "A1UEAwwSb3RoZXIuZXhhbXBsZS50ZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A\n" +
            "MIIBCgKCAQEAsDBcnR//OWArDu7CLBpQx6Q+EKB6HD8I3owFgPqHESkSPdAzHzJa\n" +
            "JKISF4FRLb33fKXsTFSBAW5DeIfaQhu9hR2q2hANpVnTN3MMBKiKUBDyYPndiHZk\n" +
            "xcsILJK5kNRMpnykU9NL0WgPLRCyMDroYClnNkh7l1veNPujDzjj1oPjpnTLzvAZ\n" +
            "GwIdUvBnxZ4rDtHEuAHVgikl20ftispejTSHtf66lToXhNzWPcG1z/9+WXDexZzO\n" +
            "xEtFqwPml2Qn84zpEyrW26LZQfuHimrw4Y5OUQ/2sA7tBntHokV0HlyPa9F46p7P\n" +
            "iDiJUFH5QGFcJYZM/jrAjR51560/jzygowIDAQABo4GTMIGQMAkGA1UdEwQCMAAw\n" +
            "CwYDVR0PBAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAXBgNV\n" +
            "HREEEDAOggxleGFtcGxlLnRlc3QwHwYDVR0jBBgwFoAUoKOe1A8kxCG7VhJXxodt\n" +
            "Xz10mtAwHQYDVR0OBBYEFMHPTzuSonuPcAZAQ299IMNWL0lXMA0GCSqGSIb3DQEB\n" +
            "CwUAA4IBAQC+mSJGw1sDydBBSI12TkrXvfXWAFY1OtAj1nT6wzwuVJew/bmy5acX\n" +
            "wrOJC9zJfQxbrmXzMjDG12DCmFt1ylHsHC4cv52KatbFkI7fZ1/UELE3rYgZTXTv\n" +
            "usI533Bp93nqxVaDTgClih7I2a9Efko+OTAakYfsDAH9veikJcg6vhLoFgx7+dE8\n" +
            "VoD1JQsYQwsbBWPqQJFrI9GJb7KtwcfVz8ZWgvPI9kUkJ6T23AIo4QyExMCPQeBe\n" +
            "qex9wx1DfF5XzF6kMI1XPfqwrO8jFlg1kdE5wMSpwwvnp1S537dsoXIPf4DQcvz9\n" +
            "pWBzC3YXYW52wZ7GwR2SWQWExZcUul3I\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDAjCCAeqgAwIBAgICEAYwDQYJKoZIhvcNAQELBQAwFDESMBAGA1UEAwwJVGVz\n" +
            "dCBSb290MCAXDTIwMDEwMTAwMDAwMFoYDzIwNTAwMTAxMDAwMDAwWjATMREwDwYD\n" +
            "VQQDDAhOb3QgQSBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMEZ\n" +
            "6+JeFI598LrGIpARoNHWBypPjI6dBr59s1UM5lQx8ZLQyCwok62cQLDnjUioWvXK\n" +
            "39es7w4Ni9cngCsEV9Ib1pnupVI1dhBF+cv24MMmTnScIvYfCZktUS08BkD/vu5L\n" +
            "997aLogJkS0QCf0B33C5LwEvjc8WcvUzai20vGdze0hX39oQxFsYlN8/kTTEbCne\n" +
            "kHp6lb7ccj0k3Dx/6xpO259O0pa2sveT9lP/5BjUvwcA+LKJ4Jd26/aIu+4g7XEr\n" +
            "+Dl9cSG3SCF7VT/Floa6OsNDDRFb+NyyCzb1W4tk1zUBKATDfm2Go4n8LazWb/9v\n" +
            "TEHepV/qUDEI+n0FIoUCAwEAAaNdMFswDAYDVR0TAQH/BAIwADALBgNVHQ8EBAMC\n" +
            "B4AwHQYDVR0OBBYEFF28Iju5dlKSY4LWRPyyyBFD7wBDMB8GA1UdIwQYMBaAFHtw\n" +
            "sdU/hijYp7bHUQDWHoeX1vpdMA0GCSqGSIb3DQEBCwUAA4IBAQAX5Du83r1POabQ\n" +
            "Z97ePImzCE689FwEtBuTlRP/SAcsERG9OIgch6EoyCmqFFr/mw9snU4kC3Acu4tS\n" +
            "BRDAWiFXDIrQZHe6m4RAPnxijXhA6ff31oijxF8PfdTO2jQ2zy/CflXk4Lr/URNH\n" +
            "NbPh/CHo+dktdM6K07nihP6i4ss97rkYXNHB7dNZIGo+GpC7qew2an74qn2LwFFd\n" +
            "5m2dwNiO9rc8r/rjh0n8tKZdZR+GuC2e9JmIyAHkUViVpk32ZAJ93QYqYHRgXOw7\n" +
            "9QAJo1e3KNN2rjQS3YeBLipg3wen083sOvBOK5zIbI/j5EXfDccADm0fXt6Jy6DI\n" +
            "tDCL/AE3\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDPzCCAiegAwIBAgICEAcwDQYJKoZIhvcNAQELBQAwEzERMA8GA1UEAwwITm90\n" +
            "IEEgQ0EwIBcNMjAwMTAxMDAwMDAwWhgPMjA1MDAxMDEwMDAwMDBaMBoxGDAWBgNV\n" +
            "BAMMD3VuZGVyLm5vY2EudGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC\n" +
            "ggEBAJnwEKsh9jFOgK4eiGgnzk3BS6usSPg7vQFvfTfflSsh2MK3gGFbaU7xMxOz\n" +
            "yV9aJKZ4qU7T2ZHg39ZlOm6AFr5mR1u+Ke+iOhOYtXTJDCAy12FTw2tM4C7lF8os\n" +
            "tJI+u4tGQ8SUHaEgwlpV/GF5VmcCHid4xgocr54g6B+iOD+6OAAQCLjI/VcBk9zn\n" +
            "I9SdEng8ibf1jtnRY9GJUu8e2yK1SL2YoD2En87SfW4qBZphV1nd9lbTOJ4BNETG\n" +
            "AOKI6tT+X1Kj3CHDn+p7a4zHa03GAsCAin81m1V4/yBZ425ZlgcjieaIQo9dwcbT\n" +
            "brywu4oNljlXjaSShUfIxqg1gKUCAwEAAaOBkzCBkDAJBgNVHRMEAjAAMAsGA1Ud\n" +
            "DwQEAwIFoDAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwFwYDVR0RBBAw\n" +
            "DoIMZXhhbXBsZS50ZXN0MB8GA1UdIwQYMBaAFF28Iju5dlKSY4LWRPyyyBFD7wBD\n" +
            "MB0GA1UdDgQWBBQtjPvAORHe8AS2gdZPw4XQOqD0IzANBgkqhkiG9w0BAQsFAAOC\n" +
            "AQEAk9OST5XbS2iN2TmmAtC52/xbBgQ3UYXmF9ap5de+7tetTDIo0H7W+Io/qDjv\n" +
            "GKQYahZzqwZcdkH17l13Mm/RbTQXd3pgGGtRl1pGvhSOr5Gp0+5skKo2QtMu3zYp\n" +
            "R9ZnkRSS5DwmXdg/E+RUEuLnF6vXEgBxNRMo1UNT4XQnktOb18zYqaIQ+HEa8dJO\n" +
            "Ql2YM5yQyCneFy99AycnrymoGupNV74oEPT5/KuJvrbtN4gV2gbnqV3gOSOASOc6\n" +
            "NGSUIzCaAHgA64ISCVhkLcFjVhm4OfYBXF9hZ8n1baVgz5Ixex8txsLQ/rRovdn5\n" +
            "iv2sU9EJx96XHi4uJdEkUTVmvA==\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDGTCCAgGgAwIBAgICEAgwDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRVGVz\n" +
            "dCBJbnRlcm1lZGlhdGUwIBcNMjAwMTAxMDAwMDAwWhgPMjA1MDAxMDEwMDAwMDBa\n" +
            "MBwxGjAYBgNVBAMMEURlZXAgSW50ZXJtZWRpYXRlMIIBIjANBgkqhkiG9w0BAQEF\n" +
            "AAOCAQ8AMIIBCgKCAQEAxjoR0/WTng4t5D/2NhVGk6/T8Qyu1KCXOUDSycqWRRYz\n" +
            "ihfmXtdzMjNoUuKprdaa/mKum5Erm/+HJ96NNQ7sqXtXJhchaDA99QatkcIEPg9y\n" +
            "JNlR1xbuK55Qw9tOA6oNtOezbmn16+tCbDXM/xxtLwbGd2L7Ls8nLcfNQHCMOU2m\n" +
            "ThO376e2GkhvGL4BZ2VNANKCtz6weDVlwli/jyqOuEKQRgxmhHog+EH5KW/uxjvn\n" +
            "YmDYL0TaOen7WEg/slE1GzePJOp05ODzADfTDU8WlspfCYPzQcC8dEHn0tZjMZR1\n" +
            "Qqbysox5p2npVAbby7FaJVjjIw6ElfkWBZwm0ID1wwIDAQABo2MwYTAPBgNVHRMB\n" +
            "Af8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUQT70oOO0SrkNGA80\n" +
            "MRXXlqocYsUwHwYDVR0jBBgwFoAUfLWGYnT6uB7/b1yCwFRL8w6VMcAwDQYJKoZI\n" +
            "hvcNAQELBQADggEBAIufjCjOMx9V3j1LdAPagxZ6jSkT5jRw9W9QCw7+yqG+c265\n" +
            "sDLGVZT5HqGuVeIPODYcf7LqGwtgGHWHSS05i5Sb96UrK7AxWr+IBh3PAV4QnYmz\n" +
            "5dUouDmq9vuoRrkLzMQlTzdyuHx4iT1VOCTtprQDQUZOqXYAe7/Mllacw+0vvblD\n" +
            "cEcdeVGE5KUZS4UAMsjzUet9Xha59hnU/hhkrImAGuwzmY7Erme6kEVpKK4ZHHWQ\n" +
            "1pkEVGkNp5aUeUsZS1GnEHe4WDIF7043o0JXU6pt57ZTml0pi5IwSJdiQeEaTjiT\n" +
            "JW7bcpqKbM3r7RxSjtcWy70xRZLrC/+yzPhWUkI=\n" +
            "-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n" +
            "MIIDSDCCAjCgAwIBAgICEAkwDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRRGVl\n" +
            "cCBJbnRlcm1lZGlhdGUwIBcNMjAwMTAxMDAwMDAwWhgPMjA1MDAxMDEwMDAwMDBa\n" +
            "MBoxGDAWBgNVBAMMD3VuZGVyLmRlZXAudGVzdDCCASIwDQYJKoZIhvcNAQEBBQAD\n" +
            "ggEPADCCAQoCggEBAI40hXkrJbBiZDv9d9QlzW46pV4LtgSkNNP/pq+sOcoluDyu\n" +
            "hR5/BHx1GhLG18T4vaFnEmGGGeq6fuSJo5gdhIi4UIy605hb9EcV+XWoC6xtemH/\n" +
            "kf6A+y+mrmyigzKJq/WXaFDjjVhRTOz1Ak+5MJK7dzXiJbmZ7THrEUwTVvRIWBVT\n" +
            "xt1PC+y4ktAWjbYShNPvwWLQ2JO0XRj3vkED8urmpiEOQObkpbkfWB85LrvWtw5N\n" +
            "o5oEaXkMuQcKuiiiIev4mdE+rEtoM74nu+VFioyHfiiVvDO0V2HNbTGj4Y9P7hwf\n" +
            "6mzju6YIlWC7xjtUJkRUnjmRc6GACepd2uvn7o0CAwEAAaOBkzCBkDAJBgNVHRME\n" +
            "AjAAMAsGA1UdDwQEAwIFoDAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIw\n" +
            "FwYDVR0RBBAwDoIMZXhhbXBsZS50ZXN0MB8GA1UdIwQYMBaAFEE+9KDjtEq5DRgP\n" +
            "NDEV15aqHGLFMB0GA1UdDgQWBBSJEPIZw1WcP73LdTdq2UXurLD5uTANBgkqhkiG\n" +
            "9w0BAQsFAAOCAQEAH6sckuqHpjF1HVVR0isRf+Th+n3SXSWWbmMHcWhXDotDHWTg\n" +
            "RdZN04xVqs1KLV3U8SL9VbJIIWaeJUNSa02L//oshId3e9GrJiuIhGjNsC2FsHEj\n" +
            "eLRmHVoZjykgLGHqb3YJIFDSlLbOrxogtsODA/mkc1yus2PKF59xG/fVar4gK202\n" +
            "fqEezhAXKH261dGwbNoH7Oc4dh17CMijDm215MveqhhSaxUOvRN/crkHn9YsIkL/\n" +
            "4MwpoNoYKnA/KSdABSZ74l/8r2Fm49FY0J4PeUHMG5bLSLdlnyQ/wGtvHYIvw7cp\n" +
            "H4X1V5hlWxerc8whI+C5a856PjrxtgZUDMJ8Xg==\n" +
            "-----END CERTIFICATE-----\n"
    };
    static final String[] CRLS = {
        "-----BEGIN X509 CRL-----\n" +
            "MIIBizB1AgEBMA0GCSqGSIb3DQEBCwUAMBwxGjAYBgNVBAMMEVRlc3QgSW50ZXJt\n" +
            "ZWRpYXRlFw0yNjExMTExMTA2MTdaGA8yMTI1MDYwNTExMDYxN1owIzAhAgIQAhcN\n" +
            "MjQwMTAxMDAwMDAwWjAMMAoGA1UdFQQDCgEBMA0GCSqGSIb3DQEBCwUAA4IBAQBa\n" +
            "srv8LI8M6hqYTm67ogUK2C4Z7gNq3zXhN7f60orR9pFe0QRv7bODcLoeprrNyNue\n" +
            "PmKcd++tm9QUBYfFZ0SAEkFub2EwoF77z8XQKMBPvaRPbfgzlaYXuUMggQa4nYRL\n" +
            "FaQHjW8Pwx8cCn4WGfquNF87DRBrI/r4OsAnFmbjjvGemASKyi9ea2HPYYzf/gbB\n" +
            "qu1HpkTMnhMh8r8OIq1kX3/tTuiqcDoXIdHyueTQiCZs8nxMQXiYlUcedVaYBIKx\n" +
            "mmASayizlgkuSSsz0/TQSZLVeDgJY6DjzLTn+eta60yDBZM2U3EOYqknOvZraueo\n" +
            "px//tNWHa/WG70geBPnP\n" +
            "-----END X509 CRL-----\n",
        "-----BEGIN X509 CRL-----\n" +
            "MIIBWzBFMA0GCSqGSIb3DQEBCwUAMBQxEjAQBgNVBAMMCVRlc3QgUm9vdBcNMjYx\n" +
            "MTExMTEwNjE3WhgPMjEyNTA2MDUxMTA2MTdaMA0GCSqGSIb3DQEBCwUAA4IBAQAW\n" +
            "Ni3jd5bCCOstXFFR+Lvum+tg55in+97y9r92/yV0jgUDUe3SBCpl1GEkeMghBYq/\n" +
            "NqeJywXsOhG3SosZ3p26iwAr4iUT8Xk49zxNVfiPl9nUDlwCU1LAXpXm+0pwXNts\n" +
            "2JmtiJnNhhJXv55FUgHygrfA/cDzm7NJrWTST34LsjpL51isosWSqO7SrROyTIQP\n" +
            "V+RTu4rG1slgJOIiRs2CYgQtAs7W7iJDT+iGw6v+g1VhZIIzrqQNPNHvQWi+Claw\n" +
            "+DZhyceBV+l7P03JbXXVwJRqdDyOd1wTFTqGBMad9xV4p2J1gP4HT563XkguFRGS\n" +
            "Ve/e15IcgYHVeFI1Yb7P\n" +
            "-----END X509 CRL-----\n"
    };
    static X509Certificate cert(String name) throws Exception {
        for (int i = 0; i < NAMES.length; i++) if (NAMES[i].equals(name)) {
            return (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(PEMS[i].getBytes(StandardCharsets.US_ASCII)));
        }
        throw new IllegalArgumentException(name);
    }
    static X509CRL crl(int i) throws Exception {
        return (X509CRL) CertificateFactory.getInstance("X.509").generateCRL(new ByteArrayInputStream(CRLS[i].getBytes(StandardCharsets.US_ASCII)));
    }
    static CertPath path(String... names) throws Exception {
        List<Certificate> l = new ArrayList<>();
        for (String n : names) l.add(cert(n));
        return CertificateFactory.getInstance("X.509").generateCertPath(l);
    }
    static final Date WHEN = new Date(1798761600000L); // 2027-01-01

    static PKIXParameters params(String anchor, boolean revocation, X509CRL... crls) throws Exception {
        PKIXParameters pp = new PKIXParameters(Collections.singleton(new TrustAnchor(cert(anchor), null)));
        pp.setRevocationEnabled(revocation);
        pp.setDate(WHEN);
        if (crls.length > 0) pp.addCertStore(CertStore.getInstance("Collection", new CollectionCertStoreParameters(Arrays.asList(crls))));
        return pp;
    }
    static String validate(CertPath cp, PKIXParameters pp) throws Exception {
        PKIXCertPathValidatorResult r = (PKIXCertPathValidatorResult) CertPathValidator.getInstance("PKIX").validate(cp, pp);
        return r.getTrustAnchor().getTrustedCert().getSubjectX500Principal() + " key=" + r.getPublicKey().getAlgorithm() + " policy=" + r.getPolicyTree();
    }

    public static String run() throws Exception {
        out = new StringBuilder();
        // cert paths
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        CertPath cp = path("leaf", "inter");
        p("cp type", cp.getType() + " " + cp.getCertificates().size());
        p("cp encodings", iter(cp.getEncodings()));
        p("cp factory encodings", iter(cf.getCertPathEncodings()));
        p("cp encoded", cp.getEncoded().length > 100);
        p("cp pkipath", Arrays.equals(cp.getEncoded(), cp.getEncoded("PkiPath")));
        p("cp pkcs7", cp.getEncoded("PKCS7").length > cp.getEncoded("PkiPath").length / 2);
        t("cp bad enc", () -> cp.getEncoded("nope").length);
        p("cp order", ((X509Certificate) cp.getCertificates().get(0)).getSubjectX500Principal() + " | " + ((X509Certificate) cp.getCertificates().get(1)).getSubjectX500Principal());
        CertPath back = cf.generateCertPath(new ByteArrayInputStream(cp.getEncoded()));
        p("cp roundtrip", back.equals(cp) + " " + (back.hashCode() == cp.hashCode()) + " " + back.getCertificates().size());
        CertPath back7 = cf.generateCertPath(new ByteArrayInputStream(cp.getEncoded("PKCS7")), "PKCS7");
        p("cp roundtrip7", back7.equals(cp) + " " + back7.getCertificates().size());
        CertPath backP = cf.generateCertPath(new ByteArrayInputStream(cp.getEncoded("PkiPath")), "PkiPath");
        p("cp roundtripP", backP.equals(cp));
        p("cp equals other", cp.equals(path("leaf")) + " " + cp.equals((Object) "x") + " " + path().equals(path()));
        p("cp empty", path().getCertificates().size() + " " + path().getEncoded().length);
        t("cp list immutable", () -> { cp.getCertificates().add(null); return "no"; });
        t("cp bad element", () -> cf.generateCertPath((List) Arrays.asList("x")));
        t("cp bad stream", () -> cf.generateCertPath(new ByteArrayInputStream(new byte[]{1, 2, 3})));
        t("cp bad encoding", () -> cf.generateCertPath(new ByteArrayInputStream(cp.getEncoded()), "nope"));
        // crl
        X509CRL ic = crl(0);
        X509CRL rc = crl(1);
        p("crl type", ic.getType() + " " + ic.getVersion() + " " + ic.getSigAlgName() + " " + ic.getSigAlgOID());
        p("crl issuer", ic.getIssuerX500Principal() + " | " + ic.getIssuerDN());
        p("crl dates", (ic.getNextUpdate().getTime() > ic.getThisUpdate().getTime()) + " " + (ic.getThisUpdate().getTime() < WHEN.getTime()));
        p("crl revoked count", ic.getRevokedCertificates().size() + " " + rc.getRevokedCertificates());
        p("crl isRevoked", ic.isRevoked(cert("leafrev")) + " " + ic.isRevoked(cert("leaf")) + " " + rc.isRevoked(cert("leafrev")));
        X509CRLEntry e = ic.getRevokedCertificate(cert("leafrev"));
        p("crl entry", e.getSerialNumber() + " " + e.getRevocationDate().getTime() + " " + e.getRevocationReason() + " " + e.hasExtensions() + " " + e.getCertificateIssuer());
        p("crl entry by serial", ic.getRevokedCertificate(cert("leafrev").getSerialNumber()).getRevocationReason() + " " + ic.getRevokedCertificate(BigInteger.valueOf(5)));
        t("crl verify ok", () -> { ic.verify(cert("inter").getPublicKey()); return "ok"; });
        t("crl verify bad", () -> { ic.verify(cert("root").getPublicKey()); return "ok"; });
        t("crl verify bad2", () -> { rc.verify(cert("inter").getPublicKey()); return "ok"; });
        p("crl ext", ic.hasUnsupportedCriticalExtension() + " " + ic.getCriticalExtensionOIDs() + " " + ic.getNonCriticalExtensionOIDs());
        p("crl equals", ic.equals(crl(0)) + " " + ic.equals(rc) + " " + (ic.hashCode() == crl(0).hashCode()));
        p("crl encoded", Arrays.equals(ic.getEncoded(), crl(0).getEncoded()) + " " + (ic.getTBSCertList().length > 10) + " " + (ic.getSignature().length > 100));
        p("crl str", ic.toString().startsWith("X.509 CRL v2"));
        p("crl entry str", e.toString().contains("Serial Number") || e.toString().length() > 0);
        List<CRL> parsed = new ArrayList<>(cf.generateCRLs(new ByteArrayInputStream((CRLS[0] + CRLS[1]).getBytes(StandardCharsets.US_ASCII))));
        p("crls", parsed.size());
        t("crl bad", () -> cf.generateCRL(new ByteArrayInputStream("junk".getBytes())));
        p("reason enum", Arrays.toString(CRLReason.values()));
        // selectors
        X509CertSelector sel = new X509CertSelector();
        sel.setSubject(new X500Principal("CN=leaf.example.test"));
        p("sel subject", sel.match(cert("leaf")) + " " + sel.match(cert("inter")));
        sel = new X509CertSelector();
        sel.setIssuer(new X500Principal("CN=Test Intermediate"));
        p("sel issuer", sel.match(cert("leaf")) + " " + sel.match(cert("leaf2")) + " " + sel.match(cert("inter")));
        sel = new X509CertSelector();
        sel.setCertificate(cert("leaf"));
        p("sel cert", sel.match(cert("leaf")) + " " + sel.match(cert("leafrev")));
        sel = new X509CertSelector();
        sel.setSerialNumber(cert("leafrev").getSerialNumber());
        p("sel serial", sel.match(cert("leafrev")) + " " + sel.match(cert("leaf")));
        sel = new X509CertSelector();
        sel.setCertificateValid(WHEN);
        p("sel valid", sel.match(cert("leaf")) + " " + sel.match(cert("leafexp")) + " " + sel.match(cert("leaffut")));
        sel = new X509CertSelector();
        sel.setBasicConstraints(0);
        p("sel bc", sel.match(cert("inter")) + " " + sel.match(cert("root")) + " " + sel.match(cert("leaf")));
        sel = new X509CertSelector();
        sel.setBasicConstraints(-2);
        p("sel bc -2", sel.match(cert("leaf")) + " " + sel.match(cert("inter")));
        sel = new X509CertSelector();
        sel.setBasicConstraints(-1);
        p("sel bc -1", sel.match(cert("leaf")) + " " + sel.match(cert("inter")));
        sel = new X509CertSelector();
        sel.setKeyUsage(new boolean[]{true, false, false, false, false, false, false, false, false});
        p("sel ku", sel.match(cert("leaf")) + " " + sel.match(cert("inter")));
        sel = new X509CertSelector();
        sel.setSubject("CN=Test Root");
        p("sel subject str", sel.match(cert("root")) + " " + sel.match(cert("inter")) + " " + sel.getSubjectAsString());
        X509CertSelector clone = (X509CertSelector) sel.clone();
        p("sel clone", clone.match(cert("root")) + " " + (clone != sel));
        p("sel default", new X509CertSelector().match(cert("leaf")));
        t("sel bad", () -> { new X509CertSelector().setBasicConstraints(-3); return "no"; });
        t("sel subject bad", () -> { new X509CertSelector().setSubject("not a dn"); return "no"; });
        X509CRLSelector cs = new X509CRLSelector();
        cs.addIssuer(new X500Principal("CN=Test Intermediate"));
        p("crlsel", cs.match(ic) + " " + cs.match(rc) + " " + cs.getIssuers().size());
        cs = new X509CRLSelector();
        cs.setCertificateChecking(cert("leafrev"));
        p("crlsel cert", cs.match(ic) + " " + cs.match(rc));
        cs = new X509CRLSelector();
        cs.setDateAndTime(WHEN);
        p("crlsel date", cs.match(ic) + " " + cs.match(rc));
        p("crlsel default", new X509CRLSelector().match(ic));
        // stores
        List<Object> all = new ArrayList<>(Arrays.asList(cert("leaf"), cert("inter"), cert("root"), cert("leaf2"), ic, rc));
        CertStore store = CertStore.getInstance("Collection", new CollectionCertStoreParameters(all));
        p("store type", store.getType() + " " + store.getCertStoreParameters().getClass().getSimpleName());
        p("store certs", store.getCertificates(null).size() + " " + store.getCertificates(new X509CertSelector()).size());
        X509CertSelector s2 = new X509CertSelector();
        s2.setIssuer(new X500Principal("CN=Test Intermediate"));
        p("store select", store.getCertificates(s2).size());
        p("store crls", store.getCRLs(null).size() + " " + store.getCRLs(new X509CRLSelector()).size());
        X509CRLSelector s3 = new X509CRLSelector();
        s3.addIssuer(new X500Principal("CN=Test Root"));
        p("store crl select", store.getCRLs(s3).size());
        t("store bad type", () -> CertStore.getInstance("LDAP", new CollectionCertStoreParameters()));
        p("store default", CertStore.getDefaultType());
        t("store bad params", () -> CertStore.getInstance("Collection", null));
        p("store empty", CertStore.getInstance("Collection", new CollectionCertStoreParameters()).getCertificates(null).size());
        // trust anchors and parameters
        TrustAnchor ta = new TrustAnchor(cert("root"), null);
        p("anchor", ta.getTrustedCert().getSubjectX500Principal() + " " + ta.getCA() + " " + ta.getCAName() + " " + ta.getCAPublicKey() + " " + ta.getNameConstraints());
        TrustAnchor ta2 = new TrustAnchor(new X500Principal("CN=Test Root"), cert("root").getPublicKey(), null);
        p("anchor2", ta2.getTrustedCert() + " " + ta2.getCA() + " " + ta2.getCAName() + " " + ta2.getCAPublicKey().getAlgorithm());
        TrustAnchor ta3 = new TrustAnchor("CN=Test Root", cert("root").getPublicKey(), null);
        p("anchor3", ta3.getCAName() + " " + ta3.getCA());
        t("anchor null", () -> new TrustAnchor((X509Certificate) null, null));
        t("anchors empty", () -> new PKIXParameters(new HashSet<TrustAnchor>()));
        t("anchors null", () -> new PKIXParameters((Set<TrustAnchor>) null));
        PKIXParameters pp = new PKIXParameters(Collections.singleton(ta));
        p("params default", pp.isRevocationEnabled() + " " + pp.getDate() + " " + pp.getCertStores().size() + " " + pp.getTrustAnchors().size() + " " + pp.getInitialPolicies() + " " + pp.isAnyPolicyInhibited() + " " + pp.isExplicitPolicyRequired() + " " + pp.isPolicyMappingInhibited() + " " + pp.getPolicyQualifiersRejected() + " " + pp.getTargetCertConstraints() + " " + pp.getCertPathCheckers() + " " + pp.getSigProvider());
        pp.setDate(WHEN);
        pp.setRevocationEnabled(false);
        pp.setExplicitPolicyRequired(true);
        p("params set", pp.getDate().getTime() + " " + pp.isRevocationEnabled() + " " + pp.isExplicitPolicyRequired());
        PKIXBuilderParameters bp = new PKIXBuilderParameters(Collections.singleton(ta), null);
        p("builder default", bp.getMaxPathLength());
        bp.setMaxPathLength(3);
        p("builder max", bp.getMaxPathLength());
        t("builder bad max", () -> { bp.setMaxPathLength(-2); return "no"; });
        // validation
        t("v ok", () -> validate(path("leaf", "inter"), params("root", false)));
        t("v ok no root in path", () -> validate(path("inter"), params("root", false)));
        t("v ok root in path", () -> validate(path("leaf", "inter", "root"), params("root", false)));
        t("v single", () -> validate(path("root"), params("root", false)));
        t("v empty", () -> validate(path(), params("root", false)));
        t("v missing intermediate", () -> validate(path("leaf"), params("root", false)));
        t("v wrong anchor", () -> validate(path("leaf", "inter"), params("root2", false)));
        t("v other leaf", () -> validate(path("leaf2"), params("root", false)));
        t("v other chain", () -> validate(path("leaf2"), params("root2", false)));
        t("v wrong order", () -> validate(path("inter", "leaf"), params("root", false)));
        t("v expired", () -> validate(path("leafexp", "inter"), params("root", false)));
        t("v future", () -> validate(path("leaffut", "inter"), params("root", false)));
        PKIXParameters early = params("root", false);
        early.setDate(new Date(1262304000000L));
        t("v date early", () -> validate(path("leaf", "inter"), early));
        PKIXParameters late = params("root", false);
        late.setDate(new Date(2840140800000L));
        t("v date late", () -> validate(path("leaf", "inter"), late));
        t("v not ca", () -> validate(path("underno", "noca"), params("root", false)));
        t("v pathlen", () -> validate(path("underdeep", "deep", "inter"), params("root", false)));
        t("v deep ok", () -> validate(path("underdeep", "deep"), params("inter", false)));
        t("v anchor intermediate", () -> validate(path("leaf"), params("inter", false)));
        t("v anchor leaf", () -> validate(path("leaf"), params("leaf", false)));
        t("v rev no crl", () -> validate(path("leaf", "inter"), params("root", true)));
        t("v rev crl ok", () -> validate(path("leaf", "inter"), params("root", true, ic, rc)));
        t("v rev crl revoked", () -> validate(path("leafrev", "inter"), params("root", true, ic, rc)));
        t("v rev only inter crl", () -> validate(path("leaf", "inter"), params("root", true, ic)));
        t("v rev only root crl", () -> validate(path("leaf", "inter"), params("root", true, rc)));
        t("v key anchor", () -> {
            PKIXParameters kp = new PKIXParameters(Collections.singleton(new TrustAnchor(new X500Principal("CN=Test Root"), cert("root").getPublicKey(), null)));
            kp.setRevocationEnabled(false);
            kp.setDate(WHEN);
            PKIXCertPathValidatorResult r = (PKIXCertPathValidatorResult) CertPathValidator.getInstance("PKIX").validate(path("leaf", "inter"), kp);
            return r.getTrustAnchor().getCAName() + " " + r.getTrustAnchor().getTrustedCert();
        });
        t("v key anchor wrong name", () -> {
            PKIXParameters kp = new PKIXParameters(Collections.singleton(new TrustAnchor(new X500Principal("CN=Wrong"), cert("root").getPublicKey(), null)));
            kp.setRevocationEnabled(false);
            kp.setDate(WHEN);
            return CertPathValidator.getInstance("PKIX").validate(path("leaf", "inter"), kp).getClass().getName();
        });
        t("v bad params", () -> CertPathValidator.getInstance("PKIX").validate(path("leaf"), new CertPathParameters() { public Object clone() { return this; } }));
        t("v alg", () -> CertPathValidator.getInstance("nope").getAlgorithm());
        p("v default alg", CertPathValidator.getDefaultType() + " " + CertPathValidator.getInstance("PKIX").getAlgorithm());
        // builder
        CertStore inters = CertStore.getInstance("Collection", new CollectionCertStoreParameters(Arrays.asList(cert("inter"), cert("leaf2"), cert("deep"))));
        t("b ok", () -> {
            X509CertSelector target = new X509CertSelector();
            target.setCertificate(cert("leaf"));
            PKIXBuilderParameters b = new PKIXBuilderParameters(Collections.singleton(new TrustAnchor(cert("root"), null)), target);
            b.setRevocationEnabled(false);
            b.setDate(WHEN);
            b.addCertStore(inters);
            PKIXCertPathBuilderResult r = (PKIXCertPathBuilderResult) CertPathBuilder.getInstance("PKIX").build(b);
            StringBuilder sb = new StringBuilder();
            for (Certificate c : r.getCertPath().getCertificates()) sb.append(((X509Certificate) c).getSubjectX500Principal()).append(" / ");
            return sb + r.getTrustAnchor().getTrustedCert().getSubjectX500Principal().toString() + " " + r.getPublicKey().getAlgorithm();
        });
        t("b deep", () -> {
            X509CertSelector target = new X509CertSelector();
            target.setCertificate(cert("underdeep"));
            PKIXBuilderParameters b = new PKIXBuilderParameters(Collections.singleton(new TrustAnchor(cert("root"), null)), target);
            b.setRevocationEnabled(false);
            b.setDate(WHEN);
            b.addCertStore(inters);
            CertPathBuilderResult r = CertPathBuilder.getInstance("PKIX").build(b);
            return r.getCertPath().getCertificates().size();
        });
        t("b missing", () -> {
            X509CertSelector target = new X509CertSelector();
            target.setCertificate(cert("leaf"));
            PKIXBuilderParameters b = new PKIXBuilderParameters(Collections.singleton(new TrustAnchor(cert("root"), null)), target);
            b.setRevocationEnabled(false);
            b.setDate(WHEN);
            return CertPathBuilder.getInstance("PKIX").build(b).getCertPath().getCertificates().size();
        });
        t("b wrong anchor", () -> {
            X509CertSelector target = new X509CertSelector();
            target.setCertificate(cert("leaf"));
            PKIXBuilderParameters b = new PKIXBuilderParameters(Collections.singleton(new TrustAnchor(cert("root2"), null)), target);
            b.setRevocationEnabled(false);
            b.setDate(WHEN);
            b.addCertStore(inters);
            return CertPathBuilder.getInstance("PKIX").build(b).getCertPath().getCertificates().size();
        });
        t("b maxlen", () -> {
            X509CertSelector target = new X509CertSelector();
            target.setCertificate(cert("leaf"));
            PKIXBuilderParameters b = new PKIXBuilderParameters(Collections.singleton(new TrustAnchor(cert("root"), null)), target);
            b.setRevocationEnabled(false);
            b.setDate(WHEN);
            b.setMaxPathLength(0);
            b.addCertStore(inters);
            return CertPathBuilder.getInstance("PKIX").build(b).getCertPath().getCertificates().size();
        });
        t("b no target", () -> {
            PKIXBuilderParameters b = new PKIXBuilderParameters(Collections.singleton(new TrustAnchor(cert("root"), null)), null);
            b.setRevocationEnabled(false);
            return CertPathBuilder.getInstance("PKIX").build(b).getCertPath().getCertificates().size();
        });
        t("b revoked", () -> {
            X509CertSelector target = new X509CertSelector();
            target.setCertificate(cert("leafrev"));
            PKIXBuilderParameters b = new PKIXBuilderParameters(Collections.singleton(new TrustAnchor(cert("root"), null)), target);
            b.setDate(WHEN);
            b.addCertStore(inters);
            b.addCertStore(CertStore.getInstance("Collection", new CollectionCertStoreParameters(Arrays.asList(ic, rc))));
            return CertPathBuilder.getInstance("PKIX").build(b).getCertPath().getCertificates().size();
        });
        t("b bad params", () -> CertPathBuilder.getInstance("PKIX").build(new PKIXParameters(Collections.singleton(new TrustAnchor(cert("root"), null)))));
        p("b default", CertPathBuilder.getDefaultType());
        // exceptions
        CertPathValidatorException ex = new CertPathValidatorException("m", new RuntimeException("c"), cp, 1, CertPathValidatorException.BasicReason.EXPIRED);
        p("exc", ex.getMessage() + " " + ex.getIndex() + " " + ex.getReason() + " " + ex.getCertPath().equals(cp) + " " + ex.getCause().getMessage());
        CertPathValidatorException ex2 = new CertPathValidatorException();
        p("exc2", ex2.getMessage() + " " + ex2.getIndex() + " " + ex2.getReason() + " " + ex2.getCertPath() + " " + ex2.getCause());
        CertPathValidatorException ex3 = new CertPathValidatorException(new RuntimeException("why"));
        p("exc3", ex3.getMessage() + " " + ex3.getIndex());
        t("exc idx", () -> new CertPathValidatorException("m", null, cp, 5));
        t("exc idx2", () -> new CertPathValidatorException("m", null, null, 0));
        p("reasons", Arrays.toString(CertPathValidatorException.BasicReason.values()));
        CertificateRevokedException cre = new CertificateRevokedException(new Date(0), CRLReason.KEY_COMPROMISE, new X500Principal("CN=A"), Collections.<String, Extension>emptyMap());
        p("cre", cre.getRevocationReason() + " " + cre.getAuthorityName() + " " + cre.getRevocationDate().getTime() + " " + cre.getExtensions() + " " + cre.getInvalidityDate());
        p("cre msg", norm(cre.getMessage()));
        return out.toString();
    }
    static String iter(Iterator<String> it) { List<String> l = new ArrayList<>(); while (it.hasNext()) l.add(it.next()); return l.toString(); }
}
