map-roots.pem adds GlobalSign Root CA R3 for the current tile.openstreetmap.org
chain. the map loader combines this file with the existing roots.pem bundle.
it does not change the roots used to register Shiro.

source: https://support.globalsign.com/ca-certificates/root-certificates/globalsign-root-certificates
SHA-256: CBB522D7B7F127AD6A0113865BDF1CD4102E7D0759AF635A7CF4720DC963C53B
valid until: 2029-03-18

the fingerprint records the bundled certificate's origin. it is not a runtime
certificate pin. hostname, chain and dates are checked by OpenSSL.
