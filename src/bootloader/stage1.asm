org 0x7C00
bits 16

jmp short start
nop

; BPB (BIOS Parameter Block)
OEM:                    db 'MSWIN4.1'           
BytesPerSector:         dw 512                 
SectorsPerCluster:      db 1
ReservedSectors:        dw 1
FatCount:               db 2
DirEntries:             dw 224
TotalSectors:           dw 2880
MediaType:              db 0xF0
SectorsPerFat:          dw 9
SectorsPerTrack:        dw 18
Heads:                  dw 2
HiddenSectors:          dd 0
LargeSectors:           dd 0

; Extended boot record
DriveNumber:            db 0
                        db 0
Signature:              db 0x29
VolumeID:               dd 12345678h
VolumeLabel:            db 'NBOS       '
FileSystemType:         db 'FAT12   '

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov dl, 0x00         ; floppy drive (BIOS gives this usually anyway)
    mov bx, 0x0600       ; load stage 2 to 0x0000:0600
    mov ah, 0x02         ; BIOS read
    mov al, 4            ; Read 4 sectors (tweak as needed)
    mov ch, 0
    mov cl, 2            ; Start at sector 2 (sector 1 is the bootloader)
    mov dh, 0
    int 0x13

    jc disk_error

    mov si, msg_hello
    call puts

    jmp 0x0000:0x0600    ; jump to stage 2

    

puts:
    pusha
.next_char:
    lodsb           ; Load byte at DS:SI into AL, increment SI
    cmp al, 0
    je .done        ; If null terminator, stop
    mov ah, 0x0E
    int 0x10
    jmp .next_char
.done:
    popa
    ret



disk_error:
    mov si, msg
.print:
    lodsb
    or al, al
    jz $
    mov ah, 0x0E
    int 0x10
    jmp .print

msg: db "Stage 2 load fail", 0
msg_hello: db 'Stage 1 OK', 0

times 510 - ($ - $$) db 0
dw 0xAA55
