#include "exteria_store.h"

#include <limits.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_tl_ids.h"

#define RECORD_MAX (1024u * 1024u)
#define PAGE_MAX 512u

/* peers share these counters by a hash, so two chats may move one together but a write never goes unseen */
#define VERSION_BUCKETS 64u

struct exteria_store {
    sqlite3 *db;
    int64_t account;
    int transaction;
    uint64_t bucket_version[VERSION_BUCKETS];
    uint64_t people_version;
    uint64_t sweep_version;
};

static size_t version_bucket(exteria_peer peer) {
    return (size_t)(((uint64_t)peer.id * 0x9e3779b97f4a7c15ull >> 40) + (uint64_t)peer.kind) % VERSION_BUCKETS;
}

static void note_write(exteria_store *s, exteria_record_kind kind, exteria_peer peer) {
    s->bucket_version[version_bucket(peer)]++;
    if (kind == EXTERIA_RECORD_USER || kind == EXTERIA_RECORD_CHAT) s->people_version++;
}

uint64_t exteria_store_peer_version(const exteria_store *s, exteria_peer peer) {
    if (!s) return 0;
    return s->bucket_version[version_bucket(peer)] + s->people_version + s->sweep_version;
}

static exteria_status sql_status(int rc) {
    switch (rc) {
        case SQLITE_OK: case SQLITE_DONE: case SQLITE_ROW: return EXTERIA_OK;
        case SQLITE_BUSY: case SQLITE_LOCKED: return EXTERIA_E_RETRY;
        case SQLITE_NOMEM: return EXTERIA_E_NOMEM;
        case SQLITE_TOOBIG: return EXTERIA_E_LIMIT;
        default: return EXTERIA_E_STORAGE;
    }
}

static exteria_status run(exteria_store *s, const char *sql) {
    return sql_status(sqlite3_exec(s->db, sql, NULL, NULL, NULL));
}

static exteria_status prepare(exteria_store *s, const char *sql, sqlite3_stmt **q) {
    *q = NULL;
    return sql_status(sqlite3_prepare_v2(s->db, sql, -1, q, NULL));
}

static exteria_status finish(sqlite3_stmt *q, exteria_status status) {
    int rc = sqlite3_finalize(q);
    return status != EXTERIA_OK ? status : sql_status(rc);
}

static exteria_status bind_key(sqlite3_stmt *q, exteria_store *s, exteria_record_kind kind,
                              exteria_peer peer, int64_t id) {
    int rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, peer.kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, peer.id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 5, id);
    return sql_status(rc);
}

static int valid_key(exteria_store *s, exteria_record_kind kind, exteria_peer peer) {
    return s && kind >= EXTERIA_RECORD_USER && kind <= EXTERIA_RECORD_MESSAGE_EDIT &&
           peer.kind >= 0 && peer.kind <= 3 && (peer.kind == 0 ? peer.id == 0 : peer.id > 0);
}

exteria_status exteria_store_open(exteria_store **out, const char *path, int64_t account_id) {
    exteria_store *s;
    sqlite3_stmt *q = NULL;
    exteria_status status;
    int version = -1;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!path || !*path || account_id <= 0) return EXTERIA_E_ARG;
    s = calloc(1, sizeof(*s));
    if (!s) return EXTERIA_E_NOMEM;
    s->account = account_id;
    status = sql_status(sqlite3_open_v2(path, &s->db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL));
    if (status != EXTERIA_OK) goto fail;
    sqlite3_limit(s->db, SQLITE_LIMIT_LENGTH, (int)RECORD_MAX + 4096);
    /* WAL avoids two slow flash syncs per update on iphone 3gs and 4; after power loss the server can replay lost commits with their cursor */
    status = run(s, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA journal_size_limit=1048576; PRAGMA foreign_keys=ON");
    if (status != EXTERIA_OK) goto fail;
    status = prepare(s, "PRAGMA user_version", &q);
    if (status != EXTERIA_OK) goto fail;
    if (sqlite3_step(q) == SQLITE_ROW) version = sqlite3_column_int(q, 0);
    status = finish(q, version < 0 ? EXTERIA_E_STORAGE : EXTERIA_OK);
    q = NULL;
    if (status != EXTERIA_OK) goto fail;
    if (version > 2) { status = EXTERIA_E_UNSUPPORTED; goto fail; }
    if (version == 0) {
        status = run(s,
            "BEGIN IMMEDIATE;"
            "CREATE TABLE records(account INTEGER NOT NULL,kind INTEGER NOT NULL,peer_kind INTEGER NOT NULL,"
            "peer INTEGER NOT NULL,id INTEGER NOT NULL,data BLOB NOT NULL,PRIMARY KEY(account,kind,peer_kind,peer,id));"
            "CREATE TABLE cursors(account INTEGER NOT NULL,channel INTEGER NOT NULL,pts INTEGER NOT NULL,"
            "qts INTEGER NOT NULL,seq INTEGER NOT NULL,date INTEGER NOT NULL,PRIMARY KEY(account,channel));"
            "CREATE TABLE outbox(account INTEGER NOT NULL,random_id INTEGER NOT NULL,peer_kind INTEGER NOT NULL,"
            "peer INTEGER NOT NULL,state INTEGER NOT NULL,server_id INTEGER NOT NULL,error INTEGER NOT NULL,"
            "request BLOB NOT NULL,PRIMARY KEY(account,random_id));"
            "CREATE INDEX outbox_pending ON outbox(account,state,random_id);"
            "PRAGMA user_version=1; COMMIT");
        if (status != EXTERIA_OK) goto fail;
    }
    if (version < 2) {
        status = run(s, "BEGIN IMMEDIATE; CREATE TABLE journal(id INTEGER PRIMARY KEY AUTOINCREMENT,"
                        "account INTEGER NOT NULL,data BLOB NOT NULL);"
                        "CREATE INDEX journal_account ON journal(account,id); PRAGMA user_version=2; COMMIT");
        if (status != EXTERIA_OK) goto fail;
    }
    *out = s;
    return EXTERIA_OK;
fail:
    sqlite3_finalize(q);
    if (s->db) sqlite3_close(s->db);
    free(s);
    return status;
}

exteria_status exteria_store_close(exteria_store *s) {
    exteria_status status;
    if (!s) return EXTERIA_E_ARG;
    if (s->transaction) {
        status = exteria_store_rollback(s);
        if (status != EXTERIA_OK) return status;
    }
    status = sql_status(sqlite3_close(s->db));
    if (status == EXTERIA_OK) free(s);
    return status;
}

exteria_status exteria_store_begin(exteria_store *s) {
    exteria_status status;
    if (!s || s->transaction) return EXTERIA_E_STATE;
    status = run(s, "BEGIN IMMEDIATE");
    if (status == EXTERIA_OK) s->transaction = 1;
    return status;
}

exteria_status exteria_store_commit(exteria_store *s) {
    exteria_status status;
    if (!s || !s->transaction) return EXTERIA_E_STATE;
    status = run(s, "COMMIT");
    if (status == EXTERIA_OK) s->transaction = 0;
    return status;
}

exteria_status exteria_store_rollback(exteria_store *s) {
    exteria_status status;
    if (!s || !s->transaction) return EXTERIA_E_STATE;
    status = run(s, "ROLLBACK");
    if (status == EXTERIA_OK) s->transaction = 0;
    return status;
}

exteria_status exteria_store_cursor_get(exteria_store *s, int64_t channel_id, exteria_cursor *out) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!s || channel_id < 0) return EXTERIA_E_ARG;
    status = prepare(s, "SELECT pts,qts,seq,date FROM cursors WHERE account=? AND channel=?", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, channel_id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    if (rc == SQLITE_ROW) {
        out->pts = sqlite3_column_int(q, 0);
        out->qts = sqlite3_column_int(q, 1);
        out->seq = sqlite3_column_int(q, 2);
        out->date = sqlite3_column_int(q, 3);
    }
    return finish(q, rc == SQLITE_DONE ? EXTERIA_E_NOTFOUND : sql_status(rc));
}

exteria_status exteria_store_cursor_put(exteria_store *s, int64_t channel_id, const exteria_cursor *v) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s || !s->transaction || !v || channel_id < 0 || v->pts < 0 || v->qts < 0 || v->seq < 0 || v->date < 0)
        return EXTERIA_E_ARG;
    status = prepare(s, "INSERT OR REPLACE INTO cursors VALUES(?,?,?,?,?,?)", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, channel_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, v->pts);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 4, v->qts);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 5, v->seq);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 6, v->date);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    return finish(q, sql_status(rc));
}

exteria_status exteria_store_put(exteria_store *s, exteria_record_kind kind, exteria_peer peer,
                                int64_t id, const exteria_tl_value *value) {
    sqlite3_stmt *q;
    exteria_writer w;
    exteria_status status;
    if (!valid_key(s, kind, peer) || !value) return EXTERIA_E_ARG;
    exteria_writer_init(&w, RECORD_MAX);
    status = exteria_tl_encode(value, &w, NULL);
    if (status != EXTERIA_OK) goto done;
    status = prepare(s, "INSERT OR REPLACE INTO records VALUES(?,?,?,?,?,?)", &q);
    if (status != EXTERIA_OK) goto done;
    status = bind_key(q, s, kind, peer, id);
    if (status == EXTERIA_OK) status = sql_status(sqlite3_bind_blob(q, 6, w.data, (int)w.len, SQLITE_TRANSIENT));
    if (status == EXTERIA_OK) status = sql_status(sqlite3_step(q));
    status = finish(q, status);
    if (status == EXTERIA_OK) note_write(s, kind, peer);
done:
    exteria_writer_free(&w);
    return status;
}

static exteria_status decode_column(sqlite3_stmt *q, int column, exteria_arena *a, exteria_tl_value **out) {
    int len = sqlite3_column_bytes(q, column);
    if (len < 4 || (unsigned)len > RECORD_MAX) return EXTERIA_E_STORAGE;
    return exteria_tl_decode_all(a, NULL, EXTERIA_TL_REF_ANY, sqlite3_column_blob(q, column), (size_t)len, out);
}

exteria_status exteria_store_get(exteria_store *s, exteria_record_kind kind, exteria_peer peer,
                                int64_t id, exteria_arena *arena, exteria_tl_value **out) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!out) return EXTERIA_E_ARG;
    *out = NULL;
    if (!valid_key(s, kind, peer) || !arena) return EXTERIA_E_ARG;
    status = prepare(s, "SELECT data FROM records WHERE account=? AND kind=? AND peer_kind=? AND peer=? AND id=?", &q);
    if (status != EXTERIA_OK) return status;
    status = bind_key(q, s, kind, peer, id);
    if (status == EXTERIA_OK) {
        rc = sqlite3_step(q);
        status = rc == SQLITE_ROW ? decode_column(q, 0, arena, out) :
                 rc == SQLITE_DONE ? EXTERIA_E_NOTFOUND : sql_status(rc);
    }
    return finish(q, status);
}

exteria_status exteria_store_delete(exteria_store *s, exteria_record_kind kind, exteria_peer peer, int64_t id) {
    sqlite3_stmt *q;
    exteria_status status;
    if (!valid_key(s, kind, peer)) return EXTERIA_E_ARG;
    status = prepare(s, "DELETE FROM records WHERE account=? AND kind=? AND peer_kind=? AND peer=? AND id=?", &q);
    if (status != EXTERIA_OK) return status;
    status = bind_key(q, s, kind, peer, id);
    if (status == EXTERIA_OK) status = sql_status(sqlite3_step(q));
    status = finish(q, status);
    if (status == EXTERIA_OK) note_write(s, kind, peer);
    return status;
}

exteria_status exteria_store_page(exteria_store *s, exteria_record_kind kind, exteria_peer peer,
                                 int64_t before_id, uint32_t limit, exteria_record_visit visit, void *ctx) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!valid_key(s, kind, peer) || !visit || limit == 0 || limit > PAGE_MAX) return EXTERIA_E_ARG;
    status = prepare(s, "SELECT id,data FROM records WHERE account=? AND kind=? AND peer_kind=? AND peer=? "
                        "AND id<? ORDER BY id DESC LIMIT ?", &q);
    if (status != EXTERIA_OK) return status;
    status = bind_key(q, s, kind, peer, before_id);
    if (status == EXTERIA_OK) status = sql_status(sqlite3_bind_int(q, 6, (int)limit));
    while (status == EXTERIA_OK && (rc = sqlite3_step(q)) == SQLITE_ROW) {
        exteria_arena a;
        exteria_tl_value *v = NULL;
        exteria_arena_init(&a, 8u * RECORD_MAX);
        status = decode_column(q, 1, &a, &v);
        if (status == EXTERIA_OK) status = visit(ctx, sqlite3_column_int64(q, 0), v);
        exteria_arena_free(&a);
    }
    if (status == EXTERIA_OK) status = sql_status(rc);
    return finish(q, status);
}

exteria_status exteria_store_outbox_add(exteria_store *s, exteria_peer peer, const exteria_tl_value *request) {
    sqlite3_stmt *q;
    exteria_writer w;
    exteria_status status;
    int64_t random_id;
    exteria_peer target;
    int rc;
    if (!s || !request || (exteria_tl_id(request) != EXTERIA_TL_ID_messages_sendMessage &&
        exteria_tl_id(request) != EXTERIA_TL_ID_messages_sendMedia)) return EXTERIA_E_ARG;
    if (exteria_tl_get_i64(request, "random_id", &random_id) != EXTERIA_OK || random_id == 0 ||
        exteria_peer_from_tl(exteria_tl_get(request, "peer"), &target) != EXTERIA_OK ||
        peer.kind != target.kind || peer.id != target.id) return EXTERIA_E_ARG;
    exteria_writer_init(&w, RECORD_MAX);
    status = exteria_tl_encode(request, &w, NULL);
    if (status != EXTERIA_OK) goto done;
    /* a reused random_id must retain the original request, replace would send different text after a crash */
    status = prepare(s, "INSERT INTO outbox VALUES(?,?,?,?,0,0,0,?)", &q);
    if (status != EXTERIA_OK) goto done;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, random_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, peer.kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, peer.id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_blob(q, 5, w.data, (int)w.len, SQLITE_TRANSIENT);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
done:
    exteria_writer_free(&w);
    return status;
}

exteria_status exteria_store_outbox_next(exteria_store *s, exteria_arena *arena, exteria_outbox_item *out) {
    sqlite3_stmt *q;
    exteria_status status;
    exteria_tl_value *v = NULL;
    int rc;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!s || !arena) return EXTERIA_E_ARG;
    status = prepare(s, "SELECT random_id,peer_kind,peer,state,server_id,error,request FROM outbox "
                        "WHERE account=? AND state=0 ORDER BY random_id LIMIT 1", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = rc == SQLITE_ROW ? decode_column(q, 6, arena, &v) :
             rc == SQLITE_DONE ? EXTERIA_E_NOTFOUND : sql_status(rc);
    if (status == EXTERIA_OK) {
        out->random_id = sqlite3_column_int64(q, 0);
        out->peer.kind = sqlite3_column_int(q, 1);
        out->peer.id = sqlite3_column_int64(q, 2);
        out->state = (exteria_outbox_state)sqlite3_column_int(q, 3);
        out->server_id = sqlite3_column_int(q, 4);
        out->error = sqlite3_column_int(q, 5);
        out->request = v;
    }
    return finish(q, status);
}

exteria_status exteria_store_outbox_set(exteria_store *s, int64_t random_id, exteria_outbox_state state,
                                       int32_t server_id, int32_t error) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s || !random_id || state < EXTERIA_OUTBOX_PENDING || state > EXTERIA_OUTBOX_FAILED ||
        server_id < 0 || (state == EXTERIA_OUTBOX_SENT && !server_id)) return EXTERIA_E_ARG;
    status = prepare(s, "UPDATE outbox SET state=?,server_id=?,error=? WHERE account=? AND random_id=? "
                        "AND (state<>2 OR ?=2)", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int(q, 1, (int)state);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, server_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, error);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 5, random_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 6, (int)state);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = sql_status(rc);
    if (status == EXTERIA_OK && sqlite3_changes(s->db) == 0) status = EXTERIA_E_NOTFOUND;
    return finish(q, status);
}

exteria_status exteria_store_outbox_recover(exteria_store *s) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s) return EXTERIA_E_ARG;
    status = prepare(s, "UPDATE outbox SET state=0 WHERE account=? AND state=1", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    return finish(q, sql_status(rc));
}

exteria_status exteria_peer_from_tl(const exteria_tl_value *v, exteria_peer *out) {
    uint32_t id;
    const char *field;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!v) return EXTERIA_E_ARG;
    id = exteria_tl_id(v);
    if (id == EXTERIA_TL_ID_peerUser || id == EXTERIA_TL_ID_inputPeerUser) { out->kind = 1; field = "user_id"; }
    else if (id == EXTERIA_TL_ID_peerChat || id == EXTERIA_TL_ID_inputPeerChat) { out->kind = 2; field = "chat_id"; }
    else if (id == EXTERIA_TL_ID_peerChannel || id == EXTERIA_TL_ID_inputPeerChannel) { out->kind = 3; field = "channel_id"; }
    else return EXTERIA_E_UNSUPPORTED;
    if (exteria_tl_get_i64(v, field, &out->id) != EXTERIA_OK || out->id <= 0) {
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

/* the entries the journal keeps for an account */
#define JOURNAL_MAX 8192

exteria_status exteria_store_journal_add(exteria_store *s, const exteria_tl_value *value) {
    sqlite3_stmt *q;
    exteria_writer w;
    exteria_status status;
    int rc, full;
    if (!s || !s->transaction || !value) return EXTERIA_E_STATE;
    status = prepare(s, "SELECT COUNT(*) FROM journal WHERE account=?", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    full = rc == SQLITE_ROW && sqlite3_column_int(q, 0) >= JOURNAL_MAX;
    status = rc == SQLITE_ROW ? EXTERIA_OK : sql_status(rc);
    status = finish(q, status);
    if (status != EXTERIA_OK) return status;
    if (full) {
        /* no feature acknowledges the journal yet, so a full one makes room by dropping its oldest entries; refusing instead stopped every later update of
           the account, once a few thousand of them had come */
        status = prepare(s, "DELETE FROM journal WHERE account=?1 AND id IN (SELECT id FROM journal WHERE account=?1 ORDER BY id LIMIT ?2)", &q);
        if (status != EXTERIA_OK) return status;
        rc = sqlite3_bind_int64(q, 1, s->account);
        if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, JOURNAL_MAX / 4);
        if (rc == SQLITE_OK) rc = sqlite3_step(q);
        status = finish(q, sql_status(rc));
        if (status != EXTERIA_OK) return status;
    }
    exteria_writer_init(&w, RECORD_MAX);
    status = exteria_tl_encode(value, &w, NULL);
    if (status != EXTERIA_OK) goto done;
    status = prepare(s, "INSERT INTO journal(account,data) VALUES(?,?)", &q);
    if (status != EXTERIA_OK) goto done;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_blob(q, 2, w.data, (int)w.len, SQLITE_TRANSIENT);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
done:
    exteria_writer_free(&w);
    return status;
}

exteria_status exteria_store_journal_page(exteria_store *s, int64_t after_id, uint32_t limit,
                                         exteria_record_visit visit, void *ctx) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s || !visit || after_id < 0 || !limit || limit > PAGE_MAX) return EXTERIA_E_ARG;
    status = prepare(s, "SELECT id,data FROM journal WHERE account=? AND id>? ORDER BY id LIMIT ?", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, after_id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, (int)limit);
    status = sql_status(rc);
    while (status == EXTERIA_OK && (rc = sqlite3_step(q)) == SQLITE_ROW) {
        exteria_arena arena;
        exteria_tl_value *v = NULL;
        exteria_arena_init(&arena, 8u * RECORD_MAX);
        status = decode_column(q, 1, &arena, &v);
        if (status == EXTERIA_OK) status = visit(ctx, sqlite3_column_int64(q, 0), v);
        exteria_arena_free(&arena);
    }
    if (status == EXTERIA_OK) status = sql_status(rc);
    return finish(q, status);
}

exteria_status exteria_store_journal_ack(exteria_store *s, int64_t through_id) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s || !s->transaction || through_id < 0) return EXTERIA_E_STATE;
    status = prepare(s, "DELETE FROM journal WHERE account=? AND id<=?", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 2, through_id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    return finish(q, sql_status(rc));
}

exteria_status exteria_store_delete_common_message(exteria_store *s, int32_t id) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s || id <= 0) return EXTERIA_E_ARG;
    status = prepare(s, "DELETE FROM records WHERE account=? AND kind=4 AND peer_kind IN (1,2) AND id=?", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
    /* the sweep reaches every chat of the account, so it moves every version */
    if (status == EXTERIA_OK) s->sweep_version++;
    return status;
}

exteria_status exteria_store_move(exteria_store *s, exteria_record_kind from, exteria_record_kind to, exteria_peer peer, int64_t id) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc, found;
    if (!valid_key(s, from, peer) || !valid_key(s, to, peer)) return EXTERIA_E_ARG;
    status = prepare(s, "INSERT OR REPLACE INTO records(account,kind,peer_kind,peer,id,data) "
                        "SELECT account,?6,peer_kind,peer,id,data FROM records WHERE account=?1 AND kind=?2 AND peer_kind=?3 AND peer=?4 AND id=?5", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)from);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 3, peer.kind);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 4, peer.id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int64(q, 5, id);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 6, (int)to);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    found = sqlite3_changes(s->db) > 0;
    status = finish(q, sql_status(rc));
    if (status != EXTERIA_OK) return status;
    if (!found) return EXTERIA_E_NOTFOUND;
    status = exteria_store_delete(s, from, peer, id);
    if (status == EXTERIA_OK) note_write(s, to, peer);
    return status;
}

exteria_status exteria_store_find_common_message(exteria_store *s, int32_t id, exteria_peer *peer) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s || !peer || id <= 0) return EXTERIA_E_ARG;
    status = prepare(s, "SELECT peer_kind,peer FROM records WHERE account=? AND kind=4 AND peer_kind IN (1,2) AND id=? LIMIT 1", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, id);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    if (rc == SQLITE_ROW) {
        peer->kind = sqlite3_column_int(q, 0);
        peer->id = sqlite3_column_int64(q, 1);
        return finish(q, EXTERIA_OK);
    }
    return finish(q, rc == SQLITE_DONE ? EXTERIA_E_NOTFOUND : sql_status(rc));
}

exteria_status exteria_store_count(exteria_store *s, exteria_record_kind kind, int64_t *count) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (count) *count = 0;
    if (!s || !count || kind < EXTERIA_RECORD_USER || kind > EXTERIA_RECORD_MESSAGE_EDIT) return EXTERIA_E_ARG;
    status = prepare(s, "SELECT COUNT(*) FROM records WHERE account=? AND kind=?", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)kind);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    if (rc == SQLITE_ROW) *count = sqlite3_column_int64(q, 0);
    return finish(q, rc == SQLITE_ROW ? EXTERIA_OK : sql_status(rc));
}

exteria_status exteria_store_clear(exteria_store *s, exteria_record_kind kind) {
    sqlite3_stmt *q;
    exteria_status status;
    int rc;
    if (!s || kind < EXTERIA_RECORD_USER || kind > EXTERIA_RECORD_MESSAGE_EDIT) return EXTERIA_E_ARG;
    status = prepare(s, "DELETE FROM records WHERE account=? AND kind=?", &q);
    if (status != EXTERIA_OK) return status;
    rc = sqlite3_bind_int64(q, 1, s->account);
    if (rc == SQLITE_OK) rc = sqlite3_bind_int(q, 2, (int)kind);
    if (rc == SQLITE_OK) rc = sqlite3_step(q);
    status = finish(q, sql_status(rc));
    if (status == EXTERIA_OK) s->sweep_version++;
    return status;
}
