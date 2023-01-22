%define BOOT_SIGNATURE 0xAA55
%define MAX_FILES 255       ;; NUMBER OF RECORDS IN THE FILE TABLE
%define FN_MAX 12           ;; FILE NAME SIZE
%define DIRENT_SIZE 16      ;; SIZE OF RECORD FILE TABLE
%define FLP_SPT  18         ;; FLOPPY SECTOR PER TRACK
%define FLP_HEAD 2          ;; FLOPPY HEAD

%define KERNEL_SEGMENT 0x0200

[bits 16]
org 0x7c00
    jmp _code
_data:
    msg_not_found   db "kernel not found...", 13, 0
    found_file      db "kernel.sys"
    times FN_MAX - ($ - found_file) db 0x0
    dev_num         db 0x0
_code:
    ;; SET CGA TEXT COLOR 16 VIDEO MODE AND CLEAR SCREEN
    mov ax, 0x0003
    int 0x10

    ;; SETUP A STACK
    mov sp, 0xFFF0
    mov bp, sp

    mov [dev_num], dl

FLOPPY_RESET:
    xor ax, ax
    int 0x13
    jc FLOPPY_RESET

    mov ax, 0x50            ;; SET BUFFER ADDRESS POINTER
    xor bx, bx              ;; ES:BX = 0x0050:0x0000
    mov es, ax
READ_FILETABLE:
    mov ah, 0x2             ;; READ SECTOR
    mov al, 9               ;; SECTOR TO READ COUNT
    mov ch, 0               ;; CYLINDER
    mov cl, 2               ;; SECTOR
    mov dh, 0               ;; HEAD
    int 0x13
    jc READ_FILETABLE       ;; IF ERROR TRY AGAIN

FOUND_KERNEL:
    mov cx, MAX_FILES       ;; SET ENTRIES COUNT
    xor di, di
.search_next:
    push cx                 ;; COMPARE CURRENT FILE TABLE ENTRY WITH KERNEL FILENAME
    push di                 ;; IF EQUAL JUMP TO LOAD KERNEL LABLE
    mov si, found_file      ;; ELSE GO TO NEXT ENTRY AND REPEAT UNTIL
    mov cx, FN_MAX          ;; THE END OF ENTRIES
    repe cmpsb
    pop di
    pop cx
    jz LOAD_KERNEL
    add di, DIRENT_SIZE
    loop .search_next

KERNEL_NOT_FOUND:
    lea si, cs:[msg_not_found]
    call PRINT_STRING
    jmp HALT

LOAD_KERNEL:
    mov ax, es:[di + 12]    ;; GET SECTOR START FROM FILE TABLE
    mov bx, es:[di + 14]    ;; GET FILE LENGTH FROM FILE TABLE
    mov [bp - 2], bx        ;; SAVE FILE LENGTH

    push ax                 ;; CONVERT LBA TO CHS
    xor dx, dx              ;; ABSOLUTE TRACK   (LBA / (Sector Per Track % head)
    mov bx, FLP_SPT         ;; ABSOLUTE HEAD    (LBA / Sctor Per Track) * head
    div bx                  ;; ABSOLUTE SECTOR  (LBA % Sector Per Track) + 1
    inc dx
    mov [bp - 4], dx        ;; SAVE ABSOLUTE SECTOR

    xor dx, dx
    mov bx, FLP_HEAD
    div bx
    mov [bp - 6], dx        ;; SAVE ABSOLUTE HEAD

    mov ax, FLP_SPT
    mov bx, FLP_HEAD
    mul bx
    mov bx, ax
    pop ax
    xor dx, dx
    div bx
    mov [bp - 8], ax        ;; SAVE ABSOLUTE TRACK

    xor ax, ax              ;; SETUP BUFFER TO READ
    mov ax, KERNEL_SEGMENT
    mov es, ax
    xor bx, bx
READ_KERNEL_FILE:
    mov ah, 0x2             ;; AH = 2, READ SECTOR
    mov al, [bp - 2]        ;; SET SECTOR READS
    mov ch, [bp - 8]        ;; SET CYLINDER
    mov cl, [bp - 4]        ;; SET SECTOR
    mov dh, [bp - 6]        ;; SET HEAD
    mov dl, cs:[dev_num]
    int 0x13                ;; READ KERNEL
    jc READ_KERNEL_FILE     ;; IF ERROR TRY AGAIN

    mov ax, KERNEL_SEGMENT  ;; SETTING KERNEL SEGMENTS
    mov es, ax              ;; es, ds, gs, fs = 0x2000
    mov ds, ax
    mov gs, ax
    mov fs, ax
    xor ax, ax
    mov ss, ax              ;; SETUP A KERNEL STACK 0x2000
    mov sp, KERNEL_SEGMENT

    jmp KERNEL_SEGMENT:0x0000       ;; JUMP TO THE KERNEL MEMORY ADDRESS

HALT:
    cli                     ;; DISABLE INTERUPT
    hlt                     ;; HALT THE PROCESSORT

;; PRINT ZERO TERMINATED STRING TO SCREEN
;; IN :
;;  SI - address of string bufffer
PRINT_STRING:
    push ax
    push si
    mov ah, 0xE
.outchar:
    lodsb
    or al, 0x0
    jz .done
    int 0x10
    jmp .outchar
.done:
    pop si
    pop ax
    ret

    times 510 - ($ - $$) db 0x0
    dw BOOT_SIGNATURE