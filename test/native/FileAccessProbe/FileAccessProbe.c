#include "FileAccessProbe.h"
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <sys/stat.h>

// Test-only dyld interposition observes Foundation's metadata lookups. The
// calibration test proves the hooks are active before testing DownloadQuery.
static atomic_bool observing = false;
static atomic_int lookups = 0;
static const char prefix[] = "/icloud-storage-tests/no-filesystem-lookup/";

void icloud_file_probe_start(void) {
  atomic_store(&lookups, 0);
  atomic_store(&observing, true);
}

int icloud_file_probe_stop(void) {
  atomic_store(&observing, false);
  return atomic_load(&lookups);
}

static void observe(const char *path) {
  if (atomic_load(&observing) &&
      strncmp(path, prefix, sizeof(prefix) - 1) == 0) {
    atomic_fetch_add(&lookups, 1);
  }
}

static int observed_lstat(const char *path, struct stat *buffer) {
  observe(path);
  return lstat(path, buffer);
}

static int observed_stat(const char *path, struct stat *buffer) {
  observe(path);
  return stat(path, buffer);
}

#define INTERPOSE(replacement, original) \
  __attribute__((used)) static const struct { \
    const void *replacement; \
    const void *original; \
  } interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
    (const void *)&replacement, (const void *)&original \
  };

INTERPOSE(observed_lstat, lstat)
INTERPOSE(observed_stat, stat)
