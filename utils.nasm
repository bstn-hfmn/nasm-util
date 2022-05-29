section .data
    newline: db 0x0A, 0

section .text
global _start
_start:

    mov rax, 60
    mov rdi, 0
    syscall

;---------------------------------------------------------------------------------------------------
; ftoa
;   @brief Converts a single percision floating point value to a sequence of ASCII encoded characters.
;          (Assumes availability of SIMD)
;   
;   @arg `value`    {edi} <int32>: Value to convert.
;   @arg `buffer`   {rsi} <void*>: Pointer to the beginning of the character sequence.
;   
;   @ret              {-}       <->: -
;===================================================================================================
ftoa:
    test        edi, 0x80000000                             ; if !signed 
    jz          ftoa.unsigned                               ; if !signed

    xor         edi, 0x80000000
    mov         byte [rsi], '-'
    inc         rsi

.unsigned:
    movd        xmm0, edi                                   ; %xmm0 = $value
    cvttss2si   ecx, xmm0                                   ; %ecx  = (int)$value

    mov         edi, ecx
    call        itoa                                        ; %rax = $strlen

    mov         byte [rsi+rax], '.'                         ; $buffer[$strlen] = '.'
    inc         rax                                         ; ++$strlen
    mov         r10, rax                                    ; %r10 = $strlen

    cvtsi2ss    xmm1, ecx                                   ; %xmm1 = (float)((int)$value)
    subss       xmm0, xmm1                                  ; %xmm0 = $value - ((int)$value)

    mov         edx, __float32__(100000.0)
    movd        xmm1, edx                                   ; %xmm1 =  100000.0
    mulss       xmm0, xmm1                                  ; %xmm0 *= 100000.0
    
    cvtss2si    ecx, xmm0                                   ; $fraction = (int)(%xmm0)

    mov         r11d, 10
    mov         ebx, 10000                                  ; $divisor
.fraction:
    xor         edx, edx                                    ; %edx = 0
    mov         eax, ecx                                    ; %eax = $fraction
    idiv        ebx                                         ; %edx:$fraction / $divisor

    xor         edx, edx                                    ; %edx = 0
    idiv        r11d                                        ; %edx:($fraction / $divisor) / 10

    add         dl, '0'                                     ; %edx[0..7] + '0'
    mov         byte [rsi+r10], dl                          ; *($buffer + $strlen) = %dl
    inc         r10                                         ; ++$strlen

    xor         edx, edx
    mov         eax, ebx                                    ; %eax = $divisor
    idiv        r11d                                        ; %edx:$divisor / 10
    mov         ebx, eax                                    ; $divisor /= 10

    cmp         ebx, 0                                      ; if $divisor == 0
    jz          ftoa.trailing                               ; if $divisor == 0
    jmp         ftoa.fraction                               ; while $divisor != 0

.trailing:
    mov         dl, byte [rsi+(r10-1)]                      ; %dl = $buffer[$strlen-1]
    cmp         dl, '0'                                     ; if %dl != '0'
    jnz         ftoa.end                                    ; if %dl != '0'

    dec         r10                                         ; --$strlen
    jmp         ftoa.trailing                               ; while %dl == '0'

.end:
    mov         byte [rsi+r10], 0
    ret


;---------------------------------------------------------------------------------------------------
; strlen
;   @brief Computes the length of a null-terminated character sequence.
;
;   @arg `buffer`   {rdi} <void*>: Pointer to the beginning of the character sequence.
;   @ret            {rax} <int64>: length of the string.
;===================================================================================================
strlen:
    test    rdi, rdi                                        ; if $buffer == 0
    jz      strlen.invalid                                  ; if $buffer == 0
    
    xor     rdx, rdx                                        ; $current  = 0
    xor     rax, rax                                        ; $length   = 0
.loop:
    inc     rax                                             ; ++$length
    mov     dl, byte [rdi+rax]                              ; $current = *($buffer+$length) 
    cmp     dl, 0                                           ; if (*($buffer+$length)) == 0
    jnz     strlen.loop
    
    ret

.invalid:
    mov     rax, 0
    ret

;---------------------------------------------------------------------------------------------------
; atoi
;   @brief Converts a sequence of ASCII encoded characters into a number.
;
;   @arg `buffer`   {rdi} <void*>: Pointer to the buffer, which will store the resulting sequence.
;   @ret            {rax} <int64>: The resulting number.
;===================================================================================================
atoi:
    call    strlen                                      ; $index = %rax
    test    rax, rax
    jz      atoi.zero                                   ; if strlen(%rdi) == 0

    dec     rax                                         ; --$index
    mov     r10, 1                                      ; $multiplier = 1
    xor     r11, r11                                    ; $result  = 0
.loop:
    cmp     byte [rdi+rax], '-'                         ; if (*($buffer + $index)) == '-'
    je      atoi.signed                                 ; if (*($buffer + $index)) == '-'

    cmp     byte [rdi+rax], '0'                         ; if (*($buffer + $index)) - 0x30 < 0
    jl      atoi.end                                    ; if (*($buffer + $index)) - 0x30 < 0
    
    cmp     byte [rdi+rax], '9'                         ; if (*($buffer + $index)) - 0x39 < 0
    jg      atoi.end                                    ; if (*($buffer + $index)) - 0x39 < 0

    xor     r12, r12                                    ; $current  = 0
    mov     r12b, byte [rdi+rax]                        ; $current  = *($buffer + $index)
    sub     r12b, '0'                                   ; $current -= 0x30

    imul    r12, r10                                    ; $current *= $multiplier
    add     r11, r12                                    ; $result += $current
    imul    r10, 10                                     ; $multipler *= 10

    sub     rax, 1                                      ; $index -= 1
    js      atoi.end                                    ; if $index < 0

    jmp     atoi.loop

.signed:
    neg     r11                                         ; 0 - $result
.end:
    mov     rax, r11                                    ; return $result
    ret

.zero:
    mov     rax, 0
    ret


;---------------------------------------------------------------------------------------------------
; itoa
;   @brief Converts an integer to a sequence of ASCII encoded characters.
;
;   @arg `value`    {rdi} <int64>: Integer value.
;   @arg `buffer`   {rsi} <void*>: Pointer to the buffer, which will store the resulting sequence.
;
;   @ret            {rax} <int64>: length of the string.
;===================================================================================================
itoa:
    test    rdi, rdi                                        ; if $value == 0
    jz      itoa.zero                                       ; if $value == 0
    
    push    rdi
    push    rsi
    push    rcx

    lea     r8, [rsi+0x00]                                  ; $original = $buffer
    jns     itoa.unsigned                                   ; if ($value & 0x8000000000000000) == 0

    mov     byte [rsi], '-'                                 ; *$buffer = '-'
    inc     rsi                                             ; ++$buffer

    not     rdi                                             ; ----- ↓ -----
    add     rdi, 1                                          ; $value = (~$value) + 1

.unsigned:
    
    xor     rcx, rcx                                        ; $counter
    mov     rbx, 1000000000000000000                        ; $divisor
    mov     r10, 10
.loop:
    test    rbx, rbx                                        ; if $divisor == 0
    jz      itoa.end                                        ; if $divisor == 0

    mov     rax, rdi                                        ; %rax = $value (divident/quotient)
    xor     rdx, rdx                                        ; %rdx = 0      (remainder)
    idiv    rbx                                             ; %rdx:%rax / $divisor

    inc     rcx                                             ; ++$counter
    cmp     rcx, 20                                         ; if $counter >= 20
    jge     itoa.end                                        ; if $counter >= 20
    
    test    rax, rax                                        ; if %rax == 0
    jz      itoa.advance                                    ; if %rax == 0

    xor     rdx, rdx                                        ; %rdx = 0 (remainder)
    idiv    r10                                             ; %rdx:%rax / 10
                                                            ; %rdx = ($value / $divisor) % 10

    add     dl, '0'                                         ; %rdx[0..7] + '0'
    mov     byte [rsi], dl                                  ; *$buffer = %rdx[0..7]
    inc     rsi                                             ; ++$buffer

.advance:
    mov     rax, rbx                                        ; %rax = $divisor   (divident/quotient)
    xor     rdx, rdx                                        ; %rdx = 0          (remainder)
    idiv    r10                                             ; %rdx:$divisor / 10

    mov     rbx, rax                                        ; $divisor = %rax
                                                            ; $divisor /= 10
    jmp     itoa.loop

.end:
    mov     byte [rsi], 0                                   ; *$buffer = 0
    
    mov     r9, rsi                                         ; %r9 = $buffer
    sub     r9, r8                                          ; %r9 -= $original

    mov     rax, r9                                         ; %rax = %r9

    pop     rcx
    pop     rsi
    pop     rdi

    ret

.zero:
    mov     rax, 1
    mov     byte [rsi+0x00], 0x30                           ; (*($buffer + 0)) = 0x30
    mov     byte [rsi+0x01], 0x00
    ret


;---------------------------------------------------------------------------------------------------
; readln
;   @brief Reads a sequence of ASCII characters from STDIN, including the line-feed.
;
;   @arg `buffer`   {rdi} <void*>: Where the read value shall be stored.
;   @ret              {-}     <->: -
;===================================================================================================
readln:
    mov     rsi, rdi                                        ; $buf = $buffer
    mov     rax, 0                                          ; %rax = syscall:read
    mov     rdi, 1                                          ; $fd  = 0x01
    mov     rdx, 1024                                       ; $count = 1024

    syscall
    ret

;---------------------------------------------------------------------------------------------------
; write
;   @brief Writes provided character sequence and to STDOUT.
;
;   @arg `buffer`   {rdi} <void*>: Pointer to the beginning of the character sequence.
;   @ret              {-}     <->: -
;===================================================================================================
write:
    call    strlen

    mov     rsi, rdi                                        ; $buf = $buffer
    mov     rdi, 0                                          ; $fd  = 0x00
    mov     rdx, rax                                        ; $count = %rax
    mov     rax, 1                                          ; %rax = syscall:write
    syscall

    ret

;---------------------------------------------------------------------------------------------------
; writeln
;   @brief Writes provided character sequence and a additional line feed to STDOUT.
;
;   @arg `buffer`   {rdi} <void*>: Pointer to the beginning of the character sequence.
;   @ret              {-}     <->: -
;===================================================================================================
writeln:
    call    write

    lea     rdi, [newline+0x00]
    call    write

    ret

;---------------------------------------------------------------------------------------------------
; writei
;   @brief Converts a integer and writes it to STDOUT.
;
;   @arg `value`    {rdi} <int64>: The number to write.
;   @ret              {-}     <->: -
;===================================================================================================
writei:
    sub     rsp, 32                                         ; byte $buffer[32]
    mov     rsi, rsp                                        ; %rsi = $buffer
    call itoa

    mov     rdi, rsp                                        ; %rdi = $buffer
    call write

    add     rsp, 32
    ret