CC = cc
CFLAGS = -Wall -Wextra -pedantic -std=c11

AS = nasm
ASFLAGS = -f bin

SSRC_FILES = $(shell find ./sys/ -name "*.asm")
SBIN_FILES = $(patsubst %.asm,%.sys,$(SSRC_FILES))

USRC_FILES = $(shell find ./bin/ -name "*asm")
UBIN_FILES = $(patsubst %.asm,%,$(USRC_FILES))

FILES = $(shell find ./files/ -name "*")

MKFS = ./mkffs

.PHONY: tools

all: clean $(SBIN_FILES) $(UBIN_FILES) image qemu

%: %.asm
	$(AS) $(ASFLAGS) -o $@ $^

%.sys: %.asm
	$(AS) $(ASFLAGS) -o $@ $^

image:
	$(MKFS) --create-fs os.img
	$(MKFS) os.img --boot ./sys/boot.sys
	$(MKFS) os.img --copy ./sys/kernel.sys
	$(MKFS) os.img --copy $(UBIN_FILES)

qemu:
	qemu-system-x86_64  os.img --boot a

tools:
	$(CC) $(CFLAGS) -o $(MKFS) ./tools/main.c

clean:
	rm -rf $(SBIN_FILES) $(UBIN_FILES) os.img
