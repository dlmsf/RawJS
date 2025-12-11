section .data
    ; Error messages
    error_args db 'Usage: ./minify input.js [output.js]', 0x0A, 0
    error_open_input db 'Error: Cannot open input file', 0x0A, 0
    error_open_output db 'Error: Cannot open output file', 0x0A, 0
    error_read db 'Error: Cannot read input file', 0x0A, 0
    error_write db 'Error: Cannot write output file', 0x0A, 0
    
    ; Default output filename
    default_output db 'output.js', 0
    
    ; Buffers
    input_buffer times 65536 db 0
    output_buffer times 65536 db 0
    
section .text
    global _start

_start:
    ; Get command line arguments
    pop rcx                     ; argc
    cmp rcx, 2
    jl .error_args              ; Need at least input file
    cmp rcx, 3
    jg .error_args              ; Max 3 args
    
    ; Get input filename
    pop rdi                     ; Skip program name
    pop rdi                     ; First arg (input file)
    
    ; Open input file
    mov rax, 2                  ; sys_open
    mov rsi, 0                  ; O_RONLY
    syscall
    cmp rax, 0
    jl .error_open_input
    mov r8, rax                 ; Save input file descriptor
    
    ; Read input file
    mov rdi, rax                ; fd
    mov rax, 0                  ; sys_read
    mov rsi, input_buffer
    mov rdx, 65536
    syscall
    cmp rax, 0
    jl .error_read
    mov r9, rax                 ; Save input length
    
    ; Close input file
    mov rax, 3                  ; sys_close
    mov rdi, r8
    syscall
    
    ; Check if output filename provided
    pop rcx                     ; Check if there's another arg
    test rcx, rcx
    jz .use_default_output
    
    mov rdi, rcx                ; Use provided output filename
    jmp .open_output
    
.use_default_output:
    lea rdi, [default_output]
    
.open_output:
    ; Open/Create output file
    mov rax, 2                  ; sys_open
    mov rsi, 0x241              ; O_CREAT|O_WRONLY|O_TRUNC
    mov rdx, 0o644              ; Permissions
    syscall
    cmp rax, 0
    jl .error_open_output
    mov r10, rax                ; Save output file descriptor
    
    ; ULTRA-SIMPLE MINIFIER
    ; Just removes whitespace and comments, but preserves everything else
    mov rsi, input_buffer       ; Source pointer
    mov rdi, output_buffer      ; Destination pointer
    mov rcx, r9                 ; Input length
    
    ; Simple state flags
    xor r11, r11                ; r11 = in_string (0=no, 1=single, 2=double, 3=template)
    xor r12, r12                ; r12 = in_comment (0=no, 1=line, 2=block)
    xor r13, r13                ; r13 = escape_next (0=no, 1=yes)
    
.minify_loop:
    test rcx, rcx
    jz .minify_done
    
    mov al, [rsi]
    
    ; Check if we're in a comment
    test r12, r12
    jnz .handle_comment
    
    ; Check if we're in a string
    test r11, r11
    jnz .handle_string
    
    ; Check for start of string
    cmp al, "'"
    je .start_single_string
    cmp al, '"'
    je .start_double_string
    cmp al, '`'
    je .start_template_string
    
    ; Check for start of comment
    cmp al, '/'
    je .check_comment_start
    
    ; Remove whitespace (but be careful)
    cmp al, ' '
    je .maybe_remove_space
    cmp al, 0x09                ; Tab
    je .remove_char
    cmp al, 0x0A                ; Newline
    je .remove_char
    cmp al, 0x0D                ; Carriage return
    je .remove_char
    
    ; Keep all other characters
    mov [rdi], al
    inc rdi
    
.next_char:
    inc rsi
    dec rcx
    jmp .minify_loop

.maybe_remove_space:
    ; Check if space separates two identifiers
    cmp rsi, input_buffer
    je .remove_char  ; Can't be first char
    
    cmp rcx, 1
    je .remove_char  ; Can't be last char
    
    ; Check characters around the space
    mov bl, [rsi - 1]
    mov dl, [rsi + 1]
    
    ; Keep space only if it separates alnum characters
    call .is_alnum_or_dot
    jnc .remove_char  ; Left not alnum
    
    push rbx
    mov bl, dl
    call .is_alnum_or_dot
    pop rbx
    jnc .remove_char  ; Right not alnum
    
    ; Keep the space
    mov byte [rdi], ' '
    inc rdi
    jmp .remove_char

.remove_char:
    inc rsi
    dec rcx
    jmp .minify_loop

.start_single_string:
    mov r11, 1
    mov [rdi], al
    inc rdi
    jmp .next_char

.start_double_string:
    mov r11, 2
    mov [rdi], al
    inc rdi
    jmp .next_char

.start_template_string:
    mov r11, 3
    mov [rdi], al
    inc rdi
    jmp .next_char

.handle_string:
    ; Copy string character
    mov [rdi], al
    inc rdi
    
    ; Check for escape sequences
    cmp r13, 1
    je .reset_escape
    
    ; Check if this starts an escape sequence
    cmp al, '\'
    je .set_escape
    jmp .check_string_end

.set_escape:
    mov r13, 1
    jmp .next_char

.reset_escape:
    mov r13, 0
    jmp .next_char

.check_string_end:
    ; Check if this ends the string (but not if escaped)
    cmp r11, 1
    je .check_single_end
    cmp r11, 2
    je .check_double_end
    ; Template string
    cmp al, '`'
    jne .next_char
    mov r11, 0
    jmp .next_char

.check_single_end:
    cmp al, "'"
    jne .next_char
    mov r11, 0
    jmp .next_char

.check_double_end:
    cmp al, '"'
    jne .next_char
    mov r11, 0
    jmp .next_char

.check_comment_start:
    cmp rcx, 1
    je .copy_char_normal  ; Last character, can't be comment
    
    mov bl, [rsi + 1]
    cmp bl, '/'
    je .start_line_comment
    cmp bl, '*'
    je .start_block_comment
    
    ; Not a comment, just a slash
.copy_char_normal:
    mov [rdi], al
    inc rdi
    jmp .next_char

.start_line_comment:
    mov r12, 1
    add rsi, 2
    sub rcx, 2
    jmp .minify_loop

.start_block_comment:
    mov r12, 2
    add rsi, 2
    sub rcx, 2
    jmp .minify_loop

.handle_comment:
    cmp r12, 1
    je .handle_line_comment
    cmp r12, 2
    je .handle_block_comment
    jmp .next_char

.handle_line_comment:
    cmp al, 0x0A
    jne .skip_char_in_comment
    ; End of line comment
    mov r12, 0
.skip_char_in_comment:
    inc rsi
    dec rcx
    jmp .minify_loop

.handle_block_comment:
    cmp al, '*'
    jne .skip_char_in_comment
    cmp rcx, 1
    je .skip_char_in_comment
    mov bl, [rsi + 1]
    cmp bl, '/'
    jne .skip_char_in_comment
    ; End of block comment
    mov r12, 0
    add rsi, 2
    sub rcx, 2
    jmp .minify_loop

.minify_done:
    ; Calculate output length
    mov r11, rdi
    lea rdi, [output_buffer]
    sub r11, rdi                ; r11 = output length
    
    ; Write output file
    mov rax, 1                  ; sys_write
    mov rdi, r10                ; output fd
    mov rsi, output_buffer
    mov rdx, r11
    syscall
    cmp rax, 0
    jl .error_write
    
    ; Close output file
    mov rax, 3                  ; sys_close
    mov rdi, r10
    syscall
    
    ; Exit successfully
    mov rax, 60                 ; sys_exit
    xor rdi, rdi                ; exit code 0
    syscall

; Helper function: check if char in bl is alnum or dot
.is_alnum_or_dot:
    cmp bl, '.'
    je .is_alnum_yes
    cmp bl, '0'
    jb .not_alnum
    cmp bl, '9'
    jbe .is_alnum_yes
    cmp bl, 'A'
    jb .not_alnum
    cmp bl, 'Z'
    jbe .is_alnum_yes
    cmp bl, 'a'
    jb .not_alnum
    cmp bl, 'z'
    jbe .is_alnum_yes
    cmp bl, '_'
    je .is_alnum_yes
    cmp bl, '$'
    je .is_alnum_yes
.not_alnum:
    clc
    ret
.is_alnum_yes:
    stc
    ret

; Error handlers
.error_args:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_args]
    mov rdx, 37
    syscall
    jmp .exit_error

.error_open_input:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_open_input]
    mov rdx, 32
    syscall
    jmp .exit_error

.error_open_output:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_open_output]
    mov rdx, 33
    syscall
    jmp .exit_error

.error_read:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_read]
    mov rdx, 30
    syscall
    jmp .exit_error

.error_write:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_write]
    mov rdx, 31
    syscall
    jmp .exit_error

.exit_error:
    mov rax, 60
    mov rdi, 1
    syscall
