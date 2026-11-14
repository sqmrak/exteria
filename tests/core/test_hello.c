#include "exteria_hello.h"
#include "test_util.h"
#include <openssl/ssl.h>

int main(void) {
    SSL_CTX *context = SSL_CTX_new(TLS_client_method());
    SSL *ssl = SSL_new(context);
    BIO *read_bio = BIO_new(BIO_s_mem()), *write_bio = BIO_new(BIO_s_mem());
    uint8_t hello[16384], out[16389], rebuilt[16384];
    size_t length, out_len, cut, i;
    CHECK(context && ssl && read_bio && write_bio);
    SSL_set_bio(ssl, read_bio, write_bio);
    SSL_set_connect_state(ssl);
    CHECK_EQ_INT(SSL_set_tlsext_host_name(ssl, "api.cloudflareclient.com"), 1);
    CHECK(SSL_do_handshake(ssl) != 1);
    length = (size_t)BIO_read(write_bio, hello, (int)sizeof(hello));
    CHECK(length > 100 && length < sizeof(hello));
    CHECK_EQ_INT(exteria_hello_split(hello, length, out, sizeof(out), &out_len, &cut, 0), EXTERIA_OK);
    CHECK_EQ_INT(out_len, length + 5);
    CHECK(cut > 5 && cut < length);
    CHECK_EQ_INT(((size_t)out[3] << 8) | out[4], cut - 5);
    CHECK_EQ_INT(((size_t)out[cut + 3] << 8) | out[cut + 4], length - cut);
    memcpy(rebuilt, out, cut);
    rebuilt[3] = hello[3]; rebuilt[4] = hello[4];
    memcpy(rebuilt + cut, out + cut + 5, length - cut);
    CHECK_MEM(rebuilt, hello, length);
    { size_t first_cut = cut;
      CHECK_EQ_INT(exteria_hello_split(hello, length, out, sizeof(out), &out_len, &cut, 1), EXTERIA_OK);
      CHECK(cut > first_cut);
    }
    CHECK_EQ_INT(exteria_hello_split(hello, length, out, length, &out_len, &cut, 0), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(out_len, 0); CHECK_EQ_INT(cut, 0);
    for (i = 0; i < length; ++i) {
        CHECK(exteria_hello_split(hello, i, out, sizeof(out), &out_len, &cut, 0) != EXTERIA_OK);
        CHECK_EQ_INT(out_len, 0);
    }
    hello[0] = 23;
    CHECK_EQ_INT(exteria_hello_split(hello, length, out, sizeof(out), &out_len, &cut, 0), EXTERIA_E_MALFORMED);
    SSL_free(ssl); SSL_CTX_free(context);
    return test_finish("test_hello");
}
