%define CGA_PAGE_1_ADDR     0xB900

%define HIDDEN_CURSOR       0x2607
%define RECTANGLE_CURSOR    0x0007

%define ESC_SCANCODE        0x01
%define Q_SCANCODE          0x10
%define E_SCANCODE          0x12
%define S_SCANCODE          0x1F

%define COL_ROWS            80
%define COL_LINES           24
%define LINE_WIDTH          (COL_ROWS * 2)
%define LINE_HEIGHT         (COL_LINES * 2)
%define POSITION(x, y)      LINE_WIDTH * (y) + 2 * (x)

    jmp _CODE

_DATA:
    active_segment  db 0x1

    segment_val     dw 0x5000
    offset_val      dw 0x0170

    app_name_lbl    db "memory dump", 0x0
    seg_off_lbl     db "segment : XXXX  offset : YYYY", 0x0
    bottom_lbl      db "esc - exit program; s - switch segment / offset; q / e / enter - change value", 0x0
    top_lbl         db "OFFSET  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F      ASCII", 0x0

    hex_table       db "0123456789ABCDEF"

    memory          times 0x100 db 0x00

_CODE:

PREPARE:
    ;; PREPARE PROGRAM
    ;; SWITCH CGA VIDEO PAGE TO 1
    mov ah, 0x5
    mov al, 1
    int 0x10

    ;; HIDE CURSOR
    mov ah, 0x1
    mov cx, HIDDEN_CURSOR
    int 0x10

    ;; SETUP SEGMENT TO VIDE BUFFER
    mov ax, CGA_PAGE_1_ADDR
    mov es, ax

DISPLAY_WINDOW:

    ;; DISPLAY APP NAME LABEL
    mov si, app_name_lbl
    mov di, POSITION(1,0)
    call PRINT_STRING_AT

    ;; DISPLAY SEGMENT / OFFSET LABEL
    mov si, seg_off_lbl
    mov di, POSITION(1, 1)
    call PRINT_STRING_AT

    ;; DISPLAY BOTTOM TEXT LABEL
    mov si, bottom_lbl
    mov di, POSITION(1, 24)
    call PRINT_STRING_AT

    ;; DISPLAY TOP TEXT LABEL
    mov si, top_lbl
    mov di, POSITION(1, 4)
    call PRINT_STRING_AT

    ;; FILL BOTTOM WHITE COLOR
    mov al, 0b01110000
    mov cx, COL_ROWS
    mov di, POSITION(0, COL_LINES) + 1
    call FILL_COLOR_AT

    ;; DRAWING HORIZONT LINE
    mov cx, COL_ROWS
    mov di, POSITION(0, 2)
.draw_hor_line:
    mov al, 0xC4
    stosb
    inc di
    loop .draw_hor_line

.draw_vert_line:


UPDATE_WINDOW:
    ;; PRINT SEGMENT VALUE
    mov ax, [segment_val]
    mov di, POSITION(11, 1)
    call SHOW_HEX_WORD_AT

    ;; PRINT OFFSET VALUE
    mov ax, [offset_val]
    mov di, POSITION(26, 1)
    call SHOW_HEX_WORD_AT

    call MEMCOPY
    call SHOW_MEMORY_TABLE

HIGHLIGHT_SEGMENT:
    cmp [active_segment], BYTE 0x0
    jz IS_ACTIVE_OFFSET

IS_ACTIVE_SEGMENT:
    mov al, 0b01110000
    mov cx, 14
    mov di, POSITION(1, 1) + 1
    call FILL_COLOR_AT

    mov al, 0b00000111
    mov cx, 13
    mov di, POSITION(17, 1) + 1
    call FILL_COLOR_AT
    jmp PRESS_KEY

IS_ACTIVE_OFFSET:
    mov al, 0b01110000
    mov cx, 13
    mov di, POSITION(17, 1) + 1
    call FILL_COLOR_AT

    mov al, 0b00000111
    mov cx, 14
    mov di, POSITION(1, 1) + 1
    call FILL_COLOR_AT

PRESS_KEY:
    xor ax, ax
    int 0x16
    cmp ah, S_SCANCODE
    je .pressed_s
    cmp ah, E_SCANCODE
    je .pressed_e
    cmp ah, Q_SCANCODE
    je .pressed_q
    cmp ah, ESC_SCANCODE
    je TERMINATE

    jmp PRESS_KEY

.pressed_s:
    mov al, [active_segment]
    xor al, 0x1
    mov [active_segment], al
    jmp UPDATE_WINDOW

.pressed_q:
    mov ax, [active_segment]
    cmp ax, 0x0
    je .dec_offset
    mov ax, [segment_val]
    sub ax, 0x10
    mov [segment_val], ax
    jmp UPDATE_WINDOW

.dec_offset:
    mov ax, [offset_val]
    sub ax, 0x10
    mov [offset_val], ax
    jmp UPDATE_WINDOW

.pressed_e:
    mov ax, [active_segment]
    cmp ax, 0x0
    je .inc_offset
    mov ax, [segment_val]
    add ax, 0x10
    mov [segment_val], ax
    jmp UPDATE_WINDOW

.inc_offset:
    mov ax, [offset_val]
    add ax, 0x10
    mov [offset_val], ax
    jmp UPDATE_WINDOW

TERMINATE:
    ;; SWITCH CGA VIDEO PAGE TO 0
    mov ah, 0x5
    mov al, 0
    int 0x10

    ;; SHOW CURSOR
    mov ah, 0x1
    mov cx, RECTANGLE_CURSOR
    int 0x10

    int 0x20

;; PRINT STRING AT POSITION
;; IN:
;;  DI - POSITION
;;  SI - STRING ADDRESS TO PRINT
PRINT_STRING_AT:
    push di
    push si

.out_char:
    lodsb
    cmp al, 0x0
    jz .done
    stosb
    inc di
    jmp .out_char

.done:
    pop si
    pop di
    ret

;; PRINT BYTE IN HEXADECIMAL FORMAT AT POSITION
;; IN:
;;  AL - BYTE
;;  DI - POSITION
SHOW_HEX_BYTE_AT:
    push ax
    push bx

    push ax
    mov bx, hex_table

    shr al, 0x4
    xlatb
    stosb
    inc di

    pop ax
    and al, 0xF
    xlatb
    stosb
    inc di

    pop bx
    pop ax
    ret

;; PRINT WORD IN HEXADECIMAL FORMAT AT POSITION
;; IN:
;;  AX - WORD
;;  DI - POSIITON
SHOW_HEX_WORD_AT:
    ror ax, 8
    call SHOW_HEX_BYTE_AT
    ror ax, 8
    call SHOW_HEX_BYTE_AT

    ret



SHOW_MEMORY_TABLE:
    mov bx, memory

    mov cx, 0x10
    mov di, POSITION(9, 6)
.next_line:
    push cx
    push di

    mov cx, 0x10
.out_byte:
    mov al, [bx]
    call SHOW_HEX_BYTE_AT
    inc di
    inc di
    inc bx
    loop .out_byte

    pop di
    pop cx
    add di, LINE_WIDTH
    loop .next_line

    mov ax, [offset_val]
    mov di, POSITION(3, 6)
    mov cx, 0x10
.out_offset_numbers:
    push di
    call SHOW_HEX_WORD_AT
    pop di
    add di, LINE_WIDTH
    add ax, 0x10
    loop .out_offset_numbers

    mov bx, memory
    mov cx, 0x10
    mov di, POSITION(COL_ROWS - 18, 6)
.out_ascii_simbols:
    push cx
    push di

    mov cx, 0x10
.out_ascii_lines:
    mov al, [bx]
    cmp al, 0x19
    jb .set_char_dot
    cmp al, 0x7F
    ja .set_char_dot
    jmp .out_char

.set_char_dot:
    mov al, '.'
.out_char:
    stosb
    inc di
    inc bx
    loop .out_ascii_lines
    pop di
    pop cx
    add di, LINE_WIDTH
    loop .out_ascii_simbols

    ret


MEMCOPY:
    push ds
    push es

    push ds
    pop es
    mov di, memory

    mov ax, [segment_val]
    mov ds, ax
    mov si, [offset_val]

    mov cx, 0x10 * 0x10
.copy:
    lodsb
    stosb
    loop .copy

    pop es
    pop ds
    ret


;; FILL COLOR
;; IN:
;;  AL - color
;;  CX - repeat count
;;  DI - start position
FILL_COLOR_AT
    stosb
    inc di
    loop FILL_COLOR_AT
    ret