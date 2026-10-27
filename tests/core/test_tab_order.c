#include "exteria_tab_order.h"
#include "test_util.h"

int main(void) {
    int order[] = {EXTERIA_TAB_CHATS, EXTERIA_TAB_CONTACTS, EXTERIA_TAB_SETTINGS, EXTERIA_TAB_PROFILE};
    int invalid[] = {EXTERIA_TAB_CHATS, EXTERIA_TAB_CHATS, EXTERIA_TAB_SETTINGS, EXTERIA_TAB_PROFILE};
    CHECK(exteria_tab_order_valid(order, EXTERIA_TAB_SLOTS));
    CHECK(!exteria_tab_order_valid(invalid, EXTERIA_TAB_SLOTS));
    CHECK(!exteria_tab_order_valid(order, 3));
    CHECK(!exteria_tab_order_valid(NULL, EXTERIA_TAB_SLOTS));
    CHECK(!exteria_tab_order_replace(order, 0, EXTERIA_TAB_CALLS));
    CHECK_EQ_INT(order[0], EXTERIA_TAB_CHATS);
    CHECK(exteria_tab_order_replace(order, 1, EXTERIA_TAB_CALLS));
    CHECK_EQ_INT(order[1], EXTERIA_TAB_CALLS);
    CHECK(exteria_tab_order_replace(order, 0, EXTERIA_TAB_SETTINGS));
    CHECK_EQ_INT(order[0], EXTERIA_TAB_SETTINGS);
    CHECK_EQ_INT(order[2], EXTERIA_TAB_CHATS);
    CHECK(exteria_tab_order_move(order, 0, 3));
    CHECK_EQ_INT(order[3], EXTERIA_TAB_SETTINGS);
    CHECK(exteria_tab_order_move(order, 3, 0));
    CHECK_EQ_INT(order[0], EXTERIA_TAB_SETTINGS);
    CHECK(!exteria_tab_order_move(order, 4, 0));
    CHECK(!exteria_tab_order_replace(order, 0, EXTERIA_TAB_KINDS));
    CHECK(exteria_tab_order_valid(order, EXTERIA_TAB_SLOTS));
    for (size_t from = 0; from < EXTERIA_TAB_SLOTS; ++from) {
        for (size_t to = 0; to < EXTERIA_TAB_SLOTS; ++to) {
            int copy[] = {EXTERIA_TAB_CHATS, EXTERIA_TAB_CONTACTS, EXTERIA_TAB_SETTINGS, EXTERIA_TAB_PROFILE};
            CHECK(exteria_tab_order_move(copy, from, to));
            CHECK(exteria_tab_order_valid(copy, EXTERIA_TAB_SLOTS));
            CHECK(exteria_tab_order_move(copy, to, from));
            for (size_t i = 0; i < EXTERIA_TAB_SLOTS; ++i) CHECK_EQ_INT(copy[i], (int)i);
        }
    }
    return test_finish("test_tab_order");
}
