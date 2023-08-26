
BITS 16
org 0x500

    jmp start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Macros...

%macro print 1
    push di
    jmp %%after
%%message: db %1, 0
%%after:
    mov di, %%message
    call internal_print_string
    pop di
%endmacro

%macro nl 0
    call print_newline
%endmacro

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Parameter stack -- register BP

param_stack_base equ 0xf800  ; allows 2k for call stack

init_param_stack:
    mov bp, param_stack_base
    ret

%macro PUSH 1 ; TODO: rename pspush?
    sub bp, 2
    mov [bp], %1
%endmacro

%macro POP 1
    mov %1, [bp]
    add bp, 2
    call check_ps_underflow
%endmacro

check_ps_underflow:
    cmp bp, param_stack_base
    ja .underflow
    ret
.underflow:
    print "stack underflow."
    nl
    jmp _crash

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Words start here...
;;; Use '_" prefix for words in forth-style ASM (args/return on parameter-stack)

%define lastlink 0

%macro defword 1
%%name: db %1, 0 ; null
%%link: dw lastlink
db (%%link - %%name - 1) ; dont include null in count
%define lastlink %%link
%endmacro

%macro defwordimm 1
%%name: db %1, 0 ; null
%%link: dw lastlink
db ((%%link - %%name - 1) | 0x80) ; dont include null in count
%define lastlink %%link
%endmacro

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; echo-control, messages, startup, crash

echo_enabled: dw 0

defword "echo-enabled" ; ( -- addr )
    mov bx, echo_enabled
    PUSH bx
    ret

defword "echo-off"
echo_off:
    mov byte [echo_enabled], 0
    ret

defword "echo-on"
    mov byte [echo_enabled], 1
    ret

defword "welcome"
    print "Welcome to Nick's Forth-like thing..."
    nl
    ret

defword "expect-failed"
    print "Expect failed, got: "
    ret

defword "todo" ;; TODO: need strings so we can avoid these specific messages
    print "TODO: "
    ret

defword "crash"
_crash:
    print "**We have crashed!"
    nl
.loop:
    call echo_off
    call read_char ; avoiding tight loop which spins laptop fans
    jmp .loop

is_startup_complete: dw 0
defword "startup-is-complete" ;; TODO: candidate for hidden word
    mov byte [is_startup_complete], 1
    ret

defword "crash-only-during-startup"
_crash_only_during_startup:
    cmp byte [is_startup_complete], 0
    jz _crash
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Output

defword "emit" ; ( byte -- ) ; emit ascii char
    POP ax
    call print_char
    ret

defword "."
    POP ax
    call print_number
    mov al, ' '
    call print_char
    ret

defword ".h" ; ( byte -- ) ; emit as 2-digit hex
_dot_h:
    POP ax
    mov ah, 0
    push ax
    push ax
    ;; hi nibble
    pop di
    and di, 0xf0
    shr di, 4
    mov al, [.hex+di]
    call print_char
    ;; lo nibble
    pop di
    and di, 0xf
    mov al, [.hex+di]
    call print_char
    mov al, ' '
    call print_char
    ret
.hex db "0123456789abcdef"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Stack manipulation

defword "dup"
_dup:
    POP ax
    PUSH ax
    PUSH ax
    ret

defword "swap"
_swap:
    POP bx
    POP ax
    PUSH bx
    PUSH ax
    ret

defword "over"
_over:
    POP ax
    POP bx
    PUSH bx
    PUSH ax
    PUSH bx
    ret

defword "rot" ; ( 1 2 3 -- 2 3 1 )
    POP ax ;3
    POP bx ;2
    POP cx ;1
    PUSH bx ;2
    PUSH ax ;3
    PUSH cx ;1
    ret

defword "drop"
_drop:
    POP ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Numerics...

defword "+"
_add:
    POP bx
    POP ax
    add ax, bx
    PUSH ax
    ret

defword "-"
    POP bx
    POP ax
    sub ax, bx
    PUSH ax
    ret

defword "*"
    POP bx
    POP ax
    mul bx ; ax = ax*bx
    PUSH ax
    ret

defword "<"
    POP bx
    POP ax
    cmp ax, bx
    mov ax, 0xffff ; true
    jl isLess
    mov ax, 0 ; false
isLess:
    PUSH ax
    ret

defword "="
    POP bx
    POP ax
    cmp ax, bx
    mov ax, 0xffff ; true
    jz isEq
    mov ax, 0 ; false
isEq:
    PUSH ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Control flow

defword "0branch"
_0branch:
    pop bx
    POP cx
    cmp cx, 0
    jz .no
    add bx, 2 ; skip over target pointer, and continue
    jmp bx
.no:
    mov bx, [bx]
    jmp bx ; branch to target

defword "exit"
_exit:
    pop bx ; and ignore
    ret

defwordimm "br"
    call _word_find
    POP bx
    push bx
    mov ax, _branch
    PUSH ax
    call _write_call
    pop bx
    add bx, 3
    mov ax, bx
    PUSH ax
    call _comma
    ret

_branch:
    pop bx
    mov bx, [bx]
    jmp bx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Fetch and store

defword "@"
_fetch:
    POP bx
    mov ax, [bx]
    PUSH ax
    ret

defword "!"
_store:
    POP bx
    POP ax
    mov [bx], ax
    ret

defword "c@"
_c_at:
    POP bx
    mov ah, 0
    mov al, [bx]
    PUSH ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; heap...

defword "here-pointer"
_here_pointer:
    mov bx, here
    PUSH bx
    ret

;;;defword "c," ;; TODO: check standard & test
_write_byte:
    POP al
    call internal_write_byte ;; TODO: inline
    ret

;;; write a 16-bit word into the heap ; TODO: move this into forth
defword ","
_comma:
    POP ax
    mov bx, [here]
    mov [bx], ax
    add word [here], 2
    ret

defword "'"
_tick:
    call _word_find
    POP bx
    add bx, 3 ;; TODO: factor this +3 pattern to get XT
    PUSH bx
    ret

defword "execute"
    POP bx
    jmp bx

defword "immediate?"
    call _word_find
    call _test_immediate_flag
    ret

defword "test-immediate-flag"
_test_immediate_flag:
    POP bx
    mov al, [bx+2]
    cmp al, 0x80
    ja .yes
    jmp .no
.yes:
    mov ax, 0xffff ; true
    PUSH ax
    ret
.no:
    mov ax, 0 ; false
    PUSH ax
    ret

defword "immediate"
    call _latest_entry
    call _flip_immediate_flag
    ret

defword "immediate^"
    call _word_find
    call _flip_immediate_flag
    ret

defword "flip-immediate-flag"
_flip_immediate_flag:
    POP bx
    mov al, [bx+2]
    xor al, 0x80
    mov [bx+2], al
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Literals

defword "(lit)" ;; internal name
_lit:
    pop bx
    mov ax, [bx]
    PUSH ax
    add bx, 2
    jmp bx

defwordimm "literal"
_literal:
    POP ax
    push ax ; save lit value
    mov ax, _lit
    PUSH ax
    call _write_call
    pop ax ; restore lit value
    PUSH ax
    call _comma
    ret

defwordimm "[']"
    call _word_find
    POP ax
    add ax, 3
    PUSH ax
    call _literal
    ret

defwordimm "[char]"
    call t_word
    POP bx
    mov ah, 0
    mov al, [bx]
    PUSH ax
    call _literal
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; compile,

;;; compile call to execution token on top of stack
defword "compile," ; ( absolute-address-to-call -- )
_write_call:
    call _abs_to_rel
    call _write_call_byte
    call _comma
    ret

_write_call_byte:
    ;;mov al, 0xe8 ; x86 encoding for "call"
    ;;PUSH ax
    call _lit
    dw 0xe8
    call _write_byte
    ret

_abs_to_rel: ; ( addr-abs -> addr-rel )
    POP ax
    sub ax, [here] ; make it relative
    sub ax, 3      ; to the end of the 3 byte instruction
    PUSH ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Dictionary entries & find

defword "entry->name"
_entry_name: ;; TODO: use this in dictfind
    POP bx
    mov ch, 0
    mov cl, [bx+2]
    and cl, 0x7f
    mov di, bx
    sub di, cx
    dec di ; subtract 1 more for the null
    PUSH di
    ret

defword "strlen" ; ( name-addr -- n )
_strlen:
    POP di
    call internal_strlen ;; INLINE
    PUSH ax
    ret

;;; Compute length of a null-terminated string
;;; [in DI=string; out AX=length]
;;; [consumes DI; uses BL]
internal_strlen:
    mov ax, 0
.loop:
    mov bl, [di]
    cmp bl, 0
    jz .ret
    inc ax
    inc di
    jmp .loop
.ret:
    ret

defword "create-entry" ; ( name-addr -- )
_create_entry:
    call _dup           ; ( a a )
    call _strlen        ; ( a n )
    call _swap          ; ( n a )
    call _over          ; ( n a n )
    call _write_string  ; ( n )
    call _write_link    ; ( n )
    call _write_byte
    ret

_write_link:
    mov ax, [dictionary]
    mov bx, [here]
    mov [dictionary], bx
    PUSH ax
    call _comma ; link
    ret

;;; Write string to [here]
_write_string:
    POP cx ; length
    POP di ; string
.loop:
    cmp cx, 0
    jz .done
    mov ax, [di]
    call internal_write_byte
    inc di
    dec cx
    jmp .loop
.done:
    mov ax, 0
    call internal_write_byte ; null
    ret

;;; Write byte to [here], in AL=byte, uses BX
internal_write_byte:
    mov bx, [here]
    mov [bx], al
    inc word [here]
    ret

defword "find" ; ( string-addr -- 0|xt )
_find:
    POP dx
    call internal_dictfind
    PUSH bx
    ret


;;defword "find" -- TODO: make a standard compliant findx
t_find: ;; t for transient
    POP dx
    PUSH dx
    call internal_dictfind ;; TODO: inline
    cmp bx, 0
    jz _warn_missing
    POP dx
    PUSH bx
    ret

defword "warn-missing"
_warn_missing:
    print "**No such word: "
    POP di
    call internal_print_string
    nl
    call _crash_only_during_startup
    mov ax, _missing-3 ;; hack to get from the code pointer to the entry pointer
    PUSH ax
    ret

_missing:
    print "**Missing**"
    nl
    ret

;;; Lookup word in dictionary, return entry if found or 0 otherwise
;;; [in DX=sought-name, out BX=entry/0]
;;; [uses SI, DI, BX, CX]
internal_dictfind:
    mov di, dx
    PUSH di
    call _strlen ; ax=len
    POP ax
    mov bx, [dictionary]
.loop:
    mov cl, [bx+2]
    and cl, 0x7f
    cmp al, cl ; 8bit length comapre
    jnz .next
    ;; length matches; compare names
    mov si, dx ; si=sought name
    mov di, bx
    sub di, ax
    dec di ; subtract 1 more for the null
    ;; now di=this entry name
    mov cx, ax ; length
    push ax
    call cmp_n
    pop ax
    jnz .next
    ret ; BX=entry
.next:
    mov bx, [bx] ; traverse link
    cmp bx, 0
    jnz .loop
    ret ; BX=0 - not found


defword "latest-entry"
_latest_entry:
    mov bx, [dictionary]
    PUSH bx
    ret

defword "words"
_words:
    mov bx, [dictionary]
.loop:
    mov cl, [bx+2]
    and cl, 0x7f
    mov ch, 0
    mov di, bx
    sub di, cx
    dec di ; null
    call internal_print_string
    mov al, ' '
    call print_char
    mov bx, [bx] ; traverse link
    cmp bx, 0
    jnz .loop
    call print_newline
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; word

defword "word" ; ( " blank-deliminted-word " -- string-addr )
t_word: ;; t for transient
    call internal_read_word ;; TODO inline
    mov ax, buffer
    PUSH ax ;; transient buffer; for _find/create
    ret

;;; Read word from keyboard into buffer memory -- prefer _word
;;; [uses AX,DI]
internal_read_word:
    mov di, buffer
.skip:
    call read_char
    cmp al, 0x21
    jb .skip ; skip leading white-space
.loop:
    cmp al, 0x21
    jb .done ; stop at white-space
    mov [di], al
    inc di
    call read_char
    jmp .loop
.done:
    mov byte [di], 0 ; null
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Uses t_word

defword "char"
    call t_word
    POP bx
    mov ah, 0
    mov al, [bx]
    PUSH ax
    ret

defword "constant"
    call t_word
    call _create_entry
    call _lit
    dw _lit
    call _write_call
    call _comma
    call _lit
    dw _exit
    call _write_call
    ret

defword "word-find"
_word_find:
    call t_word
    call t_find
    ret

defwordimm "("
.loop:
    call t_word
    POP di
    cmp word [di], ")"
    jz .close
    jmp .loop
.close:
    ret

defword "print-string"
_print_string:
    POP di
    call internal_print_string
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

defword ":"
    jmp colon_intepreter

colon_intepreter: ; TODO: move this towards forth style
    call t_word
    call _create_entry
.loop:
    call t_word
    POP dx
    mov di, dx
    call is_semi
    jz .semi
    call try_parse_as_number
    jz .number
    PUSH dx
    call t_find
    call _test_immediate_flag
    POP ax
    cmp ax, 0
    jnz .immediate
    add bx, 3
    mov ax, bx
    PUSH ax
    call _write_call
    jmp .loop
.immediate:
    add bx, 3
    call bx
    jmp .loop
.number:
    PUSH ax
    call _literal
    jmp .loop
.semi:
    ;;call write_ret ;; optimization!
    mov ax, _exit
    PUSH ax
    call _write_call
    ret

is_semi:
    cmp word [di], ";"
    ret

;write_ret:
;    mov al, 0xc3 ; x86 encoding for "ret"
;    call write_byte
;    ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; number literals

defword "number?" ; ( string-addr -- number 1 | string-addr 0 )
    call _dup
    POP dx
    call try_parse_as_number
    jnz .nan
    PUSH ax
    call _swap
    call _drop
    mov ax, 1
    PUSH ax
    ret
.nan:
    mov ax, 0
    PUSH ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; start

start:
    call init_param_stack
    call cls
.loop:
    call t_word
    POP dx
    call try_parse_as_number
    jnz .nan
    PUSH ax
    jmp .loop
.nan:
    PUSH dx
    call t_find
    POP bx
    ;; execute code at bx+3
    add bx, 3
    call bx
    jmp .loop

;;; Try to parse a string as a number
;;; [in DX=string-to-be-tested, out Z=yes-number, DX:AX=number]
;;; [uses BL, SI, BX, CX]
try_parse_as_number: ; TODO: code in forth
    push dx
    call .run
    pop dx
    ret
.run:
    mov si, dx
    mov ax, 0
    mov bh, 0
    mov cx, 10
.loop:
    mov bl, [si]
    cmp bl, 0 ; null
    jnz .continue
    ;; reached null; every char was a digit; return YES
    ret
.continue:
    mul cx ; [ax = ax*10]
    ;; current char is a digit?
    sub bl, '0'
    jc .no
    cmp bl, 10
    jnc .no
    ;; yes: accumulate digit
    add ax, bx
    inc si
    jmp .loop
.no:
    cmp bl, 0 ; return NO
    ret

;;; Compare n bytes at two pointers
;;; [in CX=n, SI/DI=pointers-to-things-to-compare, out Z=same]
;;; [consumes SI, DI, CX; uses AL]
cmp_n:
.loop:
    mov al, [si]
    cmp al, [di]
    jnz .ret
    inc si
    inc di
    dec cx
    jnz .loop
    ret ; Z - matches
.ret:
    ret ; NZ - diff

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Reading input...

read_char:
    call [read_char_indirection]
    cmp byte [echo_enabled], 0
    jz .ret
    call print_char ; echo
.ret:
    ret

read_char_indirection: dw startup_read_char

startup_read_char:
    mov bx, [builtin]
    mov al, [bx]
    cmp al, 0
    jz .interactive
    inc word [builtin]
    ret
.interactive:
    mov word [read_char_indirection], interactive_read_char
    jmp interactive_read_char

builtin: dw builtin_data
builtin_data:
    incbin "f/early.f"
    incbin "f/inter.f"
    incbin "f/predefined.f"
    incbin "f/unimplemented.f"
    incbin "f/regression.f"
    incbin "f/my-letter-F.f"
    incbin "f/dump.f"
    incbin "f/start.f"
    incbin "f/play.f"
    db 0

;;; Read char from input
;;; [out AL=char-read]
;;; [uses AX]
interactive_read_char:
    mov ah, 0
    int 0x16
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Print to output

;;; Print number in decimal format.
;;; in: AX=number
print_number:
    push ax
    push bx
    push dx
    call .go
    pop dx
    pop bx
    pop ax
    ret
.go:
    mov bx, 10
.nest:
    mov dx, 0
    div bx ; ax=ax/10; dx=ax%10
    cmp ax, 0 ; last digit?
    jz .print_digit ; YES, so print it
    ;; NO, deal with more significant digits first
    push dx
    call .nest
    pop dx
    ;; then drop to print this one
.print_digit:
    push ax
    mov al, dl
    add al, '0'
    call print_char
    pop ax
    ret

;;; Print null-terminated string.
;;; in: DI=string
internal_print_string:
    push ax
    push di
.loop:
    mov al, [di]
    cmp al, 0 ; null?
    je .done
    call print_char
    inc di
    jmp .loop
.done:
    pop di
    pop ax
    ret

;;; Print newline to output
print_newline:
    push ax
    mov al, 13
    call print_char
    pop ax
    ret

;;; Print char to output; special case 13 as 10(NL);13(CR)
;;; in: AL=char
print_char:
    push ax
    push bx
    call .go
    pop bx
    pop ax
    ret
.go:
    cmp al, 13
    jz .nl_cr
    cmp al, 10
    jz .nl_cr
.raw:
    mov ah, 0x0e ; Function: Teletype output
    mov bh, 0
    int 0x10
    ret
.nl_cr:
    mov al, 10 ; NL
    call .raw
    mov al, 13 ; CR
    jmp .raw

;;; Clear screen
cls:
    push ax
    mov ax, 0x0003 ; AH=0 AL=3 video mode 80x25
    int 0x10
    pop ax
    ret


buffer: times 64 db 0 ;; must be before size check. why??

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Size check...

%assign R ($-$$)  ;; Space required for above code
%assign S 234      ;; Number of sectors the bootloader loads
%assign A (S*512) ;; Therefore: Maximum space allowed
;;;%warning "Kernel size" required=R, allowed=A (#sectors=S)
%if R>A
%error "Kernel too big!" required=R, allowed=A (#sectors=S)
%endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; buffer & here

dictionary: dw lastlink
here: dw here_start
here_start: ; persistent heap