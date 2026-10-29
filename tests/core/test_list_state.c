#include "exteria_list_state.h"
#include "test_util.h"

static void check_presentation(size_t count, int loading, int failed, int header, exteria_list_state state, int table_visible) {
    exteria_list_presentation presentation = exteria_list_present(count, loading, failed, header);
    CHECK_EQ_INT(presentation.state, state);
    CHECK_EQ_INT(presentation.table_visible, table_visible);
}

static void all_presentation_states(void) {
    for (int header = 0; header <= 1; ++header) {
        check_presentation(0, 0, 0, header, EXTERIA_LIST_EMPTY, header);
        check_presentation(0, 1, 0, header, EXTERIA_LIST_LOADING, header);
        check_presentation(0, 0, 1, header, EXTERIA_LIST_FAILED, header);
        check_presentation(0, 1, 1, header, EXTERIA_LIST_LOADING, header);
        /* cached rows remain useful while refreshing or after a failed refresh */
        check_presentation(5, 0, 0, header, EXTERIA_LIST_CONTENT, 1);
        check_presentation(5, 1, 0, header, EXTERIA_LIST_CONTENT, 1);
        check_presentation(5, 0, 1, header, EXTERIA_LIST_CONTENT, 1);
        check_presentation(5, 1, 1, header, EXTERIA_LIST_CONTENT, 1);
    }
}

static void folder_switch_keeps_tabs_reachable(void) {
    check_presentation(100, 0, 0, 1, EXTERIA_LIST_CONTENT, 1);
    /* no channels in the current page: keep the tabs while the folder loads */
    check_presentation(0, 1, 0, 1, EXTERIA_LIST_LOADING, 1);
    /* a timeout must offer retry even though all chats loaded before this folder */
    check_presentation(0, 0, 1, 1, EXTERIA_LIST_FAILED, 1);
    check_presentation(0, 1, 0, 1, EXTERIA_LIST_LOADING, 1);
    check_presentation(4, 0, 0, 1, EXTERIA_LIST_CONTENT, 1);
    /* a genuinely empty folder also keeps a route back to all chats */
    check_presentation(0, 0, 0, 1, EXTERIA_LIST_EMPTY, 1);
    check_presentation(0, 1, 0, 1, EXTERIA_LIST_LOADING, 1);
    check_presentation(100, 0, 0, 1, EXTERIA_LIST_CONTENT, 1);
}

int main(void) {
    uint32_t seconds = 99;
    all_presentation_states();
    folder_switch_keeps_tabs_reachable();
    CHECK(exteria_list_flood_wait("FLOOD_WAIT_17", &seconds));
    CHECK_EQ_INT(seconds, 17);
    CHECK(exteria_list_flood_wait("FLOOD_PREMIUM_WAIT_120", &seconds));
    CHECK_EQ_INT(seconds, 120);
    CHECK(!exteria_list_flood_wait("FLOOD_WAIT_0", &seconds));
    CHECK_EQ_INT(seconds, 0);
    CHECK(!exteria_list_flood_wait("FLOOD_WAIT_17x", &seconds));
    CHECK(!exteria_list_flood_wait("FLOOD_WAIT_2147483648", &seconds));
    CHECK(!exteria_list_flood_wait("FLOOD_WAIT", &seconds));
    CHECK(!exteria_list_flood_wait(NULL, &seconds));
    uint64_t deadline = exteria_list_flood_deadline(0, 5000, 17);
    CHECK_EQ_INT(deadline, 22000);
    CHECK_EQ_INT(exteria_list_flood_remaining(deadline, 5001), 17);
    CHECK_EQ_INT(exteria_list_flood_remaining(deadline, 21999), 1);
    CHECK_EQ_INT(exteria_list_flood_remaining(deadline, 22000), 0);
    CHECK_EQ_INT(exteria_list_flood_deadline(deadline, 6000, 1), deadline);
    CHECK_EQ_INT(exteria_list_flood_deadline(deadline, 6000, 30), 36000);
    CHECK(exteria_list_flood_deadline(0, UINT64_MAX - 5, 1) == UINT64_MAX);
    CHECK_EQ_INT(exteria_list_refresh_delay(1000, 0, 15000, 500), 500);
    CHECK_EQ_INT(exteria_list_refresh_delay(2000, 1000, 15000, 500), 14000);
    CHECK_EQ_INT(exteria_list_refresh_delay(16000, 1000, 15000, 500), 500);
    CHECK_EQ_INT(exteria_list_refresh_delay(500, 1000, 15000, 500), 15000);
    return test_finish("test_list_state");
}
