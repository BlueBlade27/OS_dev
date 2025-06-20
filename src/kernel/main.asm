org 0
bits 16

%define ENDL 0x0D, 0x0A

start:
    
    mov si, msg_hello
    call puts

.halt:
    cli
    hlt

puts:
    push si
    push ax

.loop:
    lodsb
    or al, al
    jz .done

    mov ah, 0x0e
    mov bh, 0
    int 0x10

    jmp .loop

.done:
    pop ax
    pop si
    ret


msg_hello: db 'Hello World!', ENDL, 0

