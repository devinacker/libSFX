; libSFX LZ4 Decompression
; David Lindecrantz <optiroc@gmail.com>
;
; LZ4 homepage:
; https://github.com/Cyan4973/lz4
;
; Another 65816 implementation by Olivier Zardini:
; http://www.brutaldeluxe.fr/products/crossdevtools/lz4/
;   Relying heavily on self-modification, this implementation is
;   faster and smaller. But for SNES use it has its limits:
;   - Can't run from ROM
;   - Fixed source and destination offsets
;   - Compressed size needed as parameter

.include "../libSFX.i"
.segment "LIBSFX"

;-------------------------------------------------------------------------------

/**
  SFX_LZ4_decompress
  Decompress LZ4 frame
  [a8i16, ret:a16i16]

  :in:  x       Source offset
  :in:  y       Destination offset
  :in:  b:a     Destination:Source banks

  :out: a       Decompressed length
*/
SFX_LZ4_decompress:
        jsr     Setup
        jsr     ReadHeader
        jsr     DecodeBlock
        rtl


/**
  SFX_LZ4_decompress_block
  Decompress LZ4 block
  [a8i16, ret:a16i16]

  :in:  x       Source offset
  :in:  y       Destination offset
  :in:  b:a     Destination:Source banks

  :out: a       Decompressed length
*/
SFX_LZ4_decompress_block:
        jsr     Setup
        jsr     DecodeBlock
        rtl


;-------------------------------------------------------------------------------
;Scratch pad usage
.define LZ_source _ZPAD_+$00    ;Source (indirect long)
.define LZ_dest _ZPAD_+$03      ;Destination (indirect long)
.define LZ_mvl _ZPAD_+$06       ;Literal block move (mvn + banks + return)
.define LZ_mvm _ZPAD_+$0a       ;Match block move (mvn + banks + return)
.define LZ_blockend _ZPAD_+$0e  ;End address for current block

Setup:
        stx     LZ_source+$00   ;Set source for indirect and block move addressing
        sta     LZ_source+$02
        sta     LZ_mvl+$02

        xba                     ;Set destination for indirect and block move addressing
        sty     LZ_dest+$00
        sta     LZ_dest+$02
        sta     LZ_mvl+$01
        sta     LZ_mvm+$01
        sta     LZ_mvm+$02

        lda     #$54            ;Write MVN and RTS/RTL instructions
        sta     LZ_mvl+$00
        sta     LZ_mvm+$00
  .if ROM_MAPMODE <> 1
        lda     #$60            ;LoROM mapping = RTS
  .else
        lda     #$6b            ;HiROM mapping = RTL
  .endif
        sta     LZ_mvl+$03
        sta     LZ_mvm+$03
        rts

ReadHeader:
        jsr     Skip4           ;Skip LZ4 Magic number
        lda     [LZ_source]     ;Read FLG byte
        inc     LZ_source       ;Skip FLG+BD bytes
        inc     LZ_source
        and     #%00001000      ;Check content size bit
                                ;b2 = Content checksum
                                ;b3 = Content size
                                ;b4 = Block checksum
                                ;b5 = Blocks independent
        beq     :+
        jsr     Skip4           ;If content size present, skip 4 more bytes
:       inc     LZ_source       ;Skip header checksum
        rts

DecodeBlock:
        RW a16
        ldy     LZ_dest         ;Store destination offset for decompressed size calculation
        phy
        lda     [LZ_source]     ;Read lower 16 bits of block size
        jsr     Skip4           ;Skip block size
        add     LZ_source       ;Store block end offset
        sta     LZ_blockend


ReadToken:
        lda     [LZ_source]     ;Read token byte
        pha                     ;Save for @Match
        inc     LZ_source

        and     #$00f0          ;Check high nibble
        beq     @IsBlockDone    ;Zero: No literal

@Literal:
        lsr                     ;Compute literal length
        lsr
        lsr
        lsr
        cmp     #$000f          ;Short literal?
        bne     @CopyLiteral
        jsr     @AddLength

@CopyLiteral:
        ldx     LZ_source       ;Length in A, perform block move
        ldy     LZ_dest
        dec
        phb
  .if ROM_MAPMODE <> 1
        jsr     LZ_mvl          ;LoROM mapping = JSR
  .else
        jsl     LZ_mvl          ;HiROM mapping = JSL
  .endif
        plb
        stx     LZ_source       ;Copy offsets
        sty     LZ_dest


@IsBlockDone:
        lda     LZ_blockend
        cmp     LZ_source
        beq     @BlockDone


@Match:
        pla                     ;Pull block token
        tax                     ;Stash

        lda     [LZ_source]     ;Read match offset (word)
        pha                     ;and save on stack for @CopyMatch
        inc     LZ_source
        inc     LZ_source

        txa                     ;Swap back token
        and     #$000f          ;Check low nibble
        cmp     #$000f          ;Short match length?
        bne     @CopyMatch
        jsr     @AddLength

@CopyMatch:
        tay                     ;Length in A
        lda     LZ_dest         ;Copy from dest
        sec
        sbc     1,s             ;Offset on stack
        tax
        pla                     ;Unwind

        tya
        add     #$03
        ldy     LZ_dest
        phb
  .if ROM_MAPMODE <> 1
        jsr     LZ_mvm          ;LoROM mapping = JSR
  .else
        jsl     LZ_mvm          ;HiROM mapping = JSL
  .endif
        plb
        sty     LZ_dest         ;Copy destination offset

        bra     ReadToken


@BlockDone:
        pla
        lda     LZ_dest         ;Calculate decompressed size
        sec
        sbc     1,s             ;Start offset on stack
        plx                     ;Unwind
        rts


@AddLength:
        pha                     ;Accumulated length at s+1
:       lda     [LZ_source]     ;Read next length byte
        inc     LZ_source
        tay
        and     #$00ff          ;Add to length
        clc
        adc     1,s
        sta     1,s

        tya                     ;Check end condition: length byte != #$ff
        RW a8
        inc
        RW a16
        beq     :-

        pla                     ;Done: pull back summed length
        rts


Skip4:  inc     LZ_source       ;Skip 4 bytes
Skip3:  inc     LZ_source       ;Skip 3 bytes
        inc     LZ_source
        inc     LZ_source
        rts
