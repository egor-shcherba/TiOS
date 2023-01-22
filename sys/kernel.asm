%define KERNEL_SEGMENT      0x0200
%define FILETABLE_SEGMENT   0x0050
%define USER_SEGMENT        0x5000

%define ENTER_SCANCODE      0x1C
%define BACKSPACE_SCANCODE  0x0E
%define CTR_L               0x0C

%define FLP_SPT  18                     ;; FLOPPY SECTOR PER TRACK
%define FLP_HEAD 2                      ;; FLOPPY HEAD

%macro PRINT_NEW_LINE 0
    mov ah, 0xE
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
%endmacro

[bits 16]
[org 0x0]
  jmp KERNEL_CODE
KERNEL_DATA:

    DISPACHER_FUNC_LIST:
        dw TERMINATE    ;; 0
        dw READ_CHAR    ;; 1
        dw OUT_CHAR     ;; 2
        dw READ_STRING  ;; 3
        dw OUT_STRING   ;; 4

    shell_buffer db "run"
    pad times 256 - ($ - shell_buffer) db 0x0
    shell_cmd_ptr dw 0x0
    shell_arg_ptr dw 0x0
    shell_promt   db "$ ", 0x0


    RUN_CMD      db "run",   0x0
    LIST_CMD     db "list",  0x0
    CLEAR_CMD    db "clear", 0x0
    INFOSYS_CMD  db "infosys", 0x0
    DATE_CMD     db "date",  0x0
    TIME_CMD     db "time",  0x0
    SHUTDOWN_CMD db "shutdown", 0x0
    REBOOT_CMD   db "reboot", 0x0
    HELP_CMD     db "help", 0x0


    SHELL_WELCOME_LBL db "Welcome to the TiOS", 13, 10, 0x0
    SYSTEM_INFO_LBL   db "TiOS v1.0", 13, 10, 0x0
    COMMAND_NOT_FOUND_LBL db ": command not found", 13, 10, 0x0

    HELP_CMD_INFO_LBL db "run list clear infosys date time shutdown reboot", 13, 10, 0x0

KERNEL_CODE:
    ;; SET CGA TEXT COLOR 16 VIDEO MODE AND CLEAR SCREEN
    mov ax, 0x0003
    int 0x10

    mov ah, 0x01
    mov cx, 0x07
    int 0x10

    ;; SET INTERUPT HANDLERS
    xor ax, ax
    mov es, ax

    ;; SET INT 0x20 HANDLER
    mov es:[0x20 * 4 + 0], WORD TERMINATE
    mov es:[0x20 * 4 + 2], WORD KERNEL_SEGMENT

    ;; SET INT 0x21 HANDLER
    mov es:[0x21 * 4 + 0], WORD DISPACHER_HANDLER
    mov es:[0x21 * 4 + 2], WORD KERNEL_SEGMENT

    ;; RESOTE ES SEGMENT
    push cs
    pop es

    mov si, SHELL_WELCOME_LBL
    call KPRINT_STRING

SHELL:
    mov si, shell_promt
    call KPRINT_STRING

    ;; clear shell buffer
    mov cx, 256
    mov di, shell_buffer
    mov al, 0x0

.fill_zero_buffer:
    stosb
    loop .fill_zero_buffer

    xor cx, cx
    mov di, shell_buffer
.read:
    xor ax, ax
    int 0x16

    cmp ah, ENTER_SCANCODE
    je .press_enter
    cmp ah, BACKSPACE_SCANCODE
    je .press_bs
    cmp al, CTR_L
    je EXEC_CLEAR_CMD

    cmp al, 0x20
    jb .read
    mov ah, 0xE
    int 0x10
    inc cx
    cmp cx, 255
    je .read
    stosb
    jmp .read

.press_enter:
    PRINT_NEW_LINE

    call PARSE_CMD_BUFFER

    mov si, [shell_cmd_ptr]             ;; IF COMMAND IS EMTPY
    cmp si, WORD 0x0                    ;; JUMP TO READ NEW COMMAND
    je SHELL

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'run'
    mov di, RUN_CMD
    call COMPARE_STRING
    jc EXEC_RUN_CMD

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'list'
    mov di, LIST_CMD
    call COMPARE_STRING
    jc EXEC_LIST_CMD

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'clear'
    mov di, CLEAR_CMD
    call COMPARE_STRING
    jc EXEC_CLEAR_CMD

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'infosys'
    mov di, INFOSYS_CMD
    call COMPARE_STRING
    jc EXEC_INFOSYS_CMD
 
    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'shutdown'
    mov di, SHUTDOWN_CMD
    call COMPARE_STRING
    jc EXEC_SHUTDOWN_CMD

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'reboot'
    mov di, REBOOT_CMD
    call COMPARE_STRING
    jc EXEC_REBOOT_CMD

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'time'
    mov di, TIME_CMD
    call COMPARE_STRING
    jc EXEC_TIME_CMD

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'date'
    mov di, DATE_CMD
    call COMPARE_STRING
    jc EXEC_DATE_CMD

    mov si, [shell_cmd_ptr]             ;; IF COMMAND = 'help'
    mov di, HELP_CMD
    call COMPARE_STRING
    jc EXEC_HELP_CMD

.not_found_cmd:                         ;; IF COMMAND NOT FOUND
                                        ;; PRINT MESSAGE 'command not found'
    mov si, [shell_cmd_ptr]
    call KPRINT_STRING
    mov si, COMMAND_NOT_FOUND_LBL
    call KPRINT_STRING

    jmp SHELL

.press_bs:
    or cx, 0x0
    je .read

    dec di
    mov [di], BYTE 0x20

    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, 0x20
    int 0x10
    mov al, 0x08
    int 0x10

    dec cx
    jmp .read


EXEC_RUN_CMD:
    cmp [shell_arg_ptr], WORD 0x0
    je .miss_arg

    mov cx, 255
    mov ax, FILETABLE_SEGMENT
    mov ds, ax
    xor bx, bx

.next_record:
    mov si, bx
    cmp [si], BYTE 0x0
    jne .compare_file
    add bx, 16
    loop .next_record

    jmp .file_not_found

.compare_file:
    mov di, cs:[shell_arg_ptr]

    call COMPARE_STRING
    jc .found_file

    add bx, 16
    loop .next_record
    jmp .done

.found_file:
    mov si, bx

    mov ax, [si + 12]                   ;; GET SECTOR START FROM FILE TABLE
    mov bx, [si + 14]                   ;; GET FILE LENGTH FROM FILE TABLE
    mov [bp - 2], bx                    ;; SAVE FILE LENGTH

    push ax                             ;; CONVERT LBA TO CHS
    xor dx, dx                          ;; ABSOLUTE TRACK   (LBA / (Sector Per Track % head)
    mov bx, FLP_SPT                     ;; ABSOLUTE HEAD    (LBA / Sctor Per Track) * head
    div bx                              ;; ABSOLUTE SECTOR  (LBA % Sector Per Track) + 1
    inc dx
    mov [bp - 4], dx                    ;; SAVE ABSOLUTE SECTOR

    xor dx, dx
    mov bx, FLP_HEAD
    div bx
    mov [bp - 6], dx                    ;; SAVE ABSOLUTE HEAD

    mov ax, FLP_SPT
    mov bx, FLP_HEAD
    mul bx
    mov bx, ax
    pop ax
    xor dx, dx
    div bx
    mov [bp - 8], ax                    ;; SAVE ABSOLUTE TRACK

    xor ax, ax                          ;; SETUP BUFFER TO READ
    mov ax, USER_SEGMENT                ;; 0x5000:0000
    mov es, ax
    xor bx, bx

.read_file:
    mov ah, 0x2                         ;; AH = 2, READ SECTOR
    mov al, [bp - 2]                    ;; SET SECTOR READS
    mov ch, [bp - 8]                    ;; SET CYLINDER
    mov cl, [bp - 4]                    ;; SET SECTOR
    mov dh, [bp - 6]                    ;; SET HEAD
    mov dl, 0x80                        ;; DEVICE
    int 0x13                            ;; READ KERNEL
    jc .read_file                       ;; IF ERROR TRY AGAIN

    mov ax, USER_SEGMENT                ;; SETTING KERNEL SEGMENTS
    mov es, ax                          ;; es, ds, gs, fs = 0x2000
    mov ds, ax
    mov gs, ax
    mov fs, ax
    mov ss, ax
    mov sp, 0xFFFF

    jmp USER_SEGMENT:0x0000             ;; JUMP TO THE KERNEL MEMORY ADDRESS

.file_not_found:
    push cs
    pop ds
    mov si, [shell_arg_ptr]
    call KPRINT_STRING

    mov si, .file_not_found_lbl
    call KPRINT_STRING
    jmp .done

.miss_arg:
    mov si, .missing_arg_lbl
    call KPRINT_STRING
    jmp .done

.done:
    mov ax, KERNEL_SEGMENT
    mov ds, ax
    jmp SHELL

.missing_arg_lbl    db "run: missing argument", 13, 10, 0x0
.file_not_found_lbl db ": file not found", 13, 10, 0x0

EXEC_LIST_CMD:
    push dx
    mov ax, 0x50
    xor dx, dx
    mov ds, ax

    mov cx, 255
    xor si, si
    mov bx, si

.next_file:
    cmp [si], BYTE 0x0
    jnz .print_file

    add bx, 16
    mov si, bx

    loop .next_file
    jmp .done

.print_file:
    cmp dx, 23
    jbe .print_filename

.press_enter:
    xor ax, ax
    int 0x16
    cmp ah, ENTER_SCANCODE
    jne .press_enter

.print_filename:
    call KPRINT_STRING
    PRINT_NEW_LINE

    inc dx

    add bx, 16
    mov si, bx

    loop .next_file
.done:
    mov ax, KERNEL_SEGMENT
    mov ds, ax
    pop dx
    jmp SHELL

EXEC_CLEAR_CMD:
    mov ax, 0x0003
    int 0x10

    mov ah, 0x01
    mov cx, 0x07
    int 0x10

    jmp SHELL


EXEC_DATE_CMD:
    mov ah, 0x04
    int 0x1A

    mov bx, .table

    mov ax, dx
    shr al, 4
    xlatb
    mov ah, 0xE
    int 0x10
    mov al, dl
    and ax, 0xF
    xlatb
    mov ah, 0xE
    int 0x10

    mov ah, 0xE
    mov al, "/"
    int 0x10

    mov al, dh
    shr al, 4
    mov ah, 0xE
    xlatb
    int 0x10
    mov al, dh
    and al, 0xF
    xlatb
    int 0x10

    mov ah, 0xE
    mov al, "/"
    int 0x10

    mov ax, cx
    shr ax, 12
    and ax, 0x0F
    xlatb
    mov ah, 0x0E
    int 0x10

    mov ax, cx
    shr ax, 8
    and ax, 0x0F
    xlatb
    mov ah, 0x0E
    int 0x10

    mov ax, cx
    shr ax, 4
    and ax, 0x0F
    xlatb
    mov ah, 0x0E
    int 0x10

    mov ax, cx
    and ax, 0x0F
    xlatb
    mov ah, 0x0E
    int 0x10

    PRINT_NEW_LINE

    jmp SHELL

.table db "0123456789"

EXEC_TIME_CMD:
    mov ah, 0x02
    int 0x1A

    mov bx, .table
    mov al, ch
    shr al, 4
    xlatb
    mov ah, 0xE
    int 0x10
    mov al, ch
    and al, 0xF
    xlatb
    int 0x10

    mov al, ":"
    int 0x10

    mov al, cl
    shr al, 4
    xlatb
    mov ah, 0xE
    int 0x10
    mov al, cl
    and al, 0xF
    xlatb
    int 0x10

    mov al, ":"
    int 0x10

    mov al, dh
    shr al, 4
    xlatb
    mov ah, 0xE
    int 0x10
    mov al, dh
    and al, 0xF
    xlatb
    int 0x10

    PRINT_NEW_LINE

    jmp SHELL

.table db "0123456789"

EXEC_INFOSYS_CMD:
    mov si, SYSTEM_INFO_LBL
    call KPRINT_STRING
    jmp SHELL

EXEC_HELP_CMD:
    mov si, HELP_CMD_INFO_LBL
    call KPRINT_STRING
    jmp SHELL

EXEC_REBOOT_CMD:
    jmp 0xFFFF:0x0

EXEC_SHUTDOWN_CMD:
    mov dx, 0x0604
    mov ax, 0x2000
    out dx, ax

HALT:
    cli                     ;; DISABLE INTERUPT
    hlt                     ;; HALT THE PROCESSOR


;; COMPARE STRING
;; IN:
;;  DS:SI - string 1
;;  ES:DI - string 2
;; OUT:
;;  CARRY FLAG = 1 if equal
COMPARE_STRING:
.rep:
    cmpsb
    jnz .not_equal
    cmp ds:[si], BYTE 0x0
    je .equal
    jmp .rep

.equal:
    cmp es:[di], BYTE 0x0
    jne .not_equal
    stc
    ret

.not_equal:
    clc
    ret

PARSE_CMD_BUFFER:
    mov [shell_cmd_ptr], WORD 0x0
    mov [shell_arg_ptr], WORD 0x0
    mov cx, 255
    mov si, shell_buffer

.find_cmd:
    lodsb
    cmp al, 0x0
    je .done
    cmp al, 0x20
    jne .found_cmd
    loop .find_cmd
    jmp .done

.found_cmd:
    dec si
    mov [shell_cmd_ptr], si
    dec si

.find_end_cmd:
    lodsb
    cmp al, 0x0
    je .found_end_cmd
    cmp al, 0x20
    je .found_end_cmd
    loop .find_end_cmd
    jmp .done

.found_end_cmd:
    dec si
    mov [si], BYTE 0x0
    inc si

.find_arg:
    lodsb
    cmp al, 0x0
    je .done
    cmp al, 0x20
    jne .found_arg
    loop .find_arg
    jmp .done

.found_arg:
    dec si
    mov [shell_arg_ptr], si

.done:
    ret

;; PRINT ZERO TERMINATED STRING TO SCREEN
;; IN :
;;  SI - address of string bufffer
KPRINT_STRING:
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


DISPACHER_HANDLER:
    pusha

    xor bx, bx
    mov bl, ah
    shl bx, 1

    lea bx, cs:[DISPACHER_FUNC_LIST + bx]
    jmp [cs:bx]

.done:
    popa
    iret

;; TERMINATE PROCESS
;; INT 0x21 AH = 0 OR INT 0x20
TERMINATE:
    mov ax, KERNEL_SEGMENT
    mov ds, ax
    mov es, ax
    mov gs, ax
    mov fs, ax

    xor ax, ax
    mov ss, ax
    mov sp, KERNEL_SEGMENT

    PRINT_NEW_LINE

    jmp KERNEL_SEGMENT:SHELL


;; READ CHAR FROM KEYBOARD WITH ECHO
;; INT 0x21 AH = 0x1
;; OUT:
;;  AH - SCANCODE, AL - ASCII CODE
READ_CHAR:
    popa

.read:
    xor ax, ax
    int 0x16

    cmp ah, ENTER_SCANCODE
    je .press_enter

    or al, 0x0
    jz .read
    jmp .done
.press_enter:
    push ax
    PRINT_NEW_LINE

    pop ax
.done:
    push ax
    mov ah, 0xE
    int 0x10
    pop ax

    iret

;; PRINT CHAR TO THE SCREEN
;; INT 0x21 AH = 0x2
;; IN:
;;  AL = CHAR
OUT_CHAR:
    mov ah, 0xE
    int 0x10
    popa
    iret


;; READ STRING FROM KEYBOARD WITH ECHO
;; INT 0x21 AH = 0x3
;; IN:
;;  ES:DI - BUFFER
;;  CX - BUFFER LENGTH
READ_STRING:
.read_char:
    xor ax, ax
    int 0x16

    cmp ah, ENTER_SCANCODE
    je .press_enter

    cmp ah, BACKSPACE_SCANCODE
    je .press_bs

    mov ah, 0xE
    int 0x10

    cmp cx, 0x0
    jnz .save_char

.save_char:
    stosb
    dec cx
    jmp .read_char

.press_bs:
    inc cx
    dec di
    mov [di], BYTE 0x0

    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, 0x20
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .read_char

.press_enter:
    PRINT_NEW_LINE

.done:
    popa
    iret

;; PRINT STING TO THE SCREEN
;; INT 0x21 AH = 0x4
;; IN:
;;  DS:SI - NULL TERMINATED STRING
OUT_STRING:
    mov ah, 0xE
.L0:
    lodsb
    or al, 0x0
    jz .done
    int 0x10
    jmp .L0
.done:
    popa
    iret
