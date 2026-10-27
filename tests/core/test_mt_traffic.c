#include "test_util.h"
#include "exteria_mt_socket.h"
#include "exteria_mt_traffic.h"

#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void) {
    int pair[2];
    exteria_mt_socket a, b;
    exteria_traffic taken;
    uint8_t data[5] = {1, 2, 3, 4, 5}, back[8];
    size_t got = 0;

    exteria_traffic_take(&taken);
    exteria_traffic_add(10, 20);
    exteria_traffic_set_cellular(1);
    exteria_traffic_add(1, 2);
    exteria_traffic_set_cellular(0);
    exteria_traffic_take(&taken);
    CHECK_EQ_INT((int)taken.sent[0], 10);
    CHECK_EQ_INT((int)taken.received[0], 20);
    CHECK_EQ_INT((int)taken.sent[1], 1);
    CHECK_EQ_INT((int)taken.received[1], 2);
    /* a take starts the count again */
    exteria_traffic_take(&taken);
    CHECK_EQ_INT((int)(taken.sent[0] + taken.sent[1] + taken.received[0] + taken.received[1]), 0);

    /* the sockets count what goes through them: five bytes written on one end and read on the other are counted once each way */
    CHECK_EQ_INT(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    /* the socket reads wait with poll, so the ends are non blocking as the ones the app opens */
    CHECK_EQ_INT(fcntl(pair[0], F_SETFL, O_NONBLOCK), 0);
    CHECK_EQ_INT(fcntl(pair[1], F_SETFL, O_NONBLOCK), 0);
    exteria_mt_socket_init(&a);
    exteria_mt_socket_init(&b);
    CHECK_EQ_INT(exteria_mt_socket_adopt(&a, pair[0]), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_socket_adopt(&b, pair[1]), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_socket_write_all(&a, data, sizeof(data), 1000), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_socket_read(&b, back, sizeof(back), &got, 1000), EXTERIA_OK);
    CHECK_EQ_INT((int)got, 5);
    exteria_traffic_take(&taken);
    CHECK_EQ_INT((int)taken.sent[0], 5);
    CHECK_EQ_INT((int)taken.received[0], 5);
    /* a read that finds nothing counts nothing */
    CHECK_EQ_INT(exteria_mt_socket_read(&b, back, sizeof(back), &got, 0), EXTERIA_E_TIMEOUT);
    exteria_traffic_take(&taken);
    CHECK_EQ_INT((int)taken.received[0], 0);
    exteria_mt_socket_close(&a);
    exteria_mt_socket_close(&b);
    return test_finish("test_mt_traffic");
}
