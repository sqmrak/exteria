#include "exteria_team.h"

#define DEV ExteriaMarkDeveloper
#define OFF ExteriaMarkOfficialTester
#define BUG ExteriaMarkBugHunter
#define PROMO ExteriaMarkPromotion
#define MANAGER ExteriaMarkManager

static const exteria_team_member members[] = {
    {INT64_C(8190976381), "fly1ngangel", OFF, 1},
    {INT64_C(558269829), "kfrom7", OFF, 1},
    {INT64_C(8796163695), "anazerka", DEV | OFF, 1},
    {INT64_C(5561372449), "CookieValerka", OFF, 1},
    {INT64_C(6198068395), "inraxx", OFF, 1},
    {INT64_C(8510741400), "LimeDev", DEV | OFF, 1},
    {INT64_C(6392973712), "Lineysom", OFF, 1},
    {INT64_C(749971450), "shizotoaster", OFF, 1},
    {INT64_C(5191291829), "loveiOS6", DEV | OFF, 1},
    {INT64_C(5586697397), "xaxaxaxaxxaxaxaxaxaxaxaxaxaxa", OFF | BUG, 1},
    {INT64_C(7118797604), "merwleem", OFF | MANAGER | PROMO, 1},
    {INT64_C(8256044236), "s3dativee", OFF, 1},
    {INT64_C(1415625115), "not_a_modder", OFF | BUG, 1},
    {INT64_C(6233584668), "svcayon4ik", DEV, 0},
    {EXTERIA_TEAM_LEAD_ID, "sqmrak", ExteriaMarkLead | ExteriaMarkSenko, 0},
    {INT64_C(5435278149), "QWERTYU1OPZ", DEV, 0},
    {INT64_C(588487063), "menstry", DEV | OFF, 1},
    {INT64_C(5390055485), "nestorvashenko", DEV, 0},
    {INT64_C(1448306214), "illyagif", DEV, 0},
    {INT64_C(940506028), "Maks_097", ExteriaMarkTester, 0},
    {INT64_C(7801631734), "QuaIcomm", ExteriaMarkTester, 0},
    {INT64_C(8221692135), "cmp_73", ExteriaMarkCaution, 0},
    {INT64_C(7073807722), "Radickdz", PROMO, 0},
    {INT64_C(5850832376), "Xmas_UnrealKot", PROMO, 0}
};

size_t exteria_team_member_count(void) { return sizeof(members) / sizeof(members[0]); }
const exteria_team_member *exteria_team_member_at(size_t index) {
    return index < exteria_team_member_count() ? &members[index] : NULL;
}
const exteria_team_member *exteria_team_member_for_id(int64_t id) {
    for (size_t i = 0; i < exteria_team_member_count(); ++i) if (members[i].id == id) return &members[i];
    return NULL;
}
uint32_t exteria_team_marks(int64_t id) {
    const exteria_team_member *member = exteria_team_member_for_id(id);
    return member ? member->marks : 0;
}
int exteria_team_is_developer(int64_t id) {
    return (exteria_team_marks(id) & (ExteriaMarkDeveloper | ExteriaMarkLead)) != 0;
}
