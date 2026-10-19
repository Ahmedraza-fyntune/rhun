# WebAssembly interpreter (rhun --wasm-host, rhun --wasm-spec): shared layouts and macros.
#
# A module is decoded, validated and compiled for one instance (module and instance are one
# record, WI). Function bodies compile to threaded code: 8-byte slots, each instruction a
# handler address followed by its operands. Values live in 8-byte slots of one value stack; i32
# and f32 values are kept zero-extended. Registers while wasm code runs:
#   rsi  instruction pointer (the slot after the handler's own)
#   r12  value stack top (the next free slot)
#   r13  the running function's locals (local N at [r13 + N*8], operands above them)
#   r14  memory 0's base, r15 its size in bytes
#   rbx  the running function's instance
#   rbp  the call frame stack's top (WFR records)

.equ WASM_PAGE, 65536
.equ WASM_MAX_PAGES, 4096           # 256 MB of linear memory an instance at most
.equ WASM_MAX_TABLE, 10000000       # table entries
.equ WASM_MAX_LOCALS, 50000         # locals of one function, parameters included
.equ WASM_MAX_FUNCS, 1000000
.equ WASM_MAX_TYPES, 1000000
.equ WASM_STACK_BYTES, 16 << 20     # the value stack
.equ WASM_FRAMES, 100000            # nested calls
.equ WASM_MAX_RESULTS, 1000         # parameters or results of a function type

# value types
.equ WV_I32, 0x7f
.equ WV_I64, 0x7e
.equ WV_F32, 0x7d
.equ WV_F64, 0x7c
.equ WV_V128, 0x7b
.equ WV_FUNCREF, 0x70
.equ WV_EXTERNREF, 0x6f
.equ WV_UNKNOWN, 0                  # validation: the polymorphic stack's any type

# import and export kinds
.equ WK_FUNC, 0
.equ WK_TABLE, 1
.equ WK_MEM, 2
.equ WK_GLOBAL, 3

# trap codes (wasm_invoke's result); the messages are wasm_trap_text's
.equ WT_OK, 0
.equ WT_UNREACHABLE, 1
.equ WT_DIV0, 2
.equ WT_OVERFLOW, 3
.equ WT_CONVERSION, 4
.equ WT_OOB_MEMORY, 5
.equ WT_OOB_TABLE, 6
.equ WT_UNDEFINED, 7                # call_indirect past the table's end
.equ WT_UNINIT, 8                   # call_indirect of a null entry
.equ WT_SIGNATURE, 9                # call_indirect of another type
.equ WT_EXHAUSTED, 10               # call stack or value stack exhausted
.equ WT_EXIT, 11                    # WASI proc_exit: g_wasm_exit holds the status
.equ WT_HOST, 12                    # a host function failed

# a function type, interned (wasm_type_intern): one record per distinct signature
STRUCT
F WTY_nparams, 4
F WTY_nresults, 4
F WTY_types, 8                      # params then results, one byte each
ENDSTRUCT WTY_SIZE

# a function
STRUCT
F WFN_type, 4                       # interned type id
F WFN_nparams, 4
F WFN_nresults, 4
F WFN_nlocals, 4                    # declared locals (parameters not counted)
F WFN_need, 8                       # value stack bytes the body needs above its parameters
F WFN_inst, 8                       # the instance it belongs to
F WFN_code, 8                       # its threaded code
F WFN_host, 8                       # a host function: fn(args rdi, WFN rsi, instance rbx) -> trap code
F WFN_user, 8                       # host function data
ENDSTRUCT WFN_SIZE

# a table
STRUCT
F WTB_elems, 8                      # 8-byte references (a WFN, an extern value, 0 for null)
F WTB_size, 8
F WTB_max, 8                        # -1 for none
F WTB_cap, 8
F WTB_type, 8                       # WV_FUNCREF or WV_EXTERNREF
ENDSTRUCT WTB_SIZE

# a linear memory
STRUCT
F WMEM_base, 8
F WMEM_size, 8                      # bytes
F WMEM_cap, 8                       # bytes mapped
F WMEM_max, 8                       # pages; -1 for none
ENDSTRUCT WMEM_SIZE

# a global: its value and type, shared by the instances that import it
STRUCT
F WGL_value, 8
F WGL_type, 1
F WGL_mut, 1
F WGL_pad, 6
ENDSTRUCT WGL_SIZE

# an export
STRUCT
F WEX_name, 8
F WEX_len, 8
F WEX_kind, 8
F WEX_index, 8
ENDSTRUCT WEX_SIZE

# an element segment
STRUCT
F WEL_items, 8                      # 8-byte references
F WEL_count, 8                      # 0 once dropped
F WEL_type, 8
F WEL_mode, 8                       # 0 passive, 1 active, 2 declarative
F WEL_table, 8
F WEL_offset, 8
ENDSTRUCT WEL_SIZE

# a data segment
STRUCT
F WDA_ptr, 8                        # in the module's bytes
F WDA_len, 8                        # 0 once dropped
F WDA_mode, 8                       # 0 passive, 1 active
F WDA_offset, 8
ENDSTRUCT WDA_SIZE

# a function body to compile
STRUCT
F WBO_start, 8                      # in the module's bytes
F WBO_end, 8
ENDSTRUCT WBO_SIZE

# a module instance
STRUCT
F WI_bytes, 8                       # the module's bytes (the instance keeps them)
F WI_len, 8
F WI_types, 8                       # interned type id (u32) per type index
F WI_ntypes, 8
F WI_funcs, 8                       # VEC: WFN pointer per function index, imports first
F WI_nfuncs, 8
F WI_funcscap, 8
F WI_tables, 8                      # VEC: WTB pointer per table index
F WI_ntables, 8
F WI_tablescap, 8
F WI_globals, 8                     # VEC: WGL pointer per global index
F WI_nglobals, 8
F WI_globalscap, 8
F WI_nimpfuncs, 8
F WI_nimpglobals, 8
F WI_mem, 8                         # WMEM of memory 0 (wasm_no_memory when it has none)
F WI_nmems, 8
F WI_exports, 8                     # WEX records
F WI_nexports, 8
F WI_start, 8                       # function index, -1 for none
F WI_elems, 8                       # WEL records
F WI_nelems, 8
F WI_datas, 8                       # WDA records
F WI_ndatas, 8
F WI_datacount, 8                   # the data count section's, -1 when absent
F WI_bodies, 8                      # WBO record per defined function
F WI_nbodies, 8
F WI_code, 8                        # threaded code (grows while compiling; relative branches)
F WI_codelen, 8
F WI_codecap, 8
F WI_refs, 8                        # one byte per function: referenced outside code (ref.func allowed)
F WI_fnmem, 8                       # the defined functions' WFN records
F WI_ndefined, 8
ENDSTRUCT WI_SIZE

# a call frame
STRUCT
F WFR_ip, 8                         # where the caller continues
F WFR_locals, 8                     # the caller's r13
F WFR_inst, 8                       # the caller's rbx
F WFR_pad, 8
ENDSTRUCT WFR_SIZE

# continue with the next instruction
.macro NEXT
    mov rax, [rsi]
    add rsi, 8
    jmp rax
.endm

# Decoder functions pass the cursor r12 back to their caller: their prologue keeps rbp, r14 and
# r15 only (rbx and r13 are left alone), and reserves `frame` bytes at [rsp].
.macro DPROLOGUE frame=0
    push rbp
    mov rbp, rsp
    push r14
    push r15
    sub rsp, 8 + \frame
.ifdef WINDOWS
    and rsp, -16
.endif
.endm

.macro DEPILOGUE
    lea rsp, [rbp - 16]
    pop r15
    pop r14
    pop rbp
    ret
.endm
