web-roots.pem adds Go Daddy Root Certificate Authority - G2 for the current telegra.ph
chain (leaf, GoDaddy TLS Intermediate CA DV - R1v1, GoDaddy TLS Root CA - R1, then this root).
the article loader combines this file with the roots.pem bundle, and only for telegra.ph
(on every route, through the Shiro tunnel or directly). it does not change the roots used to register Shiro or the map.

source: the Go Daddy root bundle of the system, published at https://certs.godaddy.com/repository
SHA-256: 45140B3247EB9CC8C5B4F0D7B53091F73292089E6E5A63E2749DD3ACA9198EDA
valid until: 2037-12-31

the fingerprint records the bundled certificate's origin. it is not a runtime pin.
hostname, chain and dates are checked by OpenSSL.
