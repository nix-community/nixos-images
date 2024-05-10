
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <json-c/json.h>

// Function to allocate a free UID/GID
int allocId(int *used, int *prevUsed, int min, int max, int up) {
    int id = up ? min : max;
    while (id >= min && id <= max) {
        if (!used[id] && !prevUsed[id]) {
            used[id] = 1;
            return id;
        }
        used[id] = 1;
        if (up) {
            id++;
        } else {
            id--;
        }
    }
    printf("Out of free UIDs or GIDs\n");
    exit(1);
}

// Function to allocate a free GID
int allocGid(char *name) {
    int prevGid = getgrnam(name)->gr_gid;
    if (prevGid && !used[prevGid]) {
        printf("Reviving group '%s' with GID %d\n", name, prevGid);
        used[prevGid] = 1;
        return prevGid;
    }
    return allocId(used, prevUsed, 400, 999, 0);
}

// Function to allocate a free UID
int allocUid(char *name, int isSystemUser) {
    int min = isSystemUser ? 400 : 1000;
    int max = isSystemUser ? 999 : 29999;
    int up = isSystemUser ? 0 : 1;
    int prevUid = getpwnam(name)->pw_uid;
    if (prevUid >= min && prevUid <= max && !used[prevUid]) {
        printf("Reviving user '%s' with UID %d\n", name, prevUid);
        used[prevUid] = 1;
        return prevUid;
    }
    return allocId(used, prevUsed, min, max, up);
}

int main() {
    // Initialize used and prevUsed arrays
    int *used = (int *)malloc(sizeof(int) * 10000);
    int *prevUsed = (int *)malloc(sizeof(int) * 10000);
    for (int i = 0; i < 10000; i++) {
        used[i] = 0;
        prevUsed[i] = 0;
    }

    // Read the declared users/groups
    // ...

    // Allocate UIDs/GIDs
    for (int i = 0; i < numUsers; i++) {
        users[i]->uid = allocUid(users[i]->name, users[i]->isSystemUser);
    }
    for (int i = 0; i < numGroups; i++) {
        groups[i]->gid = allocGid(groups[i]->name);
    }

    // Update system files
    // ...

    return 0;
}
