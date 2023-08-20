BITS 16
org 0x7c00

page equ 1 ;use page 1 to ide boot messaages

start:
    mov ax, 0
    mov es, ax ;cant set es to literal
    call set_screen_page
    call print_hello
loop:
    jmp loop

set_screen_page:
    mov ah, 0x5 ;set active display page
    mov al, page ;page number
    int 0x10
    ret

print_hello:
    mov ah, 0x13 ;write string
    mov al, 1 ;write mode: update cursor
    mov bp, msg ; message
    mov cx, (msg_end - msg) ;number of chars
    mov bl, 0xe ;colour: yellow
    mov bh, page ;page number
    mov dh, 1 ;row
    mov dl, 1 ;column
    int 0x10
    ret

msg:
    db "Hello World!"
msg_end:

    times 510 - ($ - $$) db 0xff
    dw 0xaa55