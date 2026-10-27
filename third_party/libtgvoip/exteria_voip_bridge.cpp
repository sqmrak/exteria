#include "exteria_voip_bridge.h"

#include <string.h>

#include <memory>
#include <vector>

/* the aes helpers of openssl 3 are deprecated but still in the library, and libtgvoip's crypto hooks are made of exactly these */
#define OPENSSL_SUPPRESS_DEPRECATED
#include <openssl/aes.h>
#include <openssl/modes.h>
#include <openssl/rand.h>
#include <openssl/sha.h>

#include "VoIPController.h"

using namespace tgvoip;

struct exteria_voip {
    VoIPController *controller;
    exteria_voip_state_callback state;
    exteria_voip_bars_callback bars;
    void *context;
};

static void crypto_rand_bytes(uint8_t *buffer, size_t length) {
    RAND_bytes(buffer, (int)length);
}

static void crypto_sha1(uint8_t *message, size_t length, uint8_t *output) {
    SHA1(message, length, output);
}

static void crypto_sha256(uint8_t *message, size_t length, uint8_t *output) {
    SHA256(message, length, output);
}

/* the ige and cbc modes advance the iv they are given, and libtgvoip passes it again for the next block, so the caller's copy is kept */
static void crypto_aes_ige_encrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY schedule;
    uint8_t local[32];
    memcpy(local, iv, sizeof(local));
    AES_set_encrypt_key(key, 256, &schedule);
    AES_ige_encrypt(in, out, length, &schedule, local, AES_ENCRYPT);
}

static void crypto_aes_ige_decrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY schedule;
    uint8_t local[32];
    memcpy(local, iv, sizeof(local));
    AES_set_decrypt_key(key, 256, &schedule);
    AES_ige_encrypt(in, out, length, &schedule, local, AES_DECRYPT);
}

static void crypto_aes_ctr_encrypt(uint8_t *inout, size_t length, uint8_t *key, uint8_t *iv, uint8_t *ecount, uint32_t *num) {
    AES_KEY schedule;
    AES_set_encrypt_key(key, 256, &schedule);
    unsigned int position = *num;
    CRYPTO_ctr128_encrypt(inout, inout, length, &schedule, iv, ecount, &position, (block128_f)AES_encrypt);
    *num = position;
}

static void crypto_aes_cbc_encrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY schedule;
    uint8_t local[16];
    memcpy(local, iv, sizeof(local));
    AES_set_encrypt_key(key, 256, &schedule);
    AES_cbc_encrypt(in, out, length, &schedule, local, AES_ENCRYPT);
}

static void crypto_aes_cbc_decrypt(uint8_t *in, uint8_t *out, size_t length, uint8_t *key, uint8_t *iv) {
    AES_KEY schedule;
    uint8_t local[16];
    memcpy(local, iv, sizeof(local));
    AES_set_decrypt_key(key, 256, &schedule);
    AES_cbc_encrypt(in, out, length, &schedule, local, AES_DECRYPT);
}

static void install_crypto(void) {
    static bool installed = false;
    if (installed) return;
    VoIPController::crypto.rand_bytes = crypto_rand_bytes;
    VoIPController::crypto.sha1 = crypto_sha1;
    VoIPController::crypto.sha256 = crypto_sha256;
    VoIPController::crypto.aes_ige_encrypt = crypto_aes_ige_encrypt;
    VoIPController::crypto.aes_ige_decrypt = crypto_aes_ige_decrypt;
    VoIPController::crypto.aes_ctr_encrypt = crypto_aes_ctr_encrypt;
    VoIPController::crypto.aes_cbc_encrypt = crypto_aes_cbc_encrypt;
    VoIPController::crypto.aes_cbc_decrypt = crypto_aes_cbc_decrypt;
    installed = true;
}

static void state_changed(VoIPController *controller, int state) {
    exteria_voip *voip = (exteria_voip *)controller->implData;
    if (voip && voip->state) voip->state(voip->context, state);
}

static void bars_changed(VoIPController *controller, int bars) {
    exteria_voip *voip = (exteria_voip *)controller->implData;
    if (voip && voip->bars) voip->bars(voip->context, bars);
}

const char *exteria_voip_version(void) {
    return VoIPController::GetVersion();
}

exteria_voip *exteria_voip_create(const exteria_voip_endpoint *endpoints, size_t count, const uint8_t key[EXTERIA_VOIP_KEY_LEN], int outgoing,
                                  int allow_p2p, int32_t max_layer, exteria_voip_state_callback state, exteria_voip_bars_callback bars,
                                  void *context) {
    if (!endpoints || count == 0 || !key) return NULL;
    install_crypto();
    std::vector<Endpoint> remote;
    for (size_t i = 0; i < count; ++i) {
        IPv4Address v4(endpoints[i].ip);
        IPv6Address v6(endpoints[i].ipv6);
        unsigned char tag[EXTERIA_VOIP_TAG_LEN];
        memcpy(tag, endpoints[i].peer_tag, sizeof(tag));
        remote.push_back(Endpoint(endpoints[i].id, endpoints[i].port, v4, v6, endpoints[i].tcp ? Endpoint::TYPE_TCP_RELAY : Endpoint::TYPE_UDP_RELAY, tag));
    }
    exteria_voip *voip = new exteria_voip();
    voip->state = state;
    voip->bars = bars;
    voip->context = context;
    voip->controller = new VoIPController();
    voip->controller->implData = voip;
    VoIPController::Callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.connectionStateChanged = state_changed;
    callbacks.signalBarCountChanged = bars_changed;
    voip->controller->SetCallbacks(callbacks);
    /* the voice processing audio unit cancels the echo and levels the microphone itself, and the engine's own processors are not built */
    VoIPController::Config config(30.0, 20.0, DATA_SAVING_NEVER, false, false, false, false);
    voip->controller->SetConfig(config);
    voip->controller->SetEncryptionKey((char *)key, outgoing != 0);
    voip->controller->SetRemoteEndpoints(remote, allow_p2p != 0, max_layer);
    voip->controller->SetNetworkType(NET_TYPE_OTHER_MOBILE);
    return voip;
}

void exteria_voip_start(exteria_voip *voip) {
    if (!voip) return;
    voip->controller->Start();
    voip->controller->Connect();
}

void exteria_voip_set_muted(exteria_voip *voip, int muted) {
    if (voip) voip->controller->SetMicMute(muted != 0);
}

int exteria_voip_bars(exteria_voip *voip) {
    return voip ? voip->controller->GetSignalBarsCount() : 0;
}

int exteria_voip_last_error(exteria_voip *voip) {
    return voip ? voip->controller->GetLastError() : 0;
}

int64_t exteria_voip_relay_id(exteria_voip *voip) {
    return voip ? voip->controller->GetPreferredRelayID() : 0;
}

void exteria_voip_destroy(exteria_voip *voip) {
    if (!voip) return;
    /* no callback may run once the controller starts to go, since it holds the pointer to this struct */
    voip->state = NULL;
    voip->bars = NULL;
    voip->controller->Stop();
    delete voip->controller;
    delete voip;
}
