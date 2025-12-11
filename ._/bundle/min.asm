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
    newline_escape db '\n', 0
    
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
    
    ; Minify the JavaScript
    mov rsi, input_buffer       ; Source pointer
    mov rdi, output_buffer      ; Destination pointer
    mov rcx, r9                 ; Input length
    
    ; State flags
    xor r11, r11                ; r11 = in_string (0=no, 1=single, 2=double, 3=template)
    xor r12, r12                ; r12 = in_comment (0=no, 1=line, 2=block)
    xor r13, r13                ; r13 = last_char_was_space
    xor r14, r14                ; r14 = escape_next (for template strings)
    xor r15, r15                ; r15 = in_expression (for template strings)
    
.minify_loop:
    test rcx, rcx
    jz .minify_done
    
    mov al, [rsi]
    
    ; Check if we're in a string
    test r11, r11
    jnz .handle_string
    
    ; Check if we're in a comment
    test r12, r12
    jnz .handle_comment
    
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
    
    ; Check for end of statement (for adding semicolons)
    cmp al, '}'
    je .handle_brace
    cmp al, '{'
    je .handle_open_brace
    
    ; Skip whitespace (unless it's meaningful)
    cmp al, ' '
    je .handle_space
    cmp al, 0x09                ; Tab
    je .handle_space
    cmp al, 0x0A                ; Newline
    je .handle_newline
    cmp al, 0x0D                ; Carriage return
    je .skip_char
    
    ; Default: copy character
    mov [rdi], al
    inc rdi
    mov r13, 0                  ; Reset space flag
    
.next_char:
    inc rsi
    dec rcx
    jmp .minify_loop

.handle_space:
    ; Only keep space if it separates identifiers
    mov bl, [rsi - 1]
    call .is_alnum
    jc .keep_space
    mov bl, [rsi + 1]
    call .is_alnum
    jc .keep_space
    jmp .skip_char

.keep_space:
    mov byte [rdi], ' '
    inc rdi
    mov r13, 1
    jmp .next_char

.handle_newline:
    ; Replace newline with semicolon if appropriate
    mov bl, [rsi - 1]
    cmp bl, '}'
    je .skip_char
    cmp bl, '{'
    je .skip_char
    cmp bl, ';'
    je .skip_char
    call .is_alnum_or_paren
    jc .add_semicolon
    jmp .skip_char

.add_semicolon:
    mov byte [rdi], ';'
    inc rdi
    jmp .skip_char

.handle_brace:
    ; If we're in a template string expression, handle it
    cmp r15, 1
    je .copy_char_template_context
    ; If we're in a template string but not in expression, it's just a brace
    cmp r11, 3
    je .copy_char_template_context
    mov [rdi], al
    inc rdi
    jmp .next_char

.handle_open_brace:
    ; If we're in a template string and see '{', check for expression start
    cmp r11, 3
    jne .not_template_brace
    ; Check if next char is '$' to see if this is ${expression}
    mov bl, [rsi - 1]
    cmp bl, '$'
    jne .not_template_brace
    ; We have ${ - start of expression
    mov r15, 1
    jmp .copy_char_template_context

.not_template_brace:
    mov [rdi], al
    inc rdi
    jmp .next_char

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
    cmp r11, 3
    je .handle_template_string
    
    ; Handle regular strings (single or double quoted)
    mov [rdi], al
    inc rdi
    
    ; Check for escape sequences
    cmp al, '\'
    je .set_escape_next
    cmp r14, 1
    je .reset_escape_next
    
    ; Check for end of string
    cmp r11, 1
    je .check_single_string_end
    cmp r11, 2
    je .check_double_string_end
    jmp .next_char

.handle_template_string:
    ; Check for escape sequences first
    cmp al, '\'
    je .handle_template_escape
    cmp r14, 1
    je .handle_escaped_char
    
    ; Check for end of template string
    cmp al, '`'
    je .end_template_string
    
    ; Check for expression start ${ in template string
    cmp al, '{'
    je .check_template_expression_start
    
    ; Check for newline in template string
    cmp al, 0x0A
    je .replace_template_newline
    cmp al, 0x0D
    je .skip_char  ; Ignore carriage return in template strings
    
    ; Default: copy character
.copy_char_template_context:
    mov [rdi], al
    inc rdi
    jmp .next_char

.handle_template_escape:
    mov r14, 1
    mov [rdi], al
    inc rdi
    jmp .next_char

.handle_escaped_char:
    mov r14, 0
    mov [rdi], al
    inc rdi
    jmp .next_char

.replace_template_newline:
    ; Replace newline with \n escape sequence in template string
    push rsi
    push rcx
    lea rsi, [newline_escape]
    mov rcx, 2
    rep movsb
    pop rcx
    pop rsi
    jmp .next_char

.check_template_expression_start:
    mov bl, [rsi - 1]
    cmp bl, '$'
    jne .copy_char_template_context
    ; We have ${ - start of expression
    mov r15, 1
    mov [rdi - 1], al  ; Overwrite the $ we just wrote
    mov [rdi], '{'
    add rdi, 1
    jmp .next_char

.end_template_string:
    ; Check if we're in an expression
    cmp r15, 1
    je .handle_expression_brace
    ; End of template string
    mov r11, 0
    mov [rdi], al
    inc rdi
    jmp .next_char

.handle_expression_brace:
    ; If we see '}' while in expression mode, check if it ends the expression
    cmp al, '}'
    jne .copy_char_template_context
    ; End of expression
    mov r15, 0
    mov [rdi], al
    inc rdi
    jmp .next_char

.set_escape_next:
    mov r14, 1
    mov [rdi], al
    inc rdi
    jmp .next_char

.reset_escape_next:
    mov r14, 0
    mov [rdi], al
    inc rdi
    jmp .next_char

.check_single_string_end:
    cmp al, "'"
    jne .next_char
    mov r11, 0
    jmp .next_char

.check_double_string_end:
    cmp al, '"'
    jne .next_char
    mov r11, 0
    jmp .next_char

.check_comment_start:
    mov bl, [rsi + 1]
    cmp bl, '/'
    je .start_line_comment
    cmp bl, '*'
    je .start_block_comment
    ; Not a comment, just a slash
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
    je .end_line_comment
    jmp .skip_char

.end_line_comment:
    mov r12, 0
    ; Don't copy the newline
    jmp .skip_char

.handle_block_comment:
    cmp al, '*'
    jne .skip_char
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
    ; Add null terminator (not strictly needed for file)
    mov byte [rdi], 0
    
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

.error_args:
    mov rax, 1                  ; sys_write
    mov rdi, 2                  ; stderr
    lea rsi, [error_args]
    mov rdx, 37                 ; length
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
    mov rax, 60                 ; sys_exit
    mov rdi, 1                  ; exit code 1
    syscall

; Helper function: check if char in bl is alphanumeric
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

; Helper function: check if char in bl is alphanumeric or paren/brace
.is_alnum_or_paren:
    cmp bl, ')'
    je .is_alnum_or_yes
    cmp bl, ']'
    je .is_alnum_or_yes
    cmp bl, '}'
    je .is_alnum_or_yes
    jmp .is_alnum              ; Reuse alnum check

.is_alnum_or_yes:
    stc
    ret