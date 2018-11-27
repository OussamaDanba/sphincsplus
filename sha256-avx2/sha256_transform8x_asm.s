.macro rotr32 amount, src_reg, tmp_reg, res_reg
vpsrld $\amount, \src_reg, \res_reg
vpslld $32-\amount, \src_reg, \tmp_reg
vpor \res_reg, \tmp_reg, \res_reg
.endm

# Uses ymm4-ymm7 as scratch registers
.macro sha256_round a, b, c, d, e, f, g, h, rc_offset, w_reg
# Sigma1(e)
rotr32 6, \e, %ymm5, %ymm7
rotr32 11, \e, %ymm5, %ymm6
vpxor %ymm6, %ymm7, %ymm7
rotr32 25, \e, %ymm5, %ymm6
vpxor %ymm6, %ymm7, %ymm7

# Ch(e, f, g)
vpand \e, \f, %ymm6
vpcmpeqd %ymm5, %ymm5, %ymm5
vpxor \e, %ymm5, %ymm5
vpand \g, %ymm5, %ymm5
vpxor %ymm5, %ymm6, %ymm6

# Sigma1(e) + Ch(e, f, g) + h + RC + w
vpaddd %ymm6, %ymm7, %ymm7
vpaddd \h, %ymm7, %ymm7
vpbroadcastd \rc_offset*4(%rcx), %ymm6
vpaddd %ymm6, %ymm7, %ymm7
vpaddd \w_reg, %ymm7, %ymm7

# Sigma0(a)
rotr32 2, \a, %ymm4, %ymm6
rotr32 13, \a, %ymm4, %ymm5
vpxor %ymm5, %ymm6, %ymm6
rotr32 22, \a, %ymm4, %ymm5
vpxor %ymm5, %ymm6, %ymm6

# Maj(a, b, c)
vpand \a, \b, %ymm5
vpand \a, \c, %ymm4
vpxor %ymm4, %ymm5, %ymm5
vpand \b, \c, %ymm4
vpxor %ymm4, %ymm5, %ymm5

# Sigma0(a) + Maj(a, b, c)
vpaddd %ymm5, %ymm6, %ymm6

# d = d + (Sigma1(e) + Ch(e, f, g) + h + RC + w)
vpaddd \d, %ymm7, \d

# h = (Sigma1(e) + Ch(e, f, g) + h + RC + w) + (Sigma0(a) + Maj(a, b, c))
vpaddd %ymm6, %ymm7, \h
.endm

# Stores WSigma1(w0) + w1 + w2 + WSigma0(w3) to ymm0 and the stack
# Uses ymm4-ymm7 as scratch registers
.macro new_w w0, w1, w2, w3, w_target
# WSigma1(w0)
vmovdqa (\w0%16)*32(%rsp), %ymm4
rotr32 17, %ymm4, %ymm5, %ymm0
rotr32 19, %ymm4, %ymm5, %ymm6
vpxor %ymm6, %ymm0, %ymm0
vpsrld $10, %ymm4, %ymm6
vpxor %ymm6, %ymm0, %ymm0

# WSigma1(w0) + w1
vmovdqa (\w1%16)*32(%rsp), %ymm4
vpaddd %ymm4, %ymm0, %ymm0

# WSigma1(w0) + w1 + w2
vmovdqa (\w2%16)*32(%rsp), %ymm4
vpaddd %ymm4, %ymm0, %ymm0

# WSigma0(w3)
vmovdqa (\w3%16)*32(%rsp), %ymm4
rotr32 7, %ymm4, %ymm5, %ymm7
rotr32 18, %ymm4, %ymm5, %ymm6
vpxor %ymm6, %ymm7, %ymm7
vpsrld $3, %ymm4, %ymm6
vpxor %ymm6, %ymm7, %ymm7

# WSigma1(w0) + w1 + w2 + WSigma0(w3)
vpaddd %ymm7, %ymm0, %ymm0
# Store w_target back to stack since it's needed later
vmovdqa %ymm0, (\w_target%16)*32(%rsp)
.endm new_w

.globl sha256_transform8x_asm
.type sha256_transform8x_asm, @function
sha256_transform8x_asm:
    pushq %rbp
    movq %rsp, %rbp
    # Align stack pointer to 32-byte
    andq $-32, %rsp
    # Make some space for w[0] through w[15] on the stack for later
    subq $512, %rsp

    # Do the loads and byteswaps and store on stack
    # Note that only w[0] through w[7] are stored on the stack as w[7] through w[15] are transposed
    # first before being stored. We need the extra registers during transposing.
    # w[0] and w[8]
    vmovdqa (%rsi), %ymm0
    vpshufb (%rdx), %ymm0, %ymm0
    vmovdqa %ymm0, (%rsp)
    vmovdqa 32(%rsi), %ymm8
    vpshufb (%rdx), %ymm8, %ymm8
    # w[1] and w[9]
    vmovdqa 64(%rsi), %ymm1
    vpshufb (%rdx), %ymm1, %ymm1
    vmovdqa %ymm1, 32(%rsp)
    vmovdqa 96(%rsi), %ymm9
    vpshufb (%rdx), %ymm9, %ymm9
    # w[2] and w[10]
    vmovdqa 128(%rsi), %ymm2
    vpshufb (%rdx), %ymm2, %ymm2
    vmovdqa %ymm2, 64(%rsp)
    vmovdqa 160(%rsi), %ymm10
    vpshufb (%rdx), %ymm10, %ymm10
    # w[3] and w[11]
    vmovdqa 192(%rsi), %ymm3
    vpshufb (%rdx), %ymm3, %ymm3
    vmovdqa %ymm3, 96(%rsp)
    vmovdqa 224(%rsi), %ymm11
    vpshufb (%rdx), %ymm11, %ymm11
    # w[4] and w[12]
    vmovdqa 256(%rsi), %ymm4
    vpshufb (%rdx), %ymm4, %ymm4
    vmovdqa %ymm4, 128(%rsp)
    vmovdqa 288(%rsi), %ymm12
    vpshufb (%rdx), %ymm12, %ymm12
    # w[5] and w[13]
    vmovdqa 320(%rsi), %ymm5
    vpshufb (%rdx), %ymm5, %ymm5
    vmovdqa %ymm5, 160(%rsp)
    vmovdqa 352(%rsi), %ymm13
    vpshufb (%rdx), %ymm13, %ymm13
    # w[6] and w[14]
    vmovdqa 384(%rsi), %ymm6
    vpshufb (%rdx), %ymm6, %ymm6
    vmovdqa %ymm6, 192(%rsp)
    vmovdqa 416(%rsi), %ymm14
    vpshufb (%rdx), %ymm14, %ymm14
    # w[7] and w[15]
    vmovdqa 448(%rsi), %ymm7
    vpshufb (%rdx), %ymm7, %ymm7
    vmovdqa %ymm7, 224(%rsp)
    vmovdqa 480(%rsi), %ymm15
    vpshufb (%rdx), %ymm15, %ymm15

    # Transpose w[8] through w[15]
    # tmp[0] through tmp0[7]
    vpunpckldq %ymm9, %ymm8, %ymm0
    vpunpckhdq %ymm9, %ymm8, %ymm1
    vpunpckldq %ymm11, %ymm10, %ymm2
    vpunpckhdq %ymm11, %ymm10, %ymm3
    vpunpckldq %ymm13, %ymm12, %ymm4
    vpunpckhdq %ymm13, %ymm12, %ymm5
    vpunpckldq %ymm15, %ymm14, %ymm6
    vpunpckhdq %ymm15, %ymm14, %ymm7
    # tmp1[0] through tmp1[7]
    vpunpcklqdq %ymm2, %ymm0, %ymm8
    vpunpckhqdq %ymm2, %ymm0, %ymm9
    vpunpcklqdq %ymm3, %ymm1, %ymm10
    vpunpckhqdq %ymm3, %ymm1, %ymm11
    vpunpcklqdq %ymm6, %ymm4, %ymm12
    vpunpckhqdq %ymm6, %ymm4, %ymm13
    vpunpcklqdq %ymm7, %ymm5, %ymm14
    vpunpckhqdq %ymm7, %ymm5, %ymm15
    # transposed w[8] through w[15]
    vperm2i128 $32, %ymm12, %ymm8, %ymm0
    vperm2i128 $32, %ymm13, %ymm9, %ymm1
    vperm2i128 $32, %ymm14, %ymm10, %ymm2
    vperm2i128 $32, %ymm15, %ymm11, %ymm3
    vperm2i128 $49, %ymm12, %ymm8, %ymm4
    vperm2i128 $49, %ymm13, %ymm9, %ymm5
    vperm2i128 $49, %ymm14, %ymm10, %ymm6
    vperm2i128 $49, %ymm15, %ymm11, %ymm7

    # w[0] through w[7] put back into registers and transposed w[8] through w[15] put on stack
    # These can technically be interleaved with the code below and above since they occupy different execution
    # ports but out-of-order execution already takes care of this.
    vmovdqa (%rsp), %ymm8
    vmovdqa 32(%rsp), %ymm9
    vmovdqa 64(%rsp), %ymm10
    vmovdqa 96(%rsp), %ymm11
    vmovdqa 128(%rsp), %ymm12
    vmovdqa 160(%rsp), %ymm13
    vmovdqa 192(%rsp), %ymm14
    vmovdqa 224(%rsp), %ymm15
    vmovdqa %ymm0, 256(%rsp)
    vmovdqa %ymm1, 288(%rsp)
    vmovdqa %ymm2, 320(%rsp)
    vmovdqa %ymm3, 352(%rsp)
    vmovdqa %ymm4, 384(%rsp)
    vmovdqa %ymm5, 416(%rsp)
    vmovdqa %ymm6, 448(%rsp)
    vmovdqa %ymm7, 480(%rsp)

    # transpose of w[0] through w[7]
    # tmp[0] through tmp0[7]
    vpunpckldq %ymm9, %ymm8, %ymm0
    vpunpckhdq %ymm9, %ymm8, %ymm1
    vpunpckldq %ymm11, %ymm10, %ymm2
    vpunpckhdq %ymm11, %ymm10, %ymm3
    vpunpckldq %ymm13, %ymm12, %ymm4
    vpunpckhdq %ymm13, %ymm12, %ymm5
    vpunpckldq %ymm15, %ymm14, %ymm6
    vpunpckhdq %ymm15, %ymm14, %ymm7
    # tmp1[0] through tmp1[7]
    vpunpcklqdq %ymm2, %ymm0, %ymm8
    vpunpckhqdq %ymm2, %ymm0, %ymm9
    vpunpcklqdq %ymm3, %ymm1, %ymm10
    vpunpckhqdq %ymm3, %ymm1, %ymm11
    vpunpcklqdq %ymm6, %ymm4, %ymm12
    vpunpckhqdq %ymm6, %ymm4, %ymm13
    vpunpcklqdq %ymm7, %ymm5, %ymm14
    vpunpckhqdq %ymm7, %ymm5, %ymm15
    # transposed w[0] through w[7]
    vperm2i128 $32, %ymm12, %ymm8, %ymm0
    vperm2i128 $32, %ymm13, %ymm9, %ymm1
    vperm2i128 $32, %ymm14, %ymm10, %ymm2
    vperm2i128 $32, %ymm15, %ymm11, %ymm3
    vperm2i128 $49, %ymm12, %ymm8, %ymm4
    vperm2i128 $49, %ymm13, %ymm9, %ymm5
    vperm2i128 $49, %ymm14, %ymm10, %ymm6
    vperm2i128 $49, %ymm15, %ymm11, %ymm7

    # transposed w[0] through w[7] put back onto the stack. These are needed at the start
    # and after 16 rounds so we're forced to store them on the stack.
    vmovdqa %ymm0, (%rsp)
    vmovdqa %ymm1, 32(%rsp)
    vmovdqa %ymm2, 64(%rsp)
    vmovdqa %ymm3, 96(%rsp)
    vmovdqa %ymm4, 128(%rsp)
    vmovdqa %ymm5, 160(%rsp)
    vmovdqa %ymm6, 192(%rsp)
    vmovdqa %ymm7, 224(%rsp)

    # Load the initial state (s[0] through s[7]) in ymm registers before doing the rounds
    vmovdqa (%rdi), %ymm8
    vmovdqa 32(%rdi), %ymm9
    vmovdqa 64(%rdi), %ymm10
    vmovdqa 96(%rdi), %ymm11
    vmovdqa 128(%rdi), %ymm12
    vmovdqa 160(%rdi), %ymm13
    vmovdqa 192(%rdi), %ymm14
    vmovdqa 224(%rdi), %ymm15

    # Current register status: ymm0-7 contain w[0]-w[7]. ymm8-15 contain s[0]-s[7]

    # Since sha256_round does not use ymm0-3 we don't have to load the first few as they are still in registers.
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15,  0, %ymm0
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14,  1, %ymm1
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13,  2, %ymm2
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 3, %ymm3
    vmovdqa 128(%rsp), %ymm0
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 4, %ymm0
    vmovdqa 160(%rsp), %ymm0
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 5, %ymm0
    vmovdqa 192(%rsp), %ymm0
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 6, %ymm0
    vmovdqa 224(%rsp), %ymm0
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 7, %ymm0
    vmovdqa 256(%rsp), %ymm0
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, 8, %ymm0
    vmovdqa 288(%rsp), %ymm0
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, 9, %ymm0
    vmovdqa 320(%rsp), %ymm0
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, 10, %ymm0
    vmovdqa 352(%rsp), %ymm0
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 11, %ymm0
    vmovdqa 384(%rsp), %ymm0
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 12, %ymm0
    vmovdqa 416(%rsp), %ymm0
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 13, %ymm0
    vmovdqa 448(%rsp), %ymm0
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 14, %ymm0
    vmovdqa 480(%rsp), %ymm0
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 15, %ymm0
    new_w 14, 0, 9, 1, 16
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, 16, %ymm0
    new_w 15, 1, 10, 2, 17
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, 17, %ymm0
    new_w 16, 2, 11, 3, 18
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, 18, %ymm0
    new_w 17, 3, 12, 4, 19
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 19, %ymm0
    new_w 18, 4, 13, 5, 20
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 20, %ymm0
    new_w 19, 5, 14, 6, 21
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 21, %ymm0
    new_w 20, 6, 15, 7, 22
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 22, %ymm0
    new_w 21, 7, 16, 8, 23
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 23, %ymm0
    new_w 22, 8, 17, 9, 24
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, 24, %ymm0
    new_w 23, 9, 18, 10, 25
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, 25, %ymm0
    new_w 24, 10, 19, 11, 26
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, 26, %ymm0
    new_w 25, 11, 20, 12, 27
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 27, %ymm0
    new_w 26, 12, 21, 13, 28
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 28, %ymm0
    new_w 27, 13, 22, 14, 29
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 29, %ymm0
    new_w 28, 14, 23, 15, 30
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 30, %ymm0
    new_w 29, 15, 24, 16, 31
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 31, %ymm0
    new_w 30, 16, 25, 17, 32
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, 32, %ymm0
    new_w 31, 17, 26, 18, 33
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, 33, %ymm0
    new_w 32, 18, 27, 19, 34
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, 34, %ymm0
    new_w 33, 19, 28, 20, 35
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 35, %ymm0
    new_w 34, 20, 29, 21, 36
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 36, %ymm0
    new_w 35, 21, 30, 22, 37
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 37, %ymm0
    new_w 36, 22, 31, 23, 38
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 38, %ymm0
    new_w 37, 23, 32, 24, 39
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 39, %ymm0
    new_w 38, 24, 33, 25, 40
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, 40, %ymm0
    new_w 39, 25, 34, 26, 41
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, 41, %ymm0
    new_w 40, 26, 35, 27, 42
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, 42, %ymm0
    new_w 41, 27, 36, 28, 43
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 43, %ymm0
    new_w 42, 28, 37, 29, 44
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 44, %ymm0
    new_w 43, 29, 38, 30, 45
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 45, %ymm0
    new_w 44, 30, 39, 31, 46
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 46, %ymm0
    new_w 45, 31, 40, 32, 47
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 47, %ymm0
    new_w 46, 32, 41, 33, 48
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, 48, %ymm0
    new_w 47, 33, 42, 34, 49
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, 49, %ymm0
    new_w 48, 34, 43, 35, 50
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, 50, %ymm0
    new_w 49, 35, 44, 36, 51
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 51, %ymm0
    new_w 50, 36, 45, 37, 52
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 52, %ymm0
    new_w 51, 37, 46, 38, 53
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 53, %ymm0
    new_w 52, 38, 47, 39, 54
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 54, %ymm0
    new_w 53, 39, 48, 40, 55
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 55, %ymm0
    new_w 54, 40, 49, 41, 56
    sha256_round %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, 56, %ymm0
    new_w 55, 41, 50, 42, 57
    sha256_round %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, 57, %ymm0
    new_w 56, 42, 51, 43, 58
    sha256_round %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, 58, %ymm0
    new_w 57, 43, 52, 44, 59
    sha256_round %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, %ymm12, 59, %ymm0
    new_w 58, 44, 53, 45, 60
    sha256_round %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, %ymm11, 60, %ymm0
    new_w 59, 45, 54, 46, 61
    sha256_round %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, %ymm10, 61, %ymm0
    new_w 60, 46, 55, 47, 62
    sha256_round %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, %ymm9, 62, %ymm0
    new_w 61, 47, 56, 48, 63
    sha256_round %ymm9, %ymm10, %ymm11, %ymm12, %ymm13, %ymm14, %ymm15, %ymm8, 63, %ymm0

    # Add initial state to updated state and store them back
    vpaddd (%rdi), %ymm8, %ymm8
    vpaddd 32(%rdi), %ymm9, %ymm9
    vpaddd 64(%rdi), %ymm10, %ymm10
    vpaddd 96(%rdi), %ymm11, %ymm11
    vpaddd 128(%rdi), %ymm12, %ymm12
    vpaddd 160(%rdi), %ymm13, %ymm13
    vpaddd 192(%rdi), %ymm14, %ymm14
    vpaddd 224(%rdi), %ymm15, %ymm15
    vmovdqa %ymm8, (%rdi)
    vmovdqa %ymm9, 32(%rdi)
    vmovdqa %ymm10, 64(%rdi)
    vmovdqa %ymm11, 96(%rdi)
    vmovdqa %ymm12, 128(%rdi)
    vmovdqa %ymm13, 160(%rdi)
    vmovdqa %ymm14, 192(%rdi)
    vmovdqa %ymm15, 224(%rdi)

    # Functions should clear YMM registers upon return
    vzeroupper
    # Restore stack and frame pointer
    leave
    ret
