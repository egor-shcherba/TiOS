    mov ah, 0x4
    mov si, msg
    int 0x21

    int 0x20

msg db "hello, world!", 0x0