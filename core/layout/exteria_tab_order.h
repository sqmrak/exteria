#ifndef EXTERIA_TAB_ORDER_H
#define EXTERIA_TAB_ORDER_H

#include <stddef.h>

enum { EXTERIA_TAB_CHATS, EXTERIA_TAB_CONTACTS, EXTERIA_TAB_SETTINGS, EXTERIA_TAB_PROFILE, EXTERIA_TAB_CALLS, EXTERIA_TAB_KINDS };
enum { EXTERIA_TAB_SLOTS = 4 };

int exteria_tab_order_valid(const int *order, size_t count);
int exteria_tab_order_replace(int order[EXTERIA_TAB_SLOTS], size_t slot, int kind);
int exteria_tab_order_move(int order[EXTERIA_TAB_SLOTS], size_t from, size_t to);

#endif
