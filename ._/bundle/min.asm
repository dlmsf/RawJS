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
    
    ; Escape sequences for template strings
    backslash_n db '\n', 0
    
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
    mov rsi, 0                  ; O_RDONLY
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
    
    ; MINIFIER - Simple but correct
    mov rsi, input_buffer       ; Source pointer
    mov rdi, output_buffer      ; Destination pointer
    mov rcx, r9                 ; Input length
    
    ; State flags
    xor r11, r11                ; r11 = in_string (0=no, 1=single, 2=double, 3=template)
    xor r12, r12                ; r12 = in_comment (0=no, 1=line, 2=block)
    xor r13, r13                ; r13 = escape_next (0=no, 1=yes)
    xor r14, r14                ; r14 = last_char_was_space (for ASI)
    
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
    
    ; Handle whitespace
    cmp al, ' '
    je .handle_space
    cmp al, 0x09                ; Tab
    je .handle_space
    cmp al, 0x0A                ; Newline
    je .handle_newline
    cmp al, 0x0D                ; Carriage return
    je .skip_char
    
    ; Not whitespace - copy character
    mov [rdi], al
    inc rdi
    mov r14, 0                  ; Reset space flag
    
.next_char:
    inc rsi
    dec rcx
    jmp .minify_loop

.handle_space:
    ; Only keep space if needed
    cmp rsi, input_buffer
    je .skip_char
    
    mov bl, [rsi - 1]
    call .is_alnum
    jnc .skip_char
    
    cmp rcx, 1
    je .skip_char
    
    mov bl, [rsi + 1]
    call .is_alnum
    jnc .skip_char
    
    ; Keep the space
    mov byte [rdi], ' '
    inc rdi
    mov r14, 1
    jmp .skip_char

.handle_newline:
    ; Check for automatic semicolon insertion
    cmp rsi, input_buffer
    je .skip_char
    
    mov bl, [rsi - 1]
    call .needs_semicolon_before
    jc .add_semicolon
    jmp .skip_char

.add_semicolon:
    mov byte [rdi], ';'
    inc rdi
    jmp .skip_char

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
    ; Check for escape sequence
    cmp r13, 1
    je .handle_escaped_char
    
    ; Check if this starts escape
    cmp al, '\'
    je .start_escape
    
    ; Check for string end
    cmp r11, 1
    je .check_end_single
    cmp r11, 2
    je .check_end_double
    ; Template string
    cmp al, '`'
    jne .check_template_newline
    mov r11, 0
    mov [rdi], al
    inc rdi
    jmp .next_char

.check_end_single:
    cmp al, "'"
    jne .copy_char_string
    mov r11, 0
    jmp .copy_char_string

.check_end_double:
    cmp al, '"'
    jne .copy_char_string
    mov r11, 0
    jmp .copy_char_string

.check_template_newline:
    ; In template strings, newlines become \n
    cmp al, 0x0A
    jne .copy_char_string
    ; Write \n escape sequence
    push rsi
    push rcx
    lea rsi, [backslash_n]
    mov rcx, 2
    rep movsb
    pop rcx
    pop rsi
    jmp .skip_char

.copy_char_string:
    mov [rdi], al
    inc rdi
    jmp .next_char

.start_escape:
    mov r13, 1
    mov [rdi], al
    inc rdi
    jmp .next_char

.handle_escaped_char:
    mov r13, 0
    mov [rdi], al
    inc rdi
    jmp .next_char

.check_comment_start:
    cmp rcx, 1
    je .copy_char_normal
    
    mov bl, [rsi + 1]
    cmp bl, '/'
    je .start_line_comment
    cmp bl, '*'
    je .start_block_comment
    
    ; Not a comment
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
    jne .skip_char
    ; End of line comment
    mov r12, 0
    ; Don't copy the newline
    jmp .skip_char

.handle_block_comment:
    cmp al, '*'
    jne .skip_char
    cmp rcx, 1
    je .skip_char
    mov bl, [rsi + 1]
    cmp bl, '/'
    jne .skip_char
    ; End of block comment
    mov r12, 0
    add rsi, 2
    sub rcx, 2
    jmp .minify_loop

.skip_char:
    inc rsi
    dec rcx
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

; Helper functions
.is_alnum:
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

.needs_semicolon_before:
    ; Check if character in bl needs a semicolon before newline
    cmp bl, '}'
    je .no_semicolon_needed
    cmp bl, '{'
    je .no_semicolon_needed
    cmp bl, ';'
    je .no_semicolon_needed
    cmp bl, ':'
    je .no_semicolon_needed
    call .is_alnum
    jc .semicolon_needed
    cmp bl, ')'
    je .semicolon_needed
    cmp bl, ']'
    je .semicolon_needed
.no_semicolon_needed:
    clc
    ret
.semicolon_needed:
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
