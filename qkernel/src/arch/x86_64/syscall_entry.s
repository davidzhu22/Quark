.globl syscall_entry, kernel_stack,
.globl context_swap, context_swap_to, signal_call, __vsyscall_page, rdtsc, initX86FPState

.globl div_zero_handler
.globl debug_handler
.globl nm_handler
.globl breakpoint_handler
.globl overflow_handler
.globl bound_range_handler
.globl invalid_op_handler
.globl device_not_available_handler
.globl double_fault_handler
.globl invalid_tss_handler
.globl segment_not_present_handler
.globl stack_segment_handler
.globl gp_handler
.globl page_fault_handler
.globl x87_fp_handler
.globl alignment_check_handler
.globl machine_check_handler
.globl simd_fp_handler
.globl virtualization_handler
.globl security_handler

.extern syscall_handler, CopyData,

.extern DivByZeroHandler
.extern DebugHandler
.extern NonmaskableInterrupt
.extern BreakpointHandler
.extern BoundRangeHandler
.extern OverflowHandler
.extern InvalidOpcodeHandler
.extern DeviceNotAvailableHandler
.extern DoubleFaultHandler
.extern InvalidTSSHandler
.extern SegmentNotPresentHandler
.extern StackSegmentHandler
.extern GPHandler
.extern PageFaultHandler
.extern X87FPHandler
.extern AlignmentCheckHandler
.extern MachineCheckHandler
.extern SIMDFPHandler
.extern VirtualizationHandler
.extern SecurityHandler

.intel_syntax noprefix

kernel_stack: .quad 0
user_stack: .quad 0

syscall_entry:
      swapgs

      //user stack
      mov gs:8, rsp

      //kernel stack
      mov rsp, gs:0

      //reserve the space for exception stack frame
      sub rsp, 1 * 8
      push gs:8
      sub rsp, 3 * 8
      push rax

      push rdi
      push rsi
      push rdx
      push rcx
      push rax
      push r8
      push r9
      push r10
      push r11

      //callee-preserved
      push rbx
      push rbp
      push r12
      push r13
      push r14
      push r15

      mov rcx, r10
      call syscall_handler


.balign 4096, 0xcc
__vsyscall_page:
    //sys_gettimeofday
    mov rax, 96
    syscall
    ret

    .balign 1024, 0xcc
    //sys_time
    mov rax, 201
    syscall
    ret

    .balign 1024, 0xcc
    //sys_getcpu
    mov rax, 309
    syscall
    ret

    .balign 4096, 0xcc
    .size __vsyscall_page, 4096

rdtsc:
    lfence
    rdtsc
    shlq rdx, 32
    addq rax, rdx
    ret

context_swap:
    mov [rdi+0x00], rsp
    mov [rdi+0x08], r15
    mov [rdi+0x10], r14
    mov [rdi+0x18], r13
    mov [rdi+0x20], r12
    mov [rdi+0x28], rbx
    mov [rdi+0x30], rbp

    mov [rdi+0x40], rdx

    mov rsp, [rsi+0x00]
    mov r15, [rsi+0x08]
    mov r14, [rsi+0x10]
    mov r13, [rsi+0x18]
    mov r12, [rsi+0x20]
    mov rbx, [rsi+0x28]
    mov rbp, [rsi+0x30]
    mov rdi, [rsi+0x38]
    mov [rsi+0x40], rcx
    ret

context_swap_to:
    mov rsp, [rsi+0x00]
    mov r15, [rsi+0x08]
    mov r14, [rsi+0x10]
    mov r13, [rsi+0x18]
    mov r12, [rsi+0x20]
    mov rbx, [rsi+0x28]
    mov rbp, [rsi+0x30]
    mov rdi, [rsi+0x38]
    mov [rsi+0x40], rcx
    ret

.macro HandlerWithoutErrorCode target
    //push dummy error code
    sub rsp, 8

    push rdi
    push rsi
    push rdx
    push rcx
    push rax
    push r8
    push r9
    push r10
    push r11

    // switch to task kernel stack
    mov rdi, rsp
    // cs of call, if it from user, last 3 bit is 0b11
    mov rsi, [rsp + 11*8]
    //caused in user mode?
    and rsi, 0b11
    jz 1f
    //load kernel rsp
    swapgs
    mov rsp, gs:0
    swapgs
    jmp 2f
    1:
    //load exception rsp, which is kernel rsp
    mov rsi, [rsp + 13 *8]
    2:
    sub rsi, 15 * 8
    mov rdx, 15
    mov rsi, rsp
    call CopyData

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rdi, rsp
    // calculate exception stack frame pointer
    add rdi, 16*8
    // align the stack pointer
    //sub rsp, 8
    call \target
    // undo stack pointer alignment
    //add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    pop r11
    pop r10
    pop r9
    pop r8
    pop rax
    pop rcx
    pop rdx
    pop rsi
    pop rdi

    // pop error code
    add rsp, 8
    iretq
.endm

//todo: better solution with higher performance? fix this.
.macro HandlerWithErrorCode1 target
    push rdi

    mov rdi, [rsp + 3*8]    /* regs->cs */

    //caused in user mode?
    and rdi, 0b11
    jz 1f
    //load kernel rsp
    mov rdi, rsp
    swapgs
    mov rsp, gs:0
    swapgs
1:
    //load exception rsp, which is kernel rsp
    mov rsp, [rsp + 5 * 8]
2:
    pushq	[rdi + 6*8]		/* regs->ss */
    pushq	[rdi + 5*8]		/* regs->rsp */
    pushq	[rdi + 4*8]		/* regs->eflags */
    pushq	[rdi + 3*8]		/* regs->cs */
    pushq	[rdi + 2*8]		/* regs->ip */
    pushq	[rdi + 1*8]		/* regs->orig_ax */
    pushq	[rdi + 0*8]     /* regs->rdi */


    push rsi
    push rdx
    push rcx
    push rax
    push r8
    push r9
    push r10
    push r11

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rsi, [rsp + 15*8]
    mov rdi, rsp
    // calculate exception stack frame pointer
    add rdi, 16*8
    // align the stack pointer
    //sub rsp, 8
    call \target
    // undo stack pointer alignment
    //add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    pop r11
    pop r10
    pop r9
    pop r8
    pop rax
    pop rcx
    pop rdx
    pop rsi
    pop rdi

    // pop error code
    add rsp, 8
    iretq
.endm

.macro HandlerWithErrorCode target
	push rdi
    push rsi
    push rdx
    push rcx
    push rax
    push r8
    push r9
    push r10
    push r11

    // switch to task kernel stack
    mov rdi, rsp
    // cs of call, if it from user, last 3 bit is 0b11
    mov rsi, [rsp + 11*8]
    //caused in user mode?
    and rsi, 0b11
    jz 1f
    //load kernel rsp
    swapgs
    mov rsp, gs:0
    swapgs
    jmp 2f
    1:
    //load exception rsp, which is kernel rsp
    mov rsp, [rsp + 13 *8]
    2:
    sub rsp, 15 * 8
    mov rdx, 15
    mov rsi, rsp
    call CopyData

    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov rsi, [rsp + 15*8]
    mov rdi, rsp
    // calculate exception stack frame pointer
    add rdi, 16*8
    // align the stack pointer
    //sub rsp, 8
    call \target
    // undo stack pointer alignment
    //add rsp, 8

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    pop r11
    pop r10
    pop r9
    pop r8
    pop rax
    pop rcx
    pop rdx
    pop rsi
    pop rdi

    // pop error code
    add rsp, 8
    iretq
.endm

div_zero_handler:
    HandlerWithoutErrorCode DivByZeroHandler

debug_handler:
    HandlerWithoutErrorCode DebugHandler

nm_handler:
    HandlerWithoutErrorCode NonmaskableInterrupt

breakpoint_handler:
    HandlerWithoutErrorCode BreakpointHandler

bound_range_handler:
    HandlerWithoutErrorCode BoundRangeHandler

overflow_handler:
    HandlerWithoutErrorCode OverflowHandler

invalid_op_handler:
    HandlerWithoutErrorCode InvalidOpcodeHandler

device_not_available_handler:
    HandlerWithoutErrorCode DeviceNotAvailableHandler

double_fault_handler:
    HandlerWithErrorCode DoubleFaultHandler

invalid_tss_handler:
    HandlerWithErrorCode InvalidTSSHandler

segment_not_present_handler:
    HandlerWithErrorCode SegmentNotPresentHandler

stack_segment_handler:
    HandlerWithErrorCode StackSegmentHandler

gp_handler:
    HandlerWithErrorCode GPHandler

page_fault_handler:
    HandlerWithErrorCode PageFaultHandler

x87_fp_handler:
    HandlerWithoutErrorCode X87FPHandler

alignment_check_handler:
    HandlerWithErrorCode AlignmentCheckHandler

machine_check_handler:
    HandlerWithoutErrorCode MachineCheckHandler

simd_fp_handler:
    HandlerWithoutErrorCode SIMDFPHandler

virtualization_handler:
    HandlerWithoutErrorCode VirtualizationHandler

security_handler:
    HandlerWithoutErrorCode SecurityHandler

initX86FPState:
    // Save MXCSR (callee-save)
    STMXCSR     [rsp - 8]

    // Save x87 CW (callee-save)
    FSTCW       [rsp - 16]

    // Do we use xsave?
    MOV         rax, rsi
    TESTQ       rax, rax
    JZ          no_xsave1

    // Use XRSTOR to clear all FP state to an initial state.
    //
    // The fpState XSAVE area is zeroed on function entry, meaning
    // XSTATE_BV is zero.
    //
    // "If RFBM[i] = 1 and bit i is clear in the XSTATE_BV field in the
    // XSAVE header, XRSTOR initializes state component i."
    //
    // Initialization is defined in SDM Vol 1, Chapter 13.3. It puts all
    // the registers in a reasonable initial state, except MXCSR:
    //
    // "The MXCSR register is part of state component 1, SSE state (see
    // Section 13.5.2). However, the standard form of XRSTOR loads the
    // MXCSR register from memory whenever the RFBM[1] (SSE) or RFBM[2]
    // (AVX) is set, regardless of the values of XSTATE_BV[1] and
    // XSTATE_BV[2]."

    // Set MXCSR to the default value.
    MOV         eax,  0x1f80
    MOV         [rdi + 24], eax

    // Initialize registers with XRSTOR.
    MOV         eax, 0xffffffff
    MOV         edx, 0xffffffff
    XRSTOR64    [rdi + 0]

    // Now that all the state has been reset, write it back out to the
    // XSAVE area.
    //XSAVE64   [rdi + 0]
no_xsave1:
    ret

initX86FPState1:
    // Save MXCSR (callee-save)
    STMXCSR     [rsp - 8]

    // Save x87 CW (callee-save)
    FSTCW       [rsp - 16]

    // Do we use xsave?
    MOV         rax, rsi
    TESTQ       rax, rax
    JZ          no_xsave

    // Use XRSTOR to clear all FP state to an initial state.
    //
    // The fpState XSAVE area is zeroed on function entry, meaning
    // XSTATE_BV is zero.
    //
    // "If RFBM[i] = 1 and bit i is clear in the XSTATE_BV field in the
    // XSAVE header, XRSTOR initializes state component i."
    //
    // Initialization is defined in SDM Vol 1, Chapter 13.3. It puts all
    // the registers in a reasonable initial state, except MXCSR:
    //
    // "The MXCSR register is part of state component 1, SSE state (see
    // Section 13.5.2). However, the standard form of XRSTOR loads the
    // MXCSR register from memory whenever the RFBM[1] (SSE) or RFBM[2]
    // (AVX) is set, regardless of the values of XSTATE_BV[1] and
    // XSTATE_BV[2]."

    // Set MXCSR to the default value.
    MOV         eax,  0x1f80
    MOV         [rdi + 24], eax

    // Initialize registers with XRSTOR.
    MOV         eax, 0xffffffff
    MOV         edx, 0xffffffff
    XRSTOR64    [rdi + 0]

    // Now that all the state has been reset, write it back out to the
    // XSAVE area.
    XSAVE64     [rdi + 0]

    JMP         out

no_xsave:
    // Clear out existing X values.
    PXOR        xmm0, xmm0
    MOVDQA      xmm1, xmm0
    MOVDQA      xmm2, xmm0
    MOVDQA      xmm3, xmm0
    MOVDQA      xmm4, xmm0
    MOVDQA      xmm5, xmm0
    MOVDQA      xmm6, xmm0
    MOVDQA      xmm7, xmm0
    MOVDQA      xmm8, xmm0
    MOVDQA      xmm9, xmm0
    MOVDQA      xmm10, xmm0
    MOVDQA      xmm11, xmm0
    MOVDQA      xmm12, xmm0
    MOVDQA      xmm13, xmm0
    MOVDQA      xmm14, xmm0
    MOVDQA      xmm15, xmm0

	// Zero out %rax and store into MMX registers. MMX registers are
	// an alias of 8x64 bits of the 8x80 bits used for the original
	// x87 registers. Storing zero into them will reset the FPU registers
	// to bits [63:0] = 0, [79:64] = 1. But the contents aren't too
	// important, just the fact that we have reset them to a known value.
	XOR         rax, rax
    MOVQ        mm0, rax
    MOVQ        mm1, rax
    MOVQ        mm2, rax
    MOVQ        mm3, rax
    MOVQ        mm4, rax
    MOVQ        mm5, rax
    MOVQ        mm6, rax
    MOVQ        mm7, rax

    // The Go assembler doesn't support FNINIT, so we use BYTE.
    // This will:
    //  - Reset FPU control word to 0x037f
    //  - Clear FPU status word
    //  - Reset FPU tag word to 0xffff
    //  - Clear FPU data pointer
    //  - Clear FPU instruction pointer
    FNINIT

    // Reset MXCSR.
    MOV         eax, 0x1f80
    MOV         [rsp - 24], eax
    LDMXCSR     [rsp - 24]

    // Save the floating point state with fxsave.
    FXSAVE64    [rdi + 0]

out:
    // Restore MXCSR.
	LDMXCSR     [rsp - 8]

	// Restore x87 CW.
    FLDCW       [rsp - 16]

    RET


