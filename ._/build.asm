section .data
    ; Colors for output - alternating colors
    reset_color_str   db 0x1B, "[0m", 0
    color1           db 0x1B, "[1;33m", 0  ; Bright yellow
    color2           db 0x1B, "[1;36m", 0  ; Bright cyan
    color3           db 0x1B, "[1;32m", 0  ; Bright green
    color4           db 0x1B, "[1;35m", 0  ; Bright magenta
    
    ; Tags for JavaScript instances
    js_start_tag     db "<js-start>", 0
    js_end_tag       db "<js-end>", 10, 0   ; Newline after closing tag
    
    ; Error messages
    err_no_file       db "Error: No input file specified.", 10, 0
    err_open          db "Error: Could not open file.", 10, 0
    err_read          db "Error: Could not read file.", 10, 0
    
    ; Output formatting
    newline           db 10, 0
    tab               db "    ", 0
    
    ; State tracking
    in_string         db 0
    in_template       db 0
    in_comment        db 0
    paren_depth       dd 0
    brace_depth       dd 0
    last_char         db 0
    skip_next_space   db 0
    in_block          db 0
    block_started     db 0
    
    ; Color rotation
    color_index       dd 0
    color_array       dq color1, color2, color3, color4
    
    ; Buffers
    current_stmt      times 1024 db 0
    char_buffer       db 0
    stmt_started      db 0
    current_color     dq 0
    
section .bss
    file_handle       resq 1
    file_size         resq 1
    file_buffer       resb 65536
    
section .text
    global _start

; ------------------------------------------------------------
; START OF PROGRAM
; ------------------------------------------------------------
_start:
    ; Get command line arguments
    pop rcx                 ; Get argc
    cmp rcx, 2
    jl .no_file
    
    pop rdi                 ; Skip program name
    pop rdi                 ; Get filename
    
    ; Open the file
    mov rax, 2              ; sys_open
    mov rsi, 0              ; O_RDONLY
    syscall
    cmp rax, 0
    jl .open_error
    mov [file_handle], rax
    
    ; Get file size
    mov rax, 8              ; sys_lseek
    mov rdi, [file_handle]
    mov rsi, 0
    mov rdx, 2              ; SEEK_END
    syscall
    mov [file_size], rax
    
    ; Reset to beginning
    mov rax, 8              ; sys_lseek
    mov rdi, [file_handle]
    mov rsi, 0
    mov rdx, 0              ; SEEK_SET
    syscall
    
    ; Read entire file
    mov rax, 0              ; sys_read
    mov rdi, [file_handle]
    mov rsi, file_buffer
    mov rdx, [file_size]
    syscall
    cmp rax, 0
    jl .read_error
    
    ; Close file
    mov rax, 3              ; sys_close
    mov rdi, [file_handle]
    syscall
    
    ; Process the file
    call process_file
    
    ; Exit
    jmp .exit

.no_file:
    mov rsi, err_no_file
    call print_string
    mov rax, 1
    jmp .exit_error

.open_error:
    mov rsi, err_open
    call print_string
    mov rax, 2
    jmp .exit_error

.read_error:
    mov rsi, err_read
    call print_string
    mov rax, 3

.exit_error:
    mov rdi, rax
    jmp .exit_now

.exit:
    mov rdi, 0

.exit_now:
    mov rax, 60             ; sys_exit
    syscall

; ------------------------------------------------------------
; GET NEXT COLOR - Rotates through colors
; ------------------------------------------------------------
get_next_color:
    push rbx
    
    ; Get current color index
    mov ebx, [color_index]
    
    ; Get color from array
    mov rax, [color_array + rbx*8]
    mov [current_color], rax
    
    ; Increment index and wrap around (4 colors)
    inc ebx
    cmp ebx, 4
    jl .no_wrap
    xor ebx, ebx
.no_wrap:
    mov [color_index], ebx
    
    pop rbx
    ret

; ------------------------------------------------------------
; PROCESS FILE - Main processing loop
; ------------------------------------------------------------
process_file:
    push rbx
    push r12
    push r13
    
    mov r12, file_buffer    ; Current position in file
    mov r13, file_buffer
    add r13, [file_size]    ; End of file
    
    ; Initialize state
    mov dword [paren_depth], 0
    mov dword [brace_depth], 0
    mov byte [in_string], 0
    mov byte [in_template], 0
    mov byte [in_comment], 0
    mov byte [stmt_started], 0
    mov byte [last_char], 0
    mov byte [skip_next_space], 0
    mov byte [in_block], 0
    mov byte [block_started], 0
    mov dword [color_index], 0
    
    ; Get first color
    call get_next_color
    
    ; Clear statement buffer
    call clear_stmt_buffer
    
.process_loop:
    cmp r12, r13
    jge .process_done
    
    ; Get current character
    mov al, [r12]
    mov [char_buffer], al
    inc r12
    
    ; Skip whitespace at beginning of statement
    cmp byte [stmt_started], 0
    jne .not_start_whitespace
    
    cmp al, ' '
    je .skip_char
    cmp al, 9      ; Tab
    je .skip_char
    cmp al, 10     ; Newline
    je .skip_char
    cmp al, 13     ; Carriage return
    je .skip_char
    
    mov byte [stmt_started], 1
    
.not_start_whitespace:
    ; Check if we're inside a string
    cmp byte [in_string], 1
    je .handle_string_char
    
    ; Check if we're inside a template literal
    cmp byte [in_template], 1
    je .handle_template_char
    
    ; Check if we're inside a comment
    cmp byte [in_comment], 1
    je .handle_single_comment
    cmp byte [in_comment], 2
    je .handle_multi_comment
    
    ; Check for start of string
    cmp al, '"'
    je .start_string
    
    ; Check for start of template literal
    cmp al, '`'
    je .start_template
    
    ; Check for start of comment
    cmp al, '/'
    je .check_comment
    
    ; Handle spaces - only add one space between tokens
    cmp al, ' '
    je .handle_space
    
    ; Handle tabs
    cmp al, 9
    je .handle_space
    
    ; Handle newlines
    cmp al, 10
    je .handle_newline
    cmp al, 13
    je .handle_newline
    
    ; Check for statement boundaries
    cmp al, ';'
    je .handle_semicolon
    
    ; Check for braces
    cmp al, '{'
    je .open_brace
    cmp al, '}'
    je .close_brace
    
    ; Check for parentheses
    cmp al, '('
    je .open_paren
    cmp al, ')'
    je .close_paren
    
    ; Reset skip space flag (we found a non-space)
    mov byte [skip_next_space], 0
    
    ; Add character to statement buffer
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    jmp .process_loop

.skip_char:
    jmp .process_loop

.start_string:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; Add quote to statement buffer
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Set string flag
    mov byte [in_string], 1
    jmp .process_loop

.start_template:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; Add backtick to statement buffer
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Set template flag
    mov byte [in_template], 1
    jmp .process_loop

.check_comment:
    ; Check if this is a comment start
    cmp r12, r13
    jge .not_comment
    
    mov bl, [r12]
    cmp bl, '/'
    je .start_single_comment
    cmp bl, '*'
    je .start_multi_comment
    
.not_comment:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; Just a regular slash
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    jmp .process_loop

.start_single_comment:
    ; Skip second slash
    inc r12
    mov byte [in_comment], 1
    jmp .process_loop

.start_multi_comment:
    ; Skip asterisk
    inc r12
    mov byte [in_comment], 2
    jmp .process_loop

.handle_string_char:
    ; Add character to statement
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Check for string end
    cmp al, '"'
    jne .process_loop
    
    ; Check for escaped quote
    cmp byte [r12-2], '\'
    je .process_loop
    
    ; End of string
    mov byte [in_string], 0
    jmp .process_loop

.handle_template_char:
    ; Add character to statement
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Check for template end
    cmp al, '`'
    jne .process_loop
    
    ; Check for escaped backtick
    cmp byte [r12-2], '\'
    je .process_loop
    
    ; End of template
    mov byte [in_template], 0
    jmp .process_loop

.handle_single_comment:
    ; Check for newline (end of comment)
    cmp al, 10
    jne .process_loop
    
    mov byte [in_comment], 0
    jmp .process_loop

.handle_multi_comment:
    ; Check for comment end
    cmp al, '*'
    jne .process_loop
    
    cmp r12, r13
    jge .process_loop
    
    mov bl, [r12]
    cmp bl, '/'
    jne .process_loop
    
    ; Skip the slash
    inc r12
    mov byte [in_comment], 0
    jmp .process_loop

.handle_space:
    ; Check if we should skip this space
    cmp byte [skip_next_space], 1
    je .process_loop
    
    ; Don't add space after certain characters
    mov bl, [last_char]
    cmp bl, '('
    je .process_loop
    cmp bl, '['
    je .process_loop
    cmp bl, '{'
    je .process_loop
    cmp bl, ';'
    je .process_loop
    cmp bl, ':'
    je .process_loop
    cmp bl, ','
    je .process_loop
    
    ; Add single space
    call append_to_stmt
    mov byte [skip_next_space], 1
    mov byte [last_char], ' '
    jmp .process_loop

.handle_newline:
    ; Set flag to skip next spaces
    mov byte [skip_next_space], 1
    jmp .process_loop

.open_brace:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; First, check if we're already in a block
    cmp byte [in_block], 1
    je .add_brace_to_stmt
    
    ; We're starting a new block
    mov byte [in_block], 1
    mov byte [block_started], 1
    
.add_brace_to_stmt:
    ; Add brace to current statement
    mov al, '{'
    mov [char_buffer], al
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Update brace depth
    inc dword [brace_depth]
    jmp .process_loop

.close_brace:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; Add closing brace to statement
    mov al, '}'
    mov [char_buffer], al
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Update brace depth
    dec dword [brace_depth]
    
    ; Check if we're ending a block
    cmp dword [brace_depth], 0
    jne .process_loop
    
    ; We've returned to brace depth 0 - end of block
    mov byte [in_block], 0
    call print_current_statement
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    mov byte [block_started], 0
    
    ; Get new color for next statement
    call get_next_color
    
    jmp .process_loop

.open_paren:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; Add to statement buffer
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Update parenthesis depth
    inc dword [paren_depth]
    jmp .process_loop

.close_paren:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; Add to statement buffer
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; Update parenthesis depth
    dec dword [paren_depth]
    jmp .process_loop

.handle_semicolon:
    ; Reset skip space flag
    mov byte [skip_next_space], 0
    
    ; Add semicolon to statement
    call append_to_stmt
    
    ; Store as last character
    mov [last_char], al
    
    ; CRITICAL FIX: Only print if:
    ; 1. We're at top level (brace_depth = 0) AND
    ; 2. We're not inside parentheses (paren_depth = 0) AND  
    ; 3. We're not inside a block (in_block = 0)
    cmp dword [brace_depth], 0
    jne .process_loop
    cmp dword [paren_depth], 0
    jne .process_loop
    cmp byte [in_block], 0
    jne .process_loop
    
    ; This is a top-level statement outside any block or parentheses
    call print_current_statement
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    
    ; Get new color for next statement
    call get_next_color
    
    jmp .process_loop

.process_done:
    ; Print any remaining statement
    mov rsi, current_stmt
    call string_length
    test rax, rax
    jz .done
    
    call print_current_statement
    
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------
; PRINT CURRENT STATEMENT - Prints with proper formatting and alternating colors
; Now includes <js-start> and <js-end> tags with matching colors
; ------------------------------------------------------------
print_current_statement:
    push rbx
    push rsi
    push rdi
    push rcx
    
    ; Check if statement is empty
    mov rsi, current_stmt
    call string_length
    test rax, rax
    jz .done
    
    ; Trim trailing spaces
    call trim_trailing_spaces
    
    ; Use current color for both tags and content
    mov rbx, [current_color]
    
    ; Print opening tag with current color
    mov rsi, rbx
    call print_string
    
    mov rsi, js_start_tag
    call print_string
    
    ; Reset color after opening tag
    mov rsi, reset_color_str
    call print_string
    
    ; Print a space after opening tag for readability
    mov rsi, tab
    call print_string
    
    ; Print statement content with current color
    mov rsi, rbx
    call print_string
    
    mov rsi, current_stmt
    call print_string
    
    ; Reset color before closing tag
    mov rsi, reset_color_str
    call print_string
    
    ; Print a space before closing tag for readability
    mov rsi, tab
    call print_string
    
    ; Print closing tag with current color
    mov rsi, rbx
    call print_string
    
    mov rsi, js_end_tag
    call print_string
    
    ; Reset color (closing tag already has newline)
    mov rsi, reset_color_str
    call print_string

.done:
    pop rcx
    pop rdi
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------
; TRIM TRAILING SPACES - Removes spaces from end of statement
; ------------------------------------------------------------
trim_trailing_spaces:
    push rdi
    push rsi
    push rcx
    
    mov rdi, current_stmt
    call string_length
    test rax, rax
    jz .done
    
    mov rsi, current_stmt
    add rsi, rax
    dec rsi
    
.trim_loop:
    cmp rsi, current_stmt
    jl .done
    
    mov al, [rsi]
    cmp al, ' '
    je .remove_space
    cmp al, 9      ; Tab
    je .remove_space
    jmp .done
    
.remove_space:
    mov byte [rsi], 0
    dec rsi
    jmp .trim_loop

.done:
    pop rcx
    pop rsi
    pop rdi
    ret

; ------------------------------------------------------------
; APPEND TO STATEMENT - Adds character to statement buffer
; ------------------------------------------------------------
append_to_stmt:
    push rdi
    push rcx
    
    ; Find end of current statement
    mov rdi, current_stmt
    xor rcx, rcx
    
.find_end:
    cmp byte [rdi + rcx], 0
    je .found_end
    inc rcx
    cmp rcx, 1023
    jge .overflow
    jmp .find_end

.found_end:
    ; Append character
    mov al, [char_buffer]
    mov [rdi + rcx], al
    inc rcx
    mov byte [rdi + rcx], 0
    
.overflow:
    pop rcx
    pop rdi
    ret

; ------------------------------------------------------------
; CLEAR STATEMENT BUFFER
; ------------------------------------------------------------
clear_stmt_buffer:
    push rdi
    push rcx
    
    mov rdi, current_stmt
    xor rcx, rcx
    mov al, 0
    
.clear_loop:
    cmp rcx, 1024
    jge .done
    mov [rdi + rcx], al
    inc rcx
    jmp .clear_loop
    
.done:
    pop rcx
    pop rdi
    ret

; ------------------------------------------------------------
; PRINTING FUNCTIONS
; ------------------------------------------------------------
print_string:
    push rax
    push rdi
    push rdx
    push rsi
    
    ; Calculate string length
    call string_length
    mov rdx, rax
    
    ; sys_write
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    pop rsi                 ; Get string pointer back
    syscall
    
    pop rdx
    pop rdi
    pop rax
    ret

string_length:
    push rbx
    mov rbx, rsi
    xor rax, rax
    
.length_loop:
    cmp byte [rbx + rax], 0
    je .length_done
    inc rax
    jmp .length_loop

.length_done:
    pop rbx
    ret
