#ifndef EXTERIA_TEAM_H
#define EXTERIA_TEAM_H

#include <stddef.h>
#include <stdint.h>

enum {
    ExteriaMarkDeveloper = 1,
    ExteriaMarkSenko = 2,
    ExteriaMarkTester = 4,
    ExteriaMarkLead = 8,
    ExteriaMarkCaution = 16,
    ExteriaMarkPromotion = 32,
    ExteriaMarkBugHunter = 64,
    ExteriaMarkOfficialTester = 128,
    ExteriaMarkManager = 256
};

#define EXTERIA_TEAM_LEAD_ID INT64_C(8202789099)

/* names are lookup hints; identity and marks belong to the numeric account id */
typedef struct exteria_team_member {
    int64_t id;
    const char *username;
    uint32_t marks;
    int official_list;
} exteria_team_member;

const exteria_team_member *exteria_team_member_for_id(int64_t id);
size_t exteria_team_member_count(void);
const exteria_team_member *exteria_team_member_at(size_t index);
uint32_t exteria_team_marks(int64_t id);
int exteria_team_is_developer(int64_t id);

#endif
