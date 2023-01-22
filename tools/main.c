#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libgen.h>
#include <stdint.h>

#define BOOT_SIGNATURE 0xAA55
#define FN_LEN 12                       /* filename length */

typedef struct dirent {
  char filename[FN_LEN];                /* filename */
  uint16_t st;                          /* sector start of file */
  uint16_t len;                         /* length of file in sectors */
} dirent_t;

#define BSIZE 512                       /* block size */
#define DPB (BSIZE / sizeof(dirent_t))  /* dirent_t per block */
#define BFD 9                           /* blocks for dirent_t */
#define MAX_DIRENT  (BFD * DPB)         /* max count of dirent_t */

#define MAX(x, y) ((x < y) ? y : x)

FILE *disk = NULL;
dirent_t *dirents = NULL;

static void mount_fs(const char *filepath);
static void sync_fs(void);

static void cli_create_fs(int argc, char *argv[]);
static void cli_boot(int argc, char *argv[]);
static void cli_copy(int argc, char *argv[]);
static void cli_list(void);
static void cli_help(void);

static void missing_args(void);

int
main(int argc, char *argv[])
{
  if (argc < 2)
    missing_args();

  if (strcmp(argv[1], "--create-fs") == 0)
    cli_create_fs(argc - 2, argv + 2);

  if (strcmp(argv[1], "--help") == 0)
    cli_help();

  mount_fs(argv[1]);

  if (strcmp(argv[2], "--boot") == 0)
    cli_boot(argc - 3, argv + 3);

  if (strcmp(argv[2], "--copy") == 0)
    cli_copy(argc - 3, argv + 3);

   if (strcmp(argv[2], "--list") == 0)
    cli_list();

  sync_fs();
  missing_args();
}

static void
missing_args(void)
{
  printf("fss: missing arguments\n");
  printf("Try: ffs --help for more information\n");
}

static void
mount_fs(const char *filepath)
{
  disk = fopen(filepath, "r+b");

  if (disk == NULL)
    {
      perror("image");
      exit(EXIT_FAILURE);
    }

  dirents = (dirent_t*) malloc(MAX_DIRENT * sizeof(dirent_t));
  fseek(disk, BSIZE, SEEK_SET);
  int rc = fread(dirents, 1, MAX_DIRENT * sizeof(dirent_t), disk);

  if (rc != MAX_DIRENT * sizeof(dirent_t))
    {
      printf("bad load filesystem\n");
      sync_fs();
      exit(EXIT_FAILURE);
    }
}

static void
sync_fs(void)
{
  fseek(disk, BSIZE, SEEK_SET);
  fwrite(dirents, 1, sizeof(dirent_t) * MAX_DIRENT, disk);
  free(dirents);
  fclose(disk);
}

static void
cli_create_fs(int argc, char *argv[])
{
  uint16_t total_blks = 2880;

  if (argc < 1)
    missing_args();

  if (argc >= 2 && atoi(argv[1]) != 0)
    total_blks = MAX(atoi(argv[1]), BFD + 2);

  FILE *fimage = fopen(argv[0], "wb");

  if (fimage == NULL)
    {
      perror("ffs");
      exit(EXIT_FAILURE);
    }

  dirent_t rec = { "", BFD + 1, total_blks - BFD - 1};
  fseek(fimage, BSIZE, SEEK_SET);
  fwrite(&rec, 1, sizeof(dirent_t), fimage);
  fseek(fimage, BSIZE * (BFD + 1), SEEK_SET);

  uint8_t empty_blk[BSIZE] = { 0x0 };
  for (uint16_t i = 0; i < total_blks - BFD - 1; i++)
    fwrite(empty_blk, 1, BSIZE, fimage);

  fclose(fimage);

  printf("create flat file system %s\n", argv[0]);
  printf("--total blocks: %d\n", total_blks);
  printf("--volume size : %d\n", total_blks * BSIZE);

  exit(EXIT_SUCCESS);
}

static void
cli_list(void)
{
  printf("filetable:\n");
  for (uint16_t i = 0; i < MAX_DIRENT; i++)
    {
      if (dirents[i].len == 0)
        break;

      if (dirents[i].filename[0] == '\0')
        printf("%-12s ", "empty chunk");
      else
        printf("%-12s ", dirents[i].filename);
      printf("%04x - %04x\n", dirents[i].st, dirents[i].len);
    }

  sync_fs();
  exit(EXIT_SUCCESS);
}

static void
cli_help(void)
{
  const char *s =
    "ffs - utilty to create flat file system for TiOS\n" \
    "ffs --create-fs <image> [block count]  create disk image\n" \
    " <image> - image file name\n" \
    " [block count] - optional parameter default value 2880\n" \
    "ffs <image> --boot boofile   copy bootfile into the boot sector\n" \
    "ffs <image> --copy files     copy files into the disk image\n" \
    "ffs <image> --list           show root directory contents\n";

  printf("%s", s);

  exit(EXIT_SUCCESS);
}

static void
cli_boot(int argc, char *argv[])
{
  if (argc < 1)
    missing_args();

  FILE *boot_file = fopen(argv[0], "rb");

  if (boot_file == NULL)
    {
      perror(argv[0]);
      exit(EXIT_FAILURE);
    }

  uint16_t boot_val = 0x0;
  fseek(boot_file, BSIZE - 2, SEEK_SET);
  int rc = fread(&boot_val, 1, sizeof(uint16_t), boot_file);

  if (rc != sizeof(uint16_t) || boot_val != BOOT_SIGNATURE)
    {
      printf("boot file %s is not valid\n", argv[0]);
      exit(EXIT_FAILURE);
    }

  uint8_t block[BSIZE];
  fseek(boot_file, 0L, SEEK_SET);

  if ((rc = fread(block, 1, BSIZE, boot_file)) != BSIZE)
    {
      printf("bad read boot file %d\n", rc);
      sync_fs();
      exit(EXIT_FAILURE);
    }

  fseek(disk, 0L, SEEK_SET);
  fwrite(block, 1, BSIZE, disk);

  fclose(boot_file);
  sync_fs();

  exit(EXIT_SUCCESS);
}

static int
file_exists(const char *filename)
{
  for (uint16_t i = 0; i < MAX_DIRENT; i++)
    {
      if (strcmp(dirents[i].filename, filename) == 0)
        return 0;
    }

  return -1;
}

static void
cli_copy(int argc, char *argv[])
{
  dirent_t *dir = NULL;

  for (int i = 0; i < (int) MAX_DIRENT; i++)
    {
      if (dirents[i].filename[0] == '\0' && dirents[i].len != 0x0)
        {
          dir = dirents + i;
          break;
        }
    }

  for (int i = 0; i < argc; i++)
    {
      FILE *file = fopen(argv[i], "rb");

      if (file == NULL)
        {
          perror(argv[i]);
          continue;
        }

      if (file_exists(basename(argv[i])) == 0)
        {
          printf("filename %s already is exists on the disk image\n", argv[i]);
          continue;
        }

      int write_sectors = 0;
      uint8_t block[BSIZE] = { 0x0 };

      fseek(disk, dir->st * BSIZE, SEEK_SET);

      while(1)
        {
          int rc = fread(block, 1, BSIZE, file);

          if (rc == 0)
            break;

          fwrite(block, 1, rc, disk);
          write_sectors++;
        }

      (dir + 1)->len = (dir->len - write_sectors);
      (dir + 1)->st = dir->st + write_sectors;
      dir->len = write_sectors;
      strncpy(dir->filename, basename(argv[i]), FN_LEN - 1);
      dir++;

      fclose(file);
    }

  sync_fs();
  exit(EXIT_SUCCESS);
}