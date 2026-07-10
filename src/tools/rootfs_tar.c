#define _XOPEN_SOURCE 700

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define BLOCK_SIZE 512
#define COPY_BUFFER_SIZE 16384

struct string_list {
  char **items;
  size_t count;
  size_t capacity;
};

struct tar_header {
  char name[100];
  char mode[8];
  char uid[8];
  char gid[8];
  char size[12];
  char mtime[12];
  char checksum[8];
  char typeflag;
  char linkname[100];
  char magic[6];
  char version[2];
  char uname[32];
  char gname[32];
  char devmajor[8];
  char devminor[8];
  char prefix[155];
  char padding[12];
};

static void die(const char *message, const char *path) {
  if (path) {
    fprintf(stderr, "%s: %s: %s\n", message, path, strerror(errno));
  } else {
    fprintf(stderr, "%s: %s\n", message, strerror(errno));
  }
  exit(1);
}

static void write_all(int fd, const void *buffer, size_t size) {
  const char *ptr = (const char *)buffer;
  while (size > 0) {
    ssize_t written = write(fd, ptr, size);
    if (written < 0) die("write failed", NULL);
    ptr += written;
    size -= (size_t)written;
  }
}

static void list_push(struct string_list *list, const char *value, size_t len) {
  if (list->count == list->capacity) {
    list->capacity = list->capacity ? list->capacity * 2 : 8;
    char **next = realloc(list->items, list->capacity * sizeof(char *));
    if (!next) die("realloc failed", NULL);
    list->items = next;
  }
  list->items[list->count] = malloc(len + 1);
  if (!list->items[list->count]) die("malloc failed", NULL);
  memcpy(list->items[list->count], value, len);
  list->items[list->count][len] = '\0';
  list->count++;
}

static void list_free(struct string_list *list) {
  for (size_t i = 0; i < list->count; i++) free(list->items[i]);
  free(list->items);
  list->items = NULL;
  list->count = 0;
  list->capacity = 0;
}

static char *read_text_file(const char *path, size_t *size_out) {
  int fd = open(path, O_RDONLY);
  if (fd < 0) die("open failed", path);

  size_t capacity = 4096;
  size_t size = 0;
  char *buffer = malloc(capacity + 1);
  if (!buffer) die("malloc failed", NULL);

  for (;;) {
    if (size == capacity) {
      capacity *= 2;
      char *next = realloc(buffer, capacity + 1);
      if (!next) die("realloc failed", NULL);
      buffer = next;
    }
    ssize_t n = read(fd, buffer + size, capacity - size);
    if (n < 0) die("read failed", path);
    if (n == 0) break;
    size += (size_t)n;
  }
  close(fd);
  buffer[size] = '\0';
  *size_out = size;
  return buffer;
}

static void zero_pad(int fd, size_t size) {
  static const char zeros[BLOCK_SIZE] = {0};
  while (size > 0) {
    size_t chunk = size > BLOCK_SIZE ? BLOCK_SIZE : size;
    write_all(fd, zeros, chunk);
    size -= chunk;
  }
}

static void octal(char *field, size_t width, uint64_t value) {
  snprintf(field, width, "%0*llo", (int)width - 1, (unsigned long long)value);
}

static void split_tar_name(const char *path, char *name, char *prefix) {
  size_t len = strlen(path);
  if (len <= 100) {
    memcpy(name, path, len);
    return;
  }

  const char *slash = path + len;
  while (slash > path) {
    --slash;
    if (*slash != '/') continue;
    size_t prefix_len = (size_t)(slash - path);
    size_t name_len = len - prefix_len - 1;
    if (prefix_len <= 155 && name_len <= 100) {
      memcpy(prefix, path, prefix_len);
      memcpy(name, slash + 1, name_len);
      return;
    }
  }

  fprintf(stderr, "path too long for ustar: %s\n", path);
  exit(1);
}

static void write_header(int out, const char *archive_path, const struct stat *st, char typeflag, const char *linkname) {
  struct tar_header h;
  memset(&h, 0, sizeof(h));
  split_tar_name(archive_path, h.name, h.prefix);
  octal(h.mode, sizeof(h.mode), (uint64_t)(st->st_mode & 07777));
  octal(h.uid, sizeof(h.uid), 0);
  octal(h.gid, sizeof(h.gid), 0);
  octal(h.size, sizeof(h.size), typeflag == '0' ? (uint64_t)st->st_size : 0);
  octal(h.mtime, sizeof(h.mtime), (uint64_t)st->st_mtime);
  memset(h.checksum, ' ', sizeof(h.checksum));
  h.typeflag = typeflag;
  if (linkname) {
    size_t link_len = strlen(linkname);
    if (link_len > sizeof(h.linkname)) {
      fprintf(stderr, "link target too long for ustar: %s\n", linkname);
      exit(1);
    }
    memcpy(h.linkname, linkname, link_len);
  }
  memcpy(h.magic, "ustar", 5);
  memcpy(h.version, "00", 2);
  memcpy(h.uname, "root", 4);
  memcpy(h.gname, "root", 4);

  unsigned int sum = 0;
  const unsigned char *bytes = (const unsigned char *)&h;
  for (size_t i = 0; i < sizeof(h); i++) sum += bytes[i];
  snprintf(h.checksum, sizeof(h.checksum), "%06o", sum);
  h.checksum[6] = '\0';
  h.checksum[7] = ' ';

  write_all(out, &h, sizeof(h));
}

static char *join_path(const char *left, const char *right) {
  size_t left_len = strlen(left);
  size_t right_len = strlen(right);
  int needs_slash = left_len > 0 && left[left_len - 1] != '/';
  char *joined = malloc(left_len + right_len + (needs_slash ? 2 : 1));
  if (!joined) die("malloc failed", NULL);
  memcpy(joined, left, left_len);
  if (needs_slash) joined[left_len++] = '/';
  memcpy(joined + left_len, right, right_len);
  joined[left_len + right_len] = '\0';
  return joined;
}

static int ignored_context_entry(const char *name) {
  return strcmp(name, ".git") == 0 || strcmp(name, ".turbo") == 0 || strcmp(name, ".next") == 0 || strcmp(name, "build") == 0 ||
         strcmp(name, "dist") == 0 || strcmp(name, "coverage") == 0 || strcmp(name, "node_modules") == 0 || name[0] == '.';
}

static void mkdir_p(const char *path) {
  char *copy = strdup(path);
  if (!copy) die("strdup failed", NULL);
  for (char *p = copy + 1; *p; p++) {
    if (*p != '/') continue;
    *p = '\0';
    if (mkdir(copy, 0755) != 0 && errno != EEXIST) die("mkdir failed", copy);
    *p = '/';
  }
  if (mkdir(copy, 0755) != 0 && errno != EEXIST) die("mkdir failed", copy);
  free(copy);
}

static void ensure_parent_dir(const char *path) {
  char *copy = strdup(path);
  if (!copy) die("strdup failed", NULL);
  char *slash = strrchr(copy, '/');
  if (slash) {
    *slash = '\0';
    if (copy[0]) mkdir_p(copy);
  }
  free(copy);
}

static void remove_tree(const char *path) {
  struct stat st;
  if (lstat(path, &st) != 0) {
    if (errno == ENOENT) return;
    die("lstat failed", path);
  }
  if (S_ISDIR(st.st_mode)) {
    DIR *dir = opendir(path);
    if (!dir) die("opendir failed", path);
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
      if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
      char *child = join_path(path, entry->d_name);
      remove_tree(child);
      free(child);
    }
    closedir(dir);
    if (rmdir(path) != 0) die("rmdir failed", path);
  } else {
    if (unlink(path) != 0) die("unlink failed", path);
  }
}

static void copy_regular_file(const char *src, const char *dst, const struct stat *st) {
  ensure_parent_dir(dst);
  int in = open(src, O_RDONLY);
  if (in < 0) die("open source failed", src);
  int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, st->st_mode & 07777);
  if (out < 0) die("open destination failed", dst);
  char buffer[COPY_BUFFER_SIZE];
  ssize_t n;
  while ((n = read(in, buffer, sizeof(buffer))) > 0) write_all(out, buffer, (size_t)n);
  if (n < 0) die("read failed", src);
  close(in);
  close(out);
  chmod(dst, st->st_mode & 07777);
}

static void copy_symlink_file(const char *src, const char *dst) {
  char target[512];
  ssize_t len = readlink(src, target, sizeof(target) - 1);
  if (len < 0) die("readlink failed", src);
  target[len] = '\0';
  ensure_parent_dir(dst);
  unlink(dst);
  if (symlink(target, dst) != 0) die("symlink failed", dst);
}

static void copy_tree(const char *src, const char *dst) {
  struct stat st;
  if (lstat(src, &st) != 0) die("lstat failed", src);
  if (S_ISDIR(st.st_mode)) {
    mkdir_p(dst);
    chmod(dst, st.st_mode & 07777);
    DIR *dir = opendir(src);
    if (!dir) die("opendir failed", src);
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
      if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0 || ignored_context_entry(entry->d_name)) continue;
      char *child_src = join_path(src, entry->d_name);
      char *child_dst = join_path(dst, entry->d_name);
      copy_tree(child_src, child_dst);
      free(child_src);
      free(child_dst);
    }
    closedir(dir);
  } else if (S_ISREG(st.st_mode)) {
    copy_regular_file(src, dst, &st);
  } else if (S_ISLNK(st.st_mode)) {
    copy_symlink_file(src, dst);
  }
}

static void parse_cawfile_files(const char *cawfile, struct string_list *files) {
  size_t size;
  char *text = read_text_file(cawfile, &size);
  char *container = strstr(text, "container");
  if (!container) {
    free(text);
    return;
  }

  char *files_key = strstr(container, "files");
  if (!files_key) {
    free(text);
    return;
  }

  char *equals = strchr(files_key, '=');
  if (!equals) {
    free(text);
    return;
  }

  char *array = strchr(equals, '[');
  if (!array) {
    free(text);
    return;
  }

  for (char *p = array + 1; *p && *p != ']'; p++) {
    if (*p != '"' && *p != '\'') continue;
    char quote = *p++;
    char *start = p;
    char *write = p;
    while (*p && *p != quote) {
      if (*p == '\\' && p[1]) p++;
      *write++ = *p++;
    }
    if (*p == quote && write > start) list_push(files, start, (size_t)(write - start));
  }

  free(text);
  (void)size;
}

static void default_context_files(const char *workflow_dir, struct string_list *files) {
  DIR *dir = opendir(workflow_dir);
  if (!dir) die("opendir failed", workflow_dir);

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0 || ignored_context_entry(entry->d_name)) continue;
    char *src = join_path(workflow_dir, entry->d_name);
    struct stat st;
    if (lstat(src, &st) == 0) list_push(files, entry->d_name, strlen(entry->d_name));
    free(src);
  }
  closedir(dir);
}

static void remove_app_contents(const char *app_dir) {
  mkdir_p(app_dir);
  DIR *dir = opendir(app_dir);
  if (!dir) die("opendir failed", app_dir);

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0 || strcmp(entry->d_name, "ocawecore") == 0) continue;
    char *path = join_path(app_dir, entry->d_name);
    remove_tree(path);
    free(path);
  }
  closedir(dir);
}

static void refresh_app_files(const char *workflow_dir, const char *rootfs) {
  char *app_dir = join_path(rootfs, "app");
  char *cawfile = join_path(workflow_dir, "Cawfile");
  remove_app_contents(app_dir);

  struct stat cawfile_st;
  if (lstat(cawfile, &cawfile_st) == 0 && S_ISREG(cawfile_st.st_mode)) {
    char *dst_cawfile = join_path(app_dir, "Cawfile");
    copy_regular_file(cawfile, dst_cawfile, &cawfile_st);
    free(dst_cawfile);
  }

  struct string_list files = {0};
  if (lstat(cawfile, &cawfile_st) == 0 && S_ISREG(cawfile_st.st_mode)) parse_cawfile_files(cawfile, &files);
  if (files.count == 0) default_context_files(workflow_dir, &files);

  for (size_t i = 0; i < files.count; i++) {
    const char *item = files.items[i];
    if (item[0] == '\0' || strstr(item, "..")) continue;
    char *src = join_path(workflow_dir, item);
    struct stat st;
    if (lstat(src, &st) == 0) {
      char *dst = strcmp(item, ".") == 0 ? strdup(app_dir) : join_path(app_dir, item);
      if (!dst) die("strdup failed", NULL);
      copy_tree(src, dst);
      free(dst);
    } else {
      fprintf(stderr, "warning: file not found for copy: %s\n", src);
    }
    free(src);
  }

  list_free(&files);
  free(cawfile);
  free(app_dir);
}

static char *archive_name(const char *tag) {
  size_t len = strlen(tag);
  char *name = malloc(len + strlen(".rootfs.tar") + 1);
  if (!name) die("malloc failed", NULL);
  for (size_t i = 0; i < len; i++) {
    char ch = tag[i];
    name[i] = ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '.' || ch == '-') ? ch : '-';
  }
  memcpy(name + len, ".rootfs.tar", strlen(".rootfs.tar") + 1);
  return name;
}

static char *archive_join(const char *base, const char *name) {
  if (!base[0]) return strdup(name);
  return join_path(base, name);
}

static char *temporary_output_path(const char *output) {
  size_t len = strlen(output);
  char suffix[64];
  snprintf(suffix, sizeof(suffix), ".tmp.%ld", (long)getpid());
  char *path = malloc(len + strlen(suffix) + 1);
  if (!path) die("malloc failed", NULL);
  memcpy(path, output, len);
  memcpy(path + len, suffix, strlen(suffix) + 1);
  return path;
}

static int compare_names(const void *a, const void *b) {
  const char *const *sa = (const char *const *)a;
  const char *const *sb = (const char *const *)b;
  return strcmp(*sa, *sb);
}

static void write_entry(int out, const char *fs_path, const char *archive_path);

static void write_directory(int out, const char *fs_path, const char *archive_path, const struct stat *st) {
  char *dir_archive_path;
  size_t archive_len = strlen(archive_path);
  if (archive_len > 0 && archive_path[archive_len - 1] != '/') {
    dir_archive_path = malloc(archive_len + 2);
    if (!dir_archive_path) die("malloc failed", NULL);
    memcpy(dir_archive_path, archive_path, archive_len);
    dir_archive_path[archive_len] = '/';
    dir_archive_path[archive_len + 1] = '\0';
  } else {
    dir_archive_path = strdup(archive_path);
    if (!dir_archive_path) die("strdup failed", NULL);
  }

  if (dir_archive_path[0]) write_header(out, dir_archive_path, st, '5', NULL);
  free(dir_archive_path);

  DIR *dir = opendir(fs_path);
  if (!dir) die("opendir failed", fs_path);

  size_t count = 0;
  size_t capacity = 16;
  char **names = malloc(capacity * sizeof(char *));
  if (!names) die("malloc failed", NULL);

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
    if (count == capacity) {
      capacity *= 2;
      char **next = realloc(names, capacity * sizeof(char *));
      if (!next) die("realloc failed", NULL);
      names = next;
    }
    names[count] = strdup(entry->d_name);
    if (!names[count]) die("strdup failed", NULL);
    count++;
  }
  closedir(dir);

  qsort(names, count, sizeof(char *), compare_names);
  for (size_t i = 0; i < count; i++) {
    char *child_fs = join_path(fs_path, names[i]);
    char *child_archive = archive_join(archive_path, names[i]);
    write_entry(out, child_fs, child_archive);
    free(child_fs);
    free(child_archive);
    free(names[i]);
  }
  free(names);
}

static void write_regular_file(int out, const char *fs_path, const char *archive_path, const struct stat *st) {
  write_header(out, archive_path, st, '0', NULL);
  int in = open(fs_path, O_RDONLY);
  if (in < 0) die("open failed", fs_path);

  char buffer[COPY_BUFFER_SIZE];
  ssize_t n;
  while ((n = read(in, buffer, sizeof(buffer))) > 0) {
    write_all(out, buffer, (size_t)n);
  }
  if (n < 0) die("read failed", fs_path);
  close(in);

  size_t remainder = (size_t)(st->st_size % BLOCK_SIZE);
  if (remainder) zero_pad(out, BLOCK_SIZE - remainder);
}

static void write_symlink(int out, const char *fs_path, const char *archive_path, const struct stat *st) {
  char target[256];
  ssize_t len = readlink(fs_path, target, sizeof(target) - 1);
  if (len < 0) die("readlink failed", fs_path);
  target[len] = '\0';
  write_header(out, archive_path, st, '2', target);
}

static void write_entry(int out, const char *fs_path, const char *archive_path) {
  struct stat st;
  if (lstat(fs_path, &st) != 0) die("lstat failed", fs_path);

  if (S_ISDIR(st.st_mode)) {
    write_directory(out, fs_path, archive_path, &st);
  } else if (S_ISREG(st.st_mode)) {
    write_regular_file(out, fs_path, archive_path, &st);
  } else if (S_ISLNK(st.st_mode)) {
    write_symlink(out, fs_path, archive_path, &st);
  }
}

int main(int argc, char **argv) {
  const char *rootfs;
  const char *output;
  char *owned_output = NULL;
  char *container_dir = NULL;
  int build_mode = 0;

  if (argc == 4 && strcmp(argv[1], "--repack") == 0) {
    container_dir = join_path(argv[2], "build/container");
    rootfs = join_path(container_dir, "rootfs");
    char *name = archive_name(argv[3]);
    owned_output = join_path(container_dir, name);
    free(name);
    output = owned_output;
  } else if (argc == 4 && strcmp(argv[1], "--build") == 0) {
    container_dir = join_path(argv[2], "build/container");
    rootfs = join_path(container_dir, "rootfs");
    char *name = archive_name(argv[3]);
    owned_output = join_path(container_dir, name);
    free(name);
    output = owned_output;
    build_mode = 1;
  } else if (argc == 3) {
    rootfs = argv[1];
    output = argv[2];
  } else {
    fprintf(stderr, "usage: %s ROOTFS OUT.tar\n       %s --repack WORKFLOW_DIR TAG\n       %s --build WORKFLOW_DIR TAG\n", argv[0], argv[0], argv[0]);
    return 2;
  }

  if (build_mode) refresh_app_files(argv[2], rootfs);

  char *tmp_output = temporary_output_path(output);
  int out = open(tmp_output, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (out < 0) die("open output failed", tmp_output);

  struct stat st;
  if (lstat(rootfs, &st) != 0) die("lstat failed", rootfs);
  if (!S_ISDIR(st.st_mode)) {
    fprintf(stderr, "rootfs is not a directory: %s\n", rootfs);
    return 2;
  }

  write_directory(out, rootfs, "", &st);
  zero_pad(out, BLOCK_SIZE * 2);
  close(out);
  if (rename(tmp_output, output) != 0) die("rename output failed", output);
  free(tmp_output);
  if (owned_output) free(owned_output);
  if (container_dir) free(container_dir);
  if (argc == 4) free((void *)rootfs);
  return 0;
}
