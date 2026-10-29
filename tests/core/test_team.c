#include "test_util.h"
#include "exteria_team.h"

#include <string.h>

int main(void) {
    static const int64_t expected[] = {
        INT64_C(8190976381), INT64_C(558269829), INT64_C(8796163695), INT64_C(5561372449), INT64_C(6198068395),
        INT64_C(8510741400), INT64_C(6392973712), INT64_C(749971450), INT64_C(5191291829), INT64_C(5586697397),
        INT64_C(7118797604), INT64_C(8256044236), INT64_C(1415625115), INT64_C(6233584668)
    };
    size_t official = 0;
    CHECK(exteria_team_member_for_id(0) == NULL);
    CHECK(exteria_team_member_for_id(-1) == NULL);
    CHECK(exteria_team_member_at(exteria_team_member_count()) == NULL);
    CHECK_EQ_INT(exteria_team_marks(EXTERIA_TEAM_LEAD_ID), ExteriaMarkLead | ExteriaMarkSenko);
    CHECK(exteria_team_is_developer(EXTERIA_TEAM_LEAD_ID));
    CHECK(exteria_team_is_developer(INT64_C(8510741400)));
    CHECK_EQ_INT(exteria_team_marks(INT64_C(8510741400)), ExteriaMarkDeveloper | ExteriaMarkOfficialTester);
    CHECK(!exteria_team_is_developer(INT64_C(8190976381)));
    CHECK_EQ_INT(exteria_team_marks(INT64_C(8190976381)), ExteriaMarkOfficialTester);
    CHECK_EQ_INT(exteria_team_marks(INT64_C(1415625115)), ExteriaMarkOfficialTester | ExteriaMarkBugHunter);
    CHECK_EQ_INT(exteria_team_marks(INT64_C(5805414308)), 0);
    CHECK_EQ_INT(exteria_team_marks(INT64_C(6459976684)), 0);
    CHECK_EQ_INT(exteria_team_marks(INT64_C(5153994027)), 0);
    for (size_t i = 0; i < exteria_team_member_count(); ++i) {
        const exteria_team_member *member = exteria_team_member_at(i);
        CHECK(member && member->id > 0 && member->username && member->username[0]);
        CHECK(exteria_team_member_for_id(member->id) == member);
        if (member->official_list) {
            CHECK(official < sizeof(expected) / sizeof(expected[0]));
            if (official < sizeof(expected) / sizeof(expected[0])) CHECK(member->id == expected[official]);
            ++official;
            CHECK(member->marks & ExteriaMarkOfficialTester);
        }
        for (size_t j = 0; j < i; ++j) {
            const exteria_team_member *other = exteria_team_member_at(j);
            CHECK(member->id != other->id);
            CHECK(strcmp(member->username, other->username) != 0);
        }
    }
    CHECK_EQ_INT((int)official, 14);
    return test_finish("test_team");
}
