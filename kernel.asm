
BITS 16
org 0x500

    jmp start

%macro print 1
    push di
    jmp %%after
%%message: db %1, 0
%%after:
    mov di, %%message
    call internal_print_string
    pop di
%endmacro

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Defining primitive words

%define lastlink 0

%macro defword 1
%%name: db %1, 0 ; null
%%link: dw lastlink
db (%%link - %%name - 1) ; dont include null in count
%define lastlink %%link
%endmacro

immediate_flag equ 0x40
hidden_flag equ 0x80

%macro defwordimm 1
%%name: db %1, 0 ; null
%%link: dw lastlink
db ((%%link - %%name - 1) | immediate_flag)
%define lastlink %%link
%endmacro

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Termination

defword "reset"
_reset:
    int 0x19
.loop:
    jmp .loop

defword "bye"
_bye:
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
.loop:
    jmp .loop

defword "crash" ; TODO: rename lock?
_crash:
    print "We have crashed."
    call _cr
    call echo_off
.loop:
    call internal_read_char ; avoiding tight loop which spins laptop fans
    jmp .loop

is_startup_complete: dw 0
defword "startup-is-complete"
    mov byte [is_startup_complete], 1
    ret

defword "crash-only-during-startup"
_crash_only_during_startup:
    cmp byte [is_startup_complete], 0
    jz _crash
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Parameter stack (register: bp)

param_stack_base equ 0xf800  ; allows 2k for call stack

init_param_stack:
    mov bp, param_stack_base
    ret

%macro PUSH 1 ; TODO: rename pspush?
    sub bp, 2
    mov [bp], %1
%endmacro

check_ps_underflow:
    cmp bp, param_stack_base
    jb .ok
    sub bp, 2
    mov word [bp], 0
    print "stack underflow."
    call _cr
    call _crash_only_during_startup
.ok:
    ret

%macro POP 1
    call check_ps_underflow
    mov %1, [bp]
    add bp, 2
%endmacro

defword "sp" ; ( -- addr )
    mov ax, bp
    PUSH ax
    ret

defword "sp0" ; ( -- addr )
    mov ax, param_stack_base
    PUSH ax
    ret

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

defword "drop"
_drop:
    POP ax
    ret

defword "over"
_over:
    POP ax
    POP bx
    PUSH bx
    PUSH ax
    PUSH bx
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Return stack; hardware stack (call,ret,push,pop)

defword ">r"
    POP ax
    pop bx
    push ax
    jmp bx

defword "r>"
    pop bx
    pop ax
    PUSH ax
    jmp bx

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Special numbers : TODO: avoid need

defword "0"
    call _lit
    dw 0
    ret

defword "1"
    call _lit
    dw 1
    ret

defword "10"
    call _lit
    dw 10
    ret

defword "32"
    call _lit
    dw 0x20
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Numeric operations; TODO: M*, shifts, bitwise-ops

defword "/2" ; (n -- n) TODO: should not be a prim
_div2:
    POP ax
    shr ax, 1
    PUSH ax
    ret

defword "+"
_add:
    POP bx
    POP ax
    add ax, bx
    PUSH ax
    ret

defword "-"
_minus:
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

defword "/mod"
    POP bx
    POP ax
    mov dx, 0
    div bx ; dx:ax / bx. quotiant->ax, remainder->dx
    PUSH dx
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
;;; Fetch and store

defword "@"
_fetch:
    POP bx
    mov ax, [bx]
    PUSH ax
    ret

defword "!"
    POP bx
    POP ax
    mov [bx], ax
    ret

defword "c@"
    POP bx
    mov ah, 0
    mov al, [bx]
    PUSH ax
    ret

defword "c!"
    POP bx
    POP ax
    mov [bx], al
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Heap [here]

here: dw here_start

defword "here-pointer" ; TODO: dont expose; instead have alloc as prim
    mov bx, here
    PUSH bx
    ret

defword "," ; write a 16-bit word to [here]
_comma:
    POP ax
    mov bx, [here]
    mov [bx], ax
    add word [here], 2
    ret

defword "c," ; write byte to [here]
_write_byte:
    POP al
    call internal_write_byte ;; TODO: inline when only caller
    ret

internal_write_byte: ; in AL=byte, uses BX
    mov bx, [here]
    mov [bx], al
    inc word [here]
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Threading model and control flow

defword "lit" ; embed literal in threaded instruction stream ; TODO: byte version?
_lit:
    pop bx
    mov ax, [bx]
    PUSH ax
    add bx, 2
    jmp bx

defword "execute"
_execute:
    POP bx
    jmp bx

_exit:
    pop bx ; and ignore
    ret

defword "branchA" ; TODO: loose A suffix (TODO: need to be in dictionary?)
_branchA:
    pop bx
    mov bx, [bx]
    jmp bx

_0branch:
    pop bx
    POP cx
    cmp cx, 0
    jz .no
    add bx, 2 ; skip over target pointer, and continue
    jmp bx
.no:
    add bx, [bx] ; add relative offset (will be backpatched in by "then")
    jmp bx ; branch to target


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Compilation

defword "ret," ; TODO: add "jump," and use for "tail"
_write_ret:
    call _lit
    dw 0xc3 ; x86 encoding for "ret"
    call _write_byte
    ret

defword "compile," ; ( absolute-address-to-call -- )
_write_abs_call: ; TODO rename
    call _abs_to_rel
    call _write_rel_call
    ret

_write_rel_call:
    call _write_rel_call_byte
    call _comma
    ret

_write_rel_call_byte:
    call _lit
    dw 0xe8 ; x86 encoding for "call"; uses relative addressing
    call _write_byte
    ret

_abs_to_rel: ; ( addr-abs -> addr-rel )
    POP ax
    sub ax, [here] ; make it relative
    sub ax, 3      ; to the end of the 3 byte instruction
    PUSH ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Dictionary header ; TODO: document layout

defword "xt->name" ; ( xt -- string )
_xt_name:
    POP bx
    mov ch, 0
    mov cl, [bx-1] ; size byte -1 from xt
    and cl, ~(immediate_flag | hidden_flag)
    sub bx, 4 ; (1) null, (2) link pointer, (1) size byte
    sub bx, cx
    PUSH bx
    ret

;; : xt->next ( 0|xt1 -- 0|xt2 )
;; dup if 3 - @
;; dup if 3 +
;; then then;

defword "xt->next" ; ( 0|xt1 -- 0|xt2 ) ; TODO: improve layout to simplify this
_xt_next:
    call _dup
    call _if
    jz .ret ; zero
    call _lit
    dw 3
    call _minus
    call _fetch
    call _dup
    call _if
    jz .ret ; zero
    call _lit
    dw 3
    call _add
.ret:
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Dictionary flags: immediate, hidden

defword "immediate?" ; ( xt -- bool )
_immediate_query:
    POP bx
    mov al, [bx-1]
    cmp al, immediate_flag
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

defword "hidden?" ; ( xt -- bool )
_hidden_query:
    POP bx
    mov al, [bx-1]
    cmp al, hidden_flag
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

defword "immediate^"
_immediate_flip:
    POP bx
    ;; size/flag byte -1 from xt
    mov al, [bx-1]
    xor al, immediate_flag
    mov [bx-1], al
    ret

defword "hidden^"
_hidden_flip:
    POP bx
    ;; size/flag byte -1 from xt
    mov al, [bx-1]
    xor al, hidden_flag
    mov [bx-1], al
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; New dictionary entries

defword "entry," ; ( name-addr -- )
_create_entry:
    call _dup           ; ( a a )
    call _strlen        ; ( a n )
    call _swap          ; ( n a )
    call _over          ; ( n a n )
    call _write_string  ; ( n )
    call _write_link    ; ( n )
    call _write_byte
    ret

defword "strlen" ; ( name-addr -- n ) ; length of a null-terminated string
_strlen:
    POP di
    call internal_strlen ;; INLINE
    PUSH ax
    ret

internal_strlen: ; in DI=string; out AX=length
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

_write_string: ; to "here" ; TODO: avoid need by having the string already be here!
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

_write_link:
    mov ax, [dictionary]
    mov bx, [here]
    mov [dictionary], bx
    PUSH ax
    call _comma ; link
    ret

defword "latest" ; ( -- xt )
_latest:
    mov bx, [dictionary]
    add bx, 3
    PUSH bx
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Input

key_indirect: dw _key0

defword "key"
_key:
    jmp [key_indirect]

defword "set-key" ; ( xt -- )
    POP ax
    mov [key_indirect], ax
    ret

defword "get-key" ; ( -- xt )
    mov ax, [key_indirect]
    PUSH ax
    ret

_key0:
    call internal_read_char
    mov ah, 0
    PUSH ax
    ret

internal_read_char: ; -> AL
    call [read_char_indirection]
    cmp byte [echo_enabled], 0
    jz .ret
    call print_char ; echo
.ret:
    ret

read_char_indirection: dw read_char

read_char: ; first read from embedded string
    mov bx, [builtin]
    mov al, [bx]
    cmp al, 0
    jz .switch_to_interactive
    inc word [builtin]
    ret
.switch_to_interactive:
    mov word [read_char_indirection], .interactive
.interactive:
    mov ah, 0
    int 0x16
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Output

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

defword "emit" ; ( char -- ) ; emit ascii char
_emit:
    POP ax
    call print_char ; TODO: avoid internal use so can inline
    ret

print_char: ; in: AL=char, special case 13 as 10(NL);13(CR)
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

defword "cls" ; clear screen
_cls:
    push ax
    mov ax, 0x0003 ; AH=0 AL=3 video mode 80x25
    int 0x10
    pop ax
    ret

defword "type"
_type:
    POP di
    call internal_print_string
    ret

internal_print_string: ; in: DI=string; print null-terminated string.
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Start (word-find-execute-loop)

start:
    call init_param_stack
    call _cls ;; TODO: only do this on cold start
    mov ax, _bye
    push ax ; on return stack
.loop:
    cmp byte [is_startup_complete], 0
    jz .go
    mov al, '%' ;; only see '%' after startup is complete
    call print_char
.go:
    call _word
    call _dup
    call _find
    call _dup
    call _if
    jz .missing
    call _swap
    call _drop
    call _execute
    jmp .loop
.missing:
    call _drop
    mov al, '%' ;; make it clear who is reporting the error
    call print_char
    call _type
    call _lit
    dw '?' ;; standard ? error
    call _emit
    call _cr
    call _crash_only_during_startup
    jmp .loop

_if:
    POP ax
    cmp ax, 0
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

%assign X ($-$$)
;%warning X "- After Sorted"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; word (GOAL: not in Asm)

deprecated_word_buffer: times 64 db 0 ;; TODO: kill

defword "word" ; ( " blank-deliminted-word " -- string-addr )
_word:
    call internal_read_word ;; TODO inline
    mov ax, deprecated_word_buffer
    PUSH ax
    ret

internal_read_word: ; using "key" into buffer memory
    mov di, deprecated_word_buffer
.skip:
    call .key
    POP ax
    cmp al, 0x21
    jb .skip ; skip leading white-space
.loop:
    cmp al, 0x21
    jb .done ; stop at white-space
    mov [di], al
    inc di
    call .key
    POP ax
    jmp .loop
.done:
    mov byte [di], 0 ; null
    ret
.key:
    ;; Here we are calling from low-level ASM to a _forth word
    ;; And so we must preserve the registers being used here.
    ;; Failure to do this was the cause of the assumed string literal bug.
    push ax
    push di
    call _key
    pop di
    pop ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; find (GOAL: not in Asm)

defword "find" ; ( s -- xt' )
_find:
    call _latest ; ( s xt )
.loop:
    call _dup
    call _if ; ( s xt )
    jz .missing
    call _dup
    call _hidden_query
    call _if
    jnz .next
    call _over
    call _over ; ( s xt s xt )
    call _xt_name ; ( s xt s s' )
    call _s_equals
    call _if ; ( s xt )
    jz .next
    call _swap
    call _drop ; ( xt' ) Found it !
    ret
.next:
    call _xt_next ; ( s xt )
    jmp .loop
.missing: ; ( s 0 )
    call _drop
    call _drop
    call _lit
    dw 0
    ret

defword "find!"
_find_or_crash:
    call _dup
    call _find
    call _dup
    call _if
    jz .missing
    call _swap
    call _drop
    call _exit
    ret
.missing:
    call _drop
    print "kernel.find-or-crash "
    call _type
    call _lit
    dw '?'
    call _emit
    call _cr
    call _crash ;;-only-during-startup ; TODO: decide
    ret

defword "s="
_s_equals:
    POP si
    POP di
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jnz .diff ; found a differing char, so exit false
    ;; current chars match
    cmp al, 0
    jz .same ; one char is zero (so both must be), so we reached the string ends
    inc si
    inc di
    jmp .loop
.diff:
    call _lit
    dw 0
    ret
.same:
    call _lit
    dw 1
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Printing numbers (TODO: should be in Forth)

defword "." ; ( u -- ) Print number in decimal format.
    POP ax
    call internal_print_number ; TODO: inline
    mov al, ' '
    call print_char
    ret

internal_print_number: ; in: AX=number; TODO: inline
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

defword ".h" ; ( byte -- ) ; emit as 2-digit hex
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
    ret
.hex db "0123456789abcdef"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; (Almost) Pure Forth style -- TODO: make them so!

defword "char"
    call _word
    POP bx
    mov ah, 0
    mov al, [bx]
    PUSH ax
    ret

defwordimm "[char]"
    call _word
    POP bx
    mov ah, 0
    mov al, [bx]
    PUSH ax
    call _literal
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Pure Forth style

defword "0branch,"
    call _lit
    dw _0branch
    call _write_abs_call
    ret

defwordimm "tail"
    call _word
    call _find_or_crash
    call _lit
    dw _branchA
    call _write_abs_call
    call _comma
    ret

defword "tick:"
    call _word
    call _find_or_crash
    ret

defword "entry:"
    call _word
    call _create_entry
    ret

defword "call:" ; TODO: Is this [compile] ?
    call _word
    call _find_or_crash
    call _write_abs_call
    ret

defword "cr"
_cr:
    call _lit
    dw 13
    call _emit
    ret

defwordimm "literal"
_literal:
    call _lit
    dw _lit
    call _write_abs_call
    call _comma
    ret

defword "non-immediate-literal" ; TODO: avoid use & kill def
    jmp _literal

defword "constant"
    call _word
    call _create_entry
    call _lit
    dw _lit
    call _write_abs_call
    call _comma
    call _lit
    dw _exit
    call _write_abs_call
    ret


dictionary: dw lastlink

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Embedded string data (TODO: move to higher mem, above [here])

%assign X ($-$$)
;%warning X "- Before embedded"

builtin: dw builtin_data
builtin_data:
    incbin "f/boot.f"
    incbin "f/string.f"
    incbin "f/dict.f"
    incbin "f/numbers.f"
    incbin "f/interpreter.f"
    incbin "f/colon.f"
    incbin "f/word.f"
    incbin "f/find.f"
    incbin "f/predefined.f"
    incbin "f/tools.f"
    ;incbin "f/own-mult.f"
    incbin "f/regression.f"
    ;incbin "f/control.f"
    incbin "f/buffer.f"
    incbin "f/examples.f"
    incbin "f/primes.f"
    incbin "f/start.f"
    incbin "f/play.f"
    db 0

%assign X ($-$$)
;%warning X "- After Embedded"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Check Size

%assign R ($-$$)  ;; Space required for above code
%assign S 50      ;; Number of sectors the bootloader loads
%assign A (S*512) ;; Therefore: Maximum space allowed
;%warning "Kernel size" required=R, allowed=A (#sectors=S)
%if R>A
%error "Kernel too big!" required=R, allowed=A (#sectors=S)
%endif

here_start:
