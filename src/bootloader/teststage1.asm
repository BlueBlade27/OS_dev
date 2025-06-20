org 0x7C00
bits 16

start:
    mov ah, 0x0E
    mov al, 'X'
    int 0x10

hang:
    jmp hang

times 510 - ($ - $$) db 0
dw 0xAA55
