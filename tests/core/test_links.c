#include "test_util.h"
#include "exteria_links.h"

static exteria_tg_link link_of(const char *url) {
    exteria_tg_link l;
    CHECK_EQ_INT(exteria_tg_link_parse(url, &l), EXTERIA_OK);
    return l;
}

static void test_invite_links(void) {
    exteria_tg_link l = link_of("https://t.me/+AbCd-Ef_12");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVITE);
    CHECK(!strcmp(l.slug, "AbCd-Ef_12"));
    l = link_of("https://t.me/%2BAbCd-Ef_12?fbclid=long-tracking_value1234567890#fragment");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVITE);
    CHECK(!strcmp(l.slug, "AbCd-Ef_12"));
    l = link_of("https://t.me/%2bAbCd%2DEf_12?fbclid=value");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVITE);
    CHECK(!strcmp(l.slug, "AbCd-Ef_12"));
    CHECK_EQ_INT(link_of("https://t.me/%2B1234567?fbclid=value").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/%252BAbCd").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/%2Babc%2Fdef").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/%2Babc%00def").kind, EXTERIA_LINK_OTHER);
    l = link_of("https://t.me/joinchat/AAAA");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVITE);
    CHECK(!strcmp(l.slug, "AAAA"));
    l = link_of("tg://join?invite=XyZ_9");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVITE);
    CHECK(!strcmp(l.slug, "XyZ_9"));
    CHECK_EQ_INT(link_of("tg://join").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/+ab$cd").kind, EXTERIA_LINK_OTHER);
}

static void test_web_links(void) {
    exteria_tg_link l = link_of("https://t.me/durov_bot");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK(!strcmp(l.username, "durov_bot"));
    CHECK_EQ_INT(l.has_start, 0);
    l = link_of("https://t.me/helper_bot?start=ref-12_a");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK_EQ_INT(l.has_start, 1);
    CHECK(!strcmp(l.start, "ref-12_a"));
    l = link_of("http://telegram.me/helper_bot?start=");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK_EQ_INT(l.has_start, 1);
    CHECK_EQ_INT(l.start[0], 0);
    l = link_of("https://www.telegram.dog/helper_bot/");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    l = link_of("https://T.ME/Helper_Bot?startapp=go%5Fnow");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK(!strcmp(l.username, "Helper_Bot"));
    CHECK_EQ_INT(l.has_start_app, 1);
    CHECK(!strcmp(l.start_app, "go_now"));
    l = link_of("https://t.me/helper_bot/shop?startapp=a1&start=b2#frag");
    CHECK(!strcmp(l.app_name, "shop"));
    CHECK(!strcmp(l.start_app, "a1"));
    CHECK(!strcmp(l.start, "b2"));
    CHECK_EQ_INT(l.message_id, 0);
    l = link_of("https://t.me/news_channel/4521");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK_EQ_INT(l.message_id, 4521);
    CHECK_EQ_INT(l.app_name[0], 0);
    l = link_of("https://t.me/news_channel/4521?comment=3");
    CHECK_EQ_INT(l.message_id, 4521);
    l = link_of("https://t.me/helper_bot#start=x");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK_EQ_INT(l.has_start, 0);
}

static void test_invoice_and_other(void) {
    exteria_tg_link l = link_of("https://t.me/$abc-DEF_1");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVOICE);
    CHECK(!strcmp(l.slug, "abc-DEF_1"));
    l = link_of("https://t.me/invoice/xyz9");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVOICE);
    CHECK(!strcmp(l.slug, "xyz9"));
    l = link_of("https://t.me/invoice/");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_OTHER);
    l = link_of("https://t.me/invoice/a%20b");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_OTHER);
    l = link_of("tg://invoice?slug=pay_1");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_INVOICE);
    CHECK(!strcmp(l.slug, "pay_1"));
    /* pages of telegram that are not a user, invite links and plain addresses are left to the system */
    CHECK_EQ_INT(link_of("https://t.me/joinchat").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/+").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/+15551234567").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/addstickers/Cats").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/c/123/4").kind, EXTERIA_LINK_PRIVATE_POST);
    CHECK_EQ_INT(link_of("https://t.me/call/abc123").kind, EXTERIA_LINK_CALL);
    CHECK_EQ_INT(link_of("https://t.me/").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://example.org/helper_bot").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me.evil.example/helper_bot").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://evil.example/t.me/helper_bot").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("mailto:a@b.c").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("ftp://t.me/helper_bot").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/bad-name").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/012345678901234567890123456789012").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("").kind, EXTERIA_LINK_OTHER);
}

static void test_private_posts(void) {
    exteria_tg_link l = link_of("https://t.me/c/1237513492/102643");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PRIVATE_POST);
    CHECK(l.channel_id == 1237513492);
    CHECK_EQ_INT(l.message_id, 102643);
    /* the number of a channel may pass 32 bits */
    l = link_of("https://t.me/c/2500000000/7");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PRIVATE_POST);
    CHECK(l.channel_id == 2500000000LL);
    /* a topic stands before the post, and the post is the last number */
    l = link_of("https://www.telegram.me/c/55/3/900?single");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PRIVATE_POST);
    CHECK(l.channel_id == 55);
    CHECK_EQ_INT(l.message_id, 900);
    l = link_of("https://t.me/c/55");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PRIVATE_POST);
    CHECK_EQ_INT(l.message_id, 0);
    l = link_of("tg://privatepost?channel=1237513492&post=102643");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PRIVATE_POST);
    CHECK(l.channel_id == 1237513492);
    CHECK_EQ_INT(l.message_id, 102643);
    CHECK_EQ_INT(link_of("https://t.me/c/").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/c/abc/5").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/c/55/x").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/c/55/1/2/3").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("https://t.me/c/12345678901234/5").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://privatepost?channel=0&post=1").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://privatepost?post=1").kind, EXTERIA_LINK_OTHER);
}

static void test_tg_scheme(void) {
    exteria_tg_link l = link_of("tg://resolve?domain=helper_bot&start=go&appname=shop&startapp=z9");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK(!strcmp(l.username, "helper_bot"));
    CHECK(!strcmp(l.start, "go"));
    CHECK(!strcmp(l.app_name, "shop"));
    CHECK(!strcmp(l.start_app, "z9"));
    l = link_of("tg:resolve?domain=helper_bot");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    l = link_of("TG://Resolve?domain=helper_bot&post=77");
    CHECK_EQ_INT(l.message_id, 77);
    CHECK_EQ_INT(link_of("tg://resolve").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://resolve?domain=").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://resolve?domain=a%2fb").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://login?token=abc").kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(link_of("tg://user?id=5").kind, EXTERIA_LINK_OTHER);
}

static void test_parameters(void) {
    exteria_tg_link l;
    char many[EXTERIA_LINK_URL_MAX + 40];
    /* a parameter the server would not take is dropped, never cut or passed on */
    l = link_of("https://t.me/helper_bot?start=a%20b");
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK_EQ_INT(l.has_start, 0);
    l = link_of("https://t.me/helper_bot?start=a%2");
    CHECK_EQ_INT(l.has_start, 0);
    l = link_of("https://t.me/helper_bot?start=a%zz");
    CHECK_EQ_INT(l.has_start, 0);
    l = link_of("https://t.me/helper_bot?start=0123456789012345678901234567890123456789012345678901234567890123");
    CHECK_EQ_INT(l.has_start, 1);
    CHECK_EQ_INT(strlen(l.start), 64);
    l = link_of("https://t.me/helper_bot?start=01234567890123456789012345678901234567890123456789012345678901234");
    CHECK_EQ_INT(l.has_start, 0);
    l = link_of("https://t.me/helper_bot?x=1&start=first&start=second");
    CHECK(!strcmp(l.start, "first"));
    l = link_of("https://t.me/helper_bot?xstart=1");
    CHECK_EQ_INT(l.has_start, 0);
    memset(many, 'a', sizeof(many));
    many[sizeof(many) - 1] = 0;
    CHECK_EQ_INT(exteria_tg_link_parse(many, &l), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tg_link_parse(NULL, &l), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tg_link_parse("x", NULL), EXTERIA_E_ARG);
}

static void test_mentions_and_commands(void) {
    char name[40], command[40], bot[40];
    CHECK_EQ_INT(exteria_mention_name("@Some_Bot", name, sizeof(name)), EXTERIA_OK);
    CHECK(!strcmp(name, "Some_Bot"));
    CHECK_EQ_INT(exteria_mention_name("plain", name, sizeof(name)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mention_name("@", name, sizeof(name)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_mention_name("@a b", name, sizeof(name)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_mention_name("@a-b", name, sizeof(name)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_mention_name("@Some_Bot", name, 4), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_command_split("/start", command, sizeof(command), bot, sizeof(bot)), EXTERIA_OK);
    CHECK(!strcmp(command, "/start"));
    CHECK_EQ_INT(bot[0], 0);
    CHECK_EQ_INT(exteria_bot_command_split("/start@helper_bot", command, sizeof(command), bot, sizeof(bot)), EXTERIA_OK);
    CHECK(!strcmp(command, "/start"));
    CHECK(!strcmp(bot, "helper_bot"));
    CHECK_EQ_INT(exteria_bot_command_split("start", command, sizeof(command), bot, sizeof(bot)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_command_split("/", command, sizeof(command), bot, sizeof(bot)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_command_split("/@bot", command, sizeof(command), bot, sizeof(bot)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_command_split("/a b", command, sizeof(command), bot, sizeof(bot)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_command_split("/a@", command, sizeof(command), bot, sizeof(bot)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_command_split("/012345678901234567890123456789012", command, sizeof(command), bot, sizeof(bot)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_bot_command_split("/a", command, 8, bot, sizeof(bot)), EXTERIA_E_ARG);
}

static void test_voice_chat_links(void) {
    exteria_tg_link l;
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/somegroup?videochat=AbC_123", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK(!strcmp(l.username, "somegroup"));
    CHECK_EQ_INT(l.has_voice_chat, 1);
    CHECK(!strcmp(l.voice_chat, "AbC_123"));
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/somegroup?voicechat=xyz&start=1", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.has_voice_chat, 1);
    CHECK(!strcmp(l.voice_chat, "xyz"));
    CHECK_EQ_INT(l.has_start, 1);
    /* the parameter without a value still asks for the voice chat, without an invite hash */
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/somegroup?videochat", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.has_voice_chat, 1);
    CHECK_EQ_INT(l.voice_chat[0], 0);
    CHECK_EQ_INT(exteria_tg_link_parse("tg://resolve?domain=somegroup&videochat=h1", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK(!strcmp(l.voice_chat, "h1"));
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/somegroup", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.has_voice_chat, 0);
    /* a hash with a character the server would not take is dropped */
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/somegroup?videochat=a%20b", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_PEER);
    CHECK_EQ_INT(l.has_voice_chat, 0);
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/call/AbC-1_x", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_CALL);
    CHECK(!strcmp(l.slug, "AbC-1_x"));
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/call/", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_OTHER);
    CHECK_EQ_INT(exteria_tg_link_parse("https://t.me/call", &l), EXTERIA_OK);
    CHECK_EQ_INT(l.kind, EXTERIA_LINK_OTHER);
}

int main(void) {
    test_invite_links();
    test_web_links();
    test_invoice_and_other();
    test_private_posts();
    test_tg_scheme();
    test_parameters();
    test_mentions_and_commands();
    test_voice_chat_links();
    return test_finish("test_links");
}
