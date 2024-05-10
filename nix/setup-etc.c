#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>

#define MAX_PATH 4096
#define STATIC_PATH "/etc/static"
#define CLEAN_FILE "/etc/.clean"
#define NIXOS_TAG "/etc/NIXOS"

int atomicSymlink(const char *source, const char *target) {
    char tmp[MAX_PATH];
    snprintf(tmp, MAX_PATH, "%s.tmp", target);
    unlink(tmp);
    if (symlink(source, tmp) != 0) {
        return 0;
    }
    if (rename(tmp, target) != 0) {
        unlink(tmp);
        return 0;
    }
    return 1;
}

int isStatic(const char *path) {
    char buf[MAX_PATH];
    struct stat st;
    if (lstat(path, &st) != 0) {
        return 0;
    }
    if (S_ISLNK(st.st_mode)) {
        ssize_t len = readlink(path, buf, MAX_PATH);
        if (len < 0 || len >= MAX_PATH) {
            return 0;
        }
        buf[len] = '\0';
        return strncmp(buf, STATIC_PATH "/", strlen(STATIC_PATH) + 1) == 0;
    }
    if (S_ISDIR(st.st_mode)) {
        DIR *dir = opendir(path);
        if (dir == NULL) {
            return 0;
        }
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
                continue;
            }
            char subpath[MAX_PATH];
            snprintf(subpath, MAX_PATH, "%s/%s", path, entry->d_name);
            if (!isStatic(subpath)) {
                closedir(dir);
                return 0;
            }
        }
        closedir(dir);
        return 1;
    }
    return 0;
}

void cleanup(const char *path) {
    if (strcmp(path, "/etc/nixos") == 0) {
        return;
    }
    struct stat st;
    if (lstat(path, &st) != 0) {
        return;
    }
    if (S_ISLNK(st.st_mode)) {
        char buf[MAX_PATH];
        ssize_t len = readlink(path, buf, MAX_PATH);
        if (len < 0 || len >= MAX_PATH) {
            return;
        }
        buf[len] = '\0';
        if (strncmp(buf, STATIC_PATH "/", strlen(STATIC_PATH) + 1) == 0) {
            char target[MAX_PATH];
            snprintf(target, MAX_PATH, "%s/%s", STATIC_PATH, path + strlen("/etc/"));
            if (lstat(target, &st) != 0 || !S_ISLNK(st.st_mode)) {
                printf("removing obsolete symlink '%s'...\n", path);
                unlink(path);
            }
        }
    }
}

void createLink(const char *path, const char *etc_path) {
    char fn[MAX_PATH];
    snprintf(fn, MAX_PATH, "%s", path + strlen(etc_path) + 1);

    if (strcmp(fn, "resolv.conf") == 0 && getenv("IN_NIXOS_ENTER") != NULL) {
        return;
    }

    char target[MAX_PATH];
    snprintf(target, MAX_PATH, "/etc/%s", fn);
    char *dir = strdup(target);
    char *last_slash = strrchr(dir, '/');
    *last_slash = '\0';
    mkdir(dir, 0755);
    free(dir);

    char mode_path[MAX_PATH];
    snprintf(mode_path, MAX_PATH, "%s.mode", path);
    FILE *mode_file = fopen(mode_path, "r");
    if (mode_file != NULL) {
        char mode[16];
        if (fgets(mode, sizeof(mode), mode_file) != NULL) {
            mode[strcspn(mode, "\n")] = '\0';
            if (strcmp(mode, "direct-symlink") == 0) {
                char source[MAX_PATH];
                snprintf(source, MAX_PATH, "%s/%s", STATIC_PATH, fn);
                char link_target[MAX_PATH];
                ssize_t len = readlink(source, link_target, MAX_PATH);
                if (len < 0 || len >= MAX_PATH) {
                    fprintf(stderr, "could not read symlink %s\n", source);
                } else {
                    link_target[len] = '\0';
                    if (!atomicSymlink(link_target, target)) {
                        fprintf(stderr, "could not create symlink %s\n", target);
                    }
                }
            } else {
                char uid_path[MAX_PATH];
                snprintf(uid_path, MAX_PATH, "%s.uid", path);
                FILE *uid_file = fopen(uid_path, "r");
                if (uid_file == NULL) {
                    fprintf(stderr, "could not open %s\n", uid_path);
                    fclose(mode_file);
                    return;
                }
                char uid_str[32];
                if (fgets(uid_str, sizeof(uid_str), uid_file) == NULL) {
                    fprintf(stderr, "could not read %s\n", uid_path);
                    fclose(uid_file);
                    fclose(mode_file);
                    return;
                }
                uid_str[strcspn(uid_str, "\n")] = '\0';
                uid_t uid = uid_str[0] == '+' ? atoi(uid_str + 1) : getpwnam(uid_str) != NULL ? getpwnam(uid_str)->pw_uid : 0;
                fclose(uid_file);

                char gid_path[MAX_PATH];
                snprintf(gid_path, MAX_PATH, "%s.gid", path);
                FILE *gid_file = fopen(gid_path, "r");
                if (gid_file == NULL) {
                    fprintf(stderr, "could not open %s\n", gid_path);
                    fclose(mode_file);
                    return;
                }
                char gid_str[32];
                if (fgets(gid_str, sizeof(gid_str), gid_file) == NULL) {
                    fprintf(stderr, "could not read %s\n", gid_path);
                    fclose(gid_file);
                    fclose(mode_file);
                    return;
                }
                gid_str[strcspn(gid_str, "\n")] = '\0';
                gid_t gid = gid_str[0] == '+' ? atoi(gid_str + 1) : getgrnam(gid_str) != NULL ? getgrnam(gid_str)->gr_gid : 0;
                fclose(gid_file);

                char tmp_path[MAX_PATH];
                snprintf(tmp_path, MAX_PATH, "%s.tmp", target);
                char source[MAX_PATH];
                snprintf(source, MAX_PATH, "%s/%s", STATIC_PATH, fn);
                FILE *source_file = fopen(source, "rb");
                if (source_file == NULL) {
                    fprintf(stderr, "could not open %s\n", source);
                    fclose(mode_file);
                    return;
                }
                FILE *tmp_file = fopen(tmp_path, "wb");
                if (tmp_file == NULL) {
                    fprintf(stderr, "could not create %s\n", tmp_path);
                    fclose(source_file);
                    fclose(mode_file);
                    return;
                }
                char buf[4096];
                size_t n;
                while ((n = fread(buf, 1, sizeof(buf), source_file)) > 0) {
                    fwrite(buf, 1, n, tmp_file);
                }
                fclose(source_file);
                fclose(tmp_file);
                chmod(tmp_path, strtol(mode, NULL, 8));
                chown(tmp_path, uid, gid);
                if (rename(tmp_path, target) != 0) {
                    fprintf(stderr, "could not create target %s\n", target);
                    unlink(tmp_path);
                }
            }
            FILE *clean_file = fopen(CLEAN_FILE, "a");
            if (clean_file != NULL) {
                fprintf(clean_file, "%s\n", fn);
                fclose(clean_file);
            }
        }
        fclose(mode_file);
    } else {
        char source[MAX_PATH];
        snprintf(source, MAX_PATH, "%s/%s", STATIC_PATH, fn);
        if (!atomicSymlink(source, target)) {
            fprintf(stderr, "could not create symlink %s\n", target);
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <etc-path>\n", argv[0]);
        return 1;
    }

    char *etc_path = argv[1];
    char static_path[MAX_PATH];
    snprintf(static_path, MAX_PATH, "%s", STATIC_PATH);

    if (!atomicSymlink(etc_path, static_path)) {
        fprintf(stderr, "Failed to create symlink %s\n", static_path);
        return 1;
    }

    DIR *dir = opendir("/etc");
    if (dir == NULL) {
        fprintf(stderr, "could not open /etc\n");
        return 1;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char path[MAX_PATH];
        snprintf(path, MAX_PATH, "/etc/%s", entry->d_name);
        cleanup(path);
    }
    closedir(dir);

    char *old_copied[4096];
    int old_copied_count = 0;
    FILE *clean_file = fopen(CLEAN_FILE, "r");
    if (clean_file != NULL) {
        char line[MAX_PATH];
        while (fgets(line, MAX_PATH, clean_file) != NULL) {
            line[strcspn(line, "\n")] = '\0';
            old_copied[old_copied_count++] = strdup(line);
        }
        fclose(clean_file);
    }

    dir = opendir(etc_path);
    if (dir == NULL) {
        fprintf(stderr, "could not open %s\n", etc_path);
        return 1;
    }

    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char path[MAX_PATH];
        snprintf(path, MAX_PATH, "%s/%s", etc_path, entry->d_name);
        createLink(path, etc_path);
    }
    closedir(dir);

    clean_file = fopen(CLEAN_FILE, "w");
    if (clean_file != NULL) {
        for (int i = 0; i < old_copied_count; i++) {
            char path[MAX_PATH];
            snprintf(path, MAX_PATH, "/etc/%s", old_copied[i]);
            struct stat st;
            if (lstat(path, &st) == 0) {
                fprintf(clean_file, "%s\n", old_copied[i]);
            } else {
                printf("removing obsolete file '%s'...\n", path);
            }
            free(old_copied[i]);
        }
        fclose(clean_file);
    }

    FILE *tag_file = fopen(NIXOS_TAG, "a");
    if (tag_file != NULL) {
        fclose(tag_file);
    }

    return 0;
}
