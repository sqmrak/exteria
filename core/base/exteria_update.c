#include "exteria_update.h"

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include "exteria_zip.h"

#define PATH_CAP 1024u
#define STAGE_NAME ".update"
#define STORAGE_MARGIN (1024u * 1024u)
#define TREE_DEPTH 12

typedef struct update_state {
    exteria_update_progress progress;
    void *ctx;
    exteria_update_phase phase;
    uint64_t base;      /* bytes of the files finished before the one being read */
    uint64_t total;
} update_state;

static exteria_status join(char *out, const char *a, const char *b) {
    int n = snprintf(out, PATH_CAP, "%s/%s", a, b);
    return n > 0 && (size_t)n < PATH_CAP ? EXTERIA_OK : EXTERIA_E_LIMIT;
}

/* removes a folder this module made; links are unlinked and never followed, and the walk is bounded */
static exteria_status remove_tree(const char *path, int depth) {
    DIR *dir;
    struct dirent *entry;
    exteria_status status = EXTERIA_OK;
    struct stat st;
    if (lstat(path, &st) != 0) return errno == ENOENT ? EXTERIA_OK : EXTERIA_E_IO;
    if (!S_ISDIR(st.st_mode)) return unlink(path) == 0 ? EXTERIA_OK : EXTERIA_E_IO;
    if (depth > TREE_DEPTH) return EXTERIA_E_LIMIT;
    dir = opendir(path);
    if (!dir) return EXTERIA_E_IO;
    while ((entry = readdir(dir)) != NULL) {
        char child[PATH_CAP];
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        if (join(child, path, entry->d_name) != EXTERIA_OK) {
            status = EXTERIA_E_LIMIT;
            continue;
        }
        if (remove_tree(child, depth + 1) != EXTERIA_OK) status = EXTERIA_E_IO;
    }
    closedir(dir);
    if (rmdir(path) != 0) status = EXTERIA_E_IO;
    return status;
}

/* makes the folders above rel under root; every part of rel was checked by the zip reader, so none is "." or "..", and an existing part must be a real folder */
static exteria_status make_parents(const char *root, const char *rel) {
    char path[PATH_CAP];
    const char *slash = rel;
    while ((slash = strchr(slash, '/')) != NULL) {
        char part[EXTERIA_ZIP_NAME_MAX];
        size_t len = (size_t)(slash - rel);
        struct stat st;
        memcpy(part, rel, len);
        part[len] = 0;
        if (join(path, root, part) != EXTERIA_OK) return EXTERIA_E_LIMIT;
        if (lstat(path, &st) == 0) {
            if (!S_ISDIR(st.st_mode)) return EXTERIA_E_STATE;
        } else if (errno != ENOENT || mkdir(path, 0755) != 0) {
            return EXTERIA_E_IO;
        }
        ++slash;
    }
    return EXTERIA_OK;
}

/* the path of an entry inside the app folder of the ipa, or NULL for a folder entry above it; a file elsewhere is an ipa of another shape */
static exteria_status app_relative(const exteria_zip_entry *e, const char *prefix, size_t prefix_len, const char **rel) {
    *rel = NULL;
    if (!strncmp(e->name, prefix, prefix_len)) {
        if (e->name[prefix_len] == 0) return EXTERIA_OK;
        *rel = e->name + prefix_len;
        /* the staging folder lives in the bundle, so no file of the ipa may take its name */
        if (!strncmp(*rel, STAGE_NAME, sizeof(STAGE_NAME) - 1) && ((*rel)[sizeof(STAGE_NAME) - 1] == 0 || (*rel)[sizeof(STAGE_NAME) - 1] == '/')) {
            *rel = NULL;
            return EXTERIA_E_MALFORMED;
        }
        return EXTERIA_OK;
    }
    if (e->is_dir && (!strcmp(e->name, "Payload/") || !strncmp(e->name, prefix, strlen(e->name)))) return EXTERIA_OK;
    return EXTERIA_E_UNSUPPORTED;
}

static exteria_status report(update_state *s, uint64_t done) {
    return s->progress ? s->progress(s->ctx, s->phase, s->base + done, s->total) : EXTERIA_OK;
}

static exteria_status on_written(void *ctx, uint32_t written) {
    return report((update_state *)ctx, written);
}

exteria_status exteria_update_apply(const char *ipa_path, const char *bundle_path, const char *app_name, const char *executable,
                                    exteria_update_progress progress, void *ctx) {
    exteria_zip *zip = NULL;
    size_t count, i, changed = 0, *plan = NULL, committed = 0;
    char prefix[EXTERIA_ZIP_NAME_MAX], stage[PATH_CAP], from[PATH_CAP], to[PATH_CAP];
    size_t prefix_len;
    update_state state;
    uint64_t changed_bytes = 0, all_bytes = 0;
    struct statvfs vfs;
    int staged_dir = 0, have_exec = 0, have_plist = 0;
    exteria_status status;
    if (!ipa_path || !bundle_path || !app_name || !executable || !app_name[0] || strchr(app_name, '/') || strchr(executable, '/')) return EXTERIA_E_ARG;
    if (access(bundle_path, W_OK | X_OK) != 0) return EXTERIA_E_STATE;
    prefix_len = (size_t)snprintf(prefix, sizeof(prefix), "Payload/%s/", app_name);
    if (prefix_len >= sizeof(prefix)) return EXTERIA_E_ARG;
    status = join(stage, bundle_path, STAGE_NAME);
    if (status != EXTERIA_OK) return status;
    status = exteria_zip_open(ipa_path, &zip);
    if (status != EXTERIA_OK) return status;
    count = exteria_zip_count(zip);
    plan = (size_t *)calloc(count, sizeof(*plan));
    if (!plan) {
        exteria_zip_close(zip);
        return EXTERIA_E_NOMEM;
    }
    memset(&state, 0, sizeof(state));
    state.progress = progress;
    state.ctx = ctx;

    /* the ipa is read once to learn its shape and its size, then the installed files are compared against it */
    for (i = 0; i < count; ++i) {
        const exteria_zip_entry *e = exteria_zip_entry_at(zip, i);
        const char *rel;
        status = app_relative(e, prefix, prefix_len, &rel);
        if (status != EXTERIA_OK) goto done;
        if (!rel || e->is_dir) continue;
        if (!strcmp(rel, executable)) have_exec = 1;
        if (!strcmp(rel, "Info.plist")) have_plist = 1;
        all_bytes += e->size;
    }
    if (!have_exec || !have_plist) {
        status = EXTERIA_E_MALFORMED;
        goto done;
    }
    state.phase = EXTERIA_UPDATE_COMPARE;
    state.total = all_bytes;
    for (i = 0; i < count; ++i) {
        const exteria_zip_entry *e = exteria_zip_entry_at(zip, i);
        const char *rel;
        int same = 0;
        (void)app_relative(e, prefix, prefix_len, &rel);
        if (!rel || e->is_dir) continue;
        status = join(to, bundle_path, rel);
        if (status != EXTERIA_OK) goto done;
        status = exteria_zip_entry_matches(e, to, &same);
        if (status != EXTERIA_OK) goto done;
        state.base += e->size;
        status = report(&state, 0);
        if (status != EXTERIA_OK) goto done;
        if (!same) {
            plan[changed++] = i;
            changed_bytes += e->size;
        }
    }

    if (statvfs(bundle_path, &vfs) != 0) {
        status = EXTERIA_E_IO;
        goto done;
    }
    if ((uint64_t)vfs.f_bavail * vfs.f_frsize < changed_bytes + STORAGE_MARGIN) {
        status = EXTERIA_E_STORAGE;
        goto done;
    }

    /* a stage left by an update that was cut short is not trusted */
    status = remove_tree(stage, 0);
    if (status != EXTERIA_OK) goto done;
    if (mkdir(stage, 0755) != 0) {
        status = EXTERIA_E_IO;
        goto done;
    }
    staged_dir = 1;
    state.phase = EXTERIA_UPDATE_STAGE;
    state.base = 0;
    state.total = changed_bytes;
    for (i = 0; i < changed; ++i) {
        const exteria_zip_entry *e = exteria_zip_entry_at(zip, plan[i]);
        const char *rel;
        (void)app_relative(e, prefix, prefix_len, &rel);
        status = make_parents(stage, rel);
        if (status == EXTERIA_OK) status = join(to, stage, rel);
        if (status != EXTERIA_OK) goto done;
        status = exteria_zip_extract(zip, e, to, on_written, &state);
        if (status != EXTERIA_OK) goto done;
        state.base += e->size;
    }

    /* the point of no return: from here the files are moved one by one, each rename atomic, and the executable goes last so an
       interruption leaves the old program with some new resources, which the next update completes */
    state.phase = EXTERIA_UPDATE_COMMIT;
    state.base = 0;
    state.total = changed;
    for (i = 0; i < 3; ++i) {
        size_t k;
        for (k = 0; k < changed; ++k) {
            const exteria_zip_entry *e = exteria_zip_entry_at(zip, plan[k]);
            const char *rel;
            int rank;
            (void)app_relative(e, prefix, prefix_len, &rel);
            rank = !strcmp(rel, executable) ? 2 : !strcmp(rel, "Info.plist") ? 1 : 0;
            if (rank != (int)i) continue;
            status = make_parents(bundle_path, rel);
            if (status == EXTERIA_OK) status = join(from, stage, rel);
            if (status == EXTERIA_OK) status = join(to, bundle_path, rel);
            if (status != EXTERIA_OK) goto done;
            if (chmod(from, (e->mode & 0111u) ? 0755 : 0644) != 0 || rename(from, to) != 0) {
                status = EXTERIA_E_IO;
                goto done;
            }
            ++committed;
            if (progress) (void)progress(ctx, EXTERIA_UPDATE_COMMIT, committed, changed);
        }
    }
    status = EXTERIA_OK;
done:
    /* what is left of the stage is empty folders after a success, which the next update removes if this cannot */
    if (staged_dir) (void)remove_tree(stage, 0);
    free(plan);
    exteria_zip_close(zip);
    return status;
}
