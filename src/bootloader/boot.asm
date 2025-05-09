org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

jmp short start
nop

; BIOS Parameter Block (BPB)
bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512                 ; Changed from db to dw
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 224
bdb_total_sectors:          dw 2880
bdb_media_descriptor_type:  db 0F0h
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; Extended Boot Record
ebr_drive_number:           db 0
                            db 0                    ; Reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h  ; Serial number
ebr_volume_label:           db 'NBOS       '       ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '          ; 8 bytes

start:
    jmp main

puts:
    push si
    push ax
    push bx         ; BIOS call modifies BH

.loop:
    lodsb           ; Load next character
    or al, al       ; Check for null terminator
    jz .done

    mov ah, 0x0E    ; BIOS teletype output
    mov bh, 0       ; Page number
    int 0x10
    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret

main:
    ; Initialize segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Set up stack
    mov ss, ax
    mov sp, 0x7C00  ; Stack grows downward from 0x7C00

    ; Save drive number
    mov [ebr_drive_number], dl
    
    ; Print message
    mov si, msg_hello
    call puts

    mov si, msg_attempt_read
    call puts

    mov ax, 1
    mov cl, 1
    mov bx, 0x7E00
    call disk_read

    mov si, msg_read_ok
    call puts

    ; Verify the read data by checking first few bytes
    mov si, 0x7E00
    mov cx, 8       ; Check 8 bytes
    call hex_dump   ; New function to display memory    

    cli
    hlt

floppy_error:

    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h
    jmp 0FFFFh:0


.halt:
    cli
    hlt


lba_to_chs:

    push ax
    push dx

    xor dx, dx
    div word [bdb_sectors_per_track] ; Divide LBA by sectors per track

    inc dx
    mov cx, dx

    xor dx, dx
    div word [bdb_heads]             ; Divide LBA by heads


    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah

    pop ax
    mov dl, al
    pop ax
    ret


disk_read:

    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax
    mov ah, 02h
    mov di, 3

.retry:
    pusha
    stc
    int 13h
    jnc .done
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

; Dumps memory in hex
; Input:
;   SI = memory address
;   CX = number of bytes to dump
hex_dump:
    pusha
    mov ah, 0x0E    ; BIOS teletype
    
.dump_loop:
    lodsb           ; Load byte from [SI] into AL
    push ax
    
    ; High nibble
    shr al, 4
    call .nibble_to_ascii
    int 0x10
    
    ; Low nibble
    pop ax
    and al, 0x0F
    call .nibble_to_ascii
    int 0x10
    
    ; Space between bytes
    mov al, ' '
    int 0x10
    
    loop .dump_loop
    
    ; Newline
    mov al, 0x0D    ; CR
    int 0x10
    mov al, 0x0A    ; LF
    int 0x10
    
    popa
    ret
    
.nibble_to_ascii:
    cmp al, 9
    jbe .digit
    add al, 7       ; 'A'-'0'-10 = 7
.digit:
    add al, '0'
    ret
    
msg_attempt_read: db 'Attempting disk read...', ENDL, 0
msg_read_ok: db 'Disk read successful!', ENDL, 0
msg_hello: db 'Hello World!', ENDL, 0
msg_read_failed: db 'Disk read failed!', ENDL, 0

; Boot signature
times 510-($-$$) db 0
dw 0xAA55          ; Little-endian boot signature