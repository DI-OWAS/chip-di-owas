# Crypto Core — Design & Host Programming Manual

**Switchable AES-128 CTR / CMAC / CCM crypto-DMA accelerator with an AXI4-Lite control plane
and an AXI4 master data plane.**

This document describes (1) what the core does, (2) every module, (3) the **data byte-order
conventions** the host must follow, and (4) how a host drives the core — the register map,
every control/status bit, and a step-by-step procedure **per mode**.

> **Status at a glance.** A single AES-128 engine is shared by three run-time-selectable
> modes: **CTR** (confidentiality), **CMAC** (authentication), **CCM** (authenticated
> encryption, both directions). All modes stream over the DMA data plane and support
> whole-block and word-aligned partial payloads. The integration testbench
> `tb_cryptoCore_dma` passes **34/34**.

---

## 1. Overview

Two interfaces, like every accelerator on the SoC crossbar:

- **REG-IF — AXI4-Lite slave (control plane).** Configure mode/key/nonce, program a transfer,
  start it, poll status, read the result tag.
- **DATA-IF — AXI4 full master (data plane).** The core autonomously reads source data and
  writes results over the crossbar (a "crypto-DMA"). The host supplies a source address, a
  destination address, and a length — not the data itself.

### 1.1 The three modes (plus bypass)

`CTRL.MODE` (2 bits) selects the function the shared AES engine performs:

| MODE | Function | What it does / produces |
|---|---|---|
| `0` | **CTR** | AES-128 Counter mode. Confidentiality only; encrypt = decrypt. Streams ciphertext/plaintext to `DST_ADDR`. |
| `1` | **CMAC** | AES-CMAC (SP 800-38B / RFC 4493). Authentication only; reads the message, produces a 128-bit **tag** in `TAG_OUT`. No data written back. |
| `2` | **CCM** | AES-CCM (SP 800-38C). Authenticated encryption. Encrypt (`DECRYPT=0`): ciphertext → `DST_ADDR`, tag `U` → `TAG_OUT`. Decrypt+verify (`DECRYPT=1`): plaintext → `DST_ADDR`, sets `STATUS.AUTH_OK`. |

`CTRL.BYPASS` = plain memory-to-memory copy (no crypto).

**Shared AES engine.** There is exactly one AES-128 engine. A combinational arbiter
(`aesArbiter`) routes its inputs to the active mode's controller (CTR FSM, `cmacEngine`, or
`ccmEngine`); its outputs broadcast to all three. Adding CMAC/CCM cost mostly control logic,
not a second cipher. All three modes use **AES encryption only** (CTR/CCM decryption XORs
against forward keystream), so no inverse cipher is needed.

### 1.2 Key properties

- **Algorithm:** AES-128. CTR block = `IV(96) || counter(32)`; CMAC per RFC 4493; CCM per
  SP 800-38C with `q=2` (13-byte nonce), `Tlen=16` (full tag), **no AAD** (current scope).
- **Crypto-DMA:** one AXI4 master port; 32-bit data path (four beats per 128-bit block).
- **Partial payloads:** whole-block and word-aligned (multiples of 4 bytes). Sub-word tails
  not yet supported (§6).
- **Two key slots** `key1`/`key2` (`CTRL.KEY_SEL`), provisioned at boot (`BOOT_ENABLE=1`) or
  loaded from the fixed test keys `STATIC_KEY1/2` after reset (`BOOT_ENABLE=0`, default).
- **CTR nonce-uniqueness:** 96-bit IV + 32-bit hardware counter (auto-increment, no rollback);
  a pre-flight gate refuses transfers that would exhaust the per-IV budget or use an unloaded key.
- **Hardening:** keys never readable over either bus; async-zeroize on reset.

### 1.3 Boot / key provisioning

On reset, `bootCtrl` DMA-fetches an encrypted bitstream, decrypts it on the shared AES, and
writes the recovered keys into `keyStorage`. During boot, `boot_active` forces the arbiter to
CTR and **gates host register writes**; `STATUS.BOOT_DONE` rises when done. **Wait for
`BOOT_DONE` before configuring a transfer.** Details in `boot_path_spec.md`.

The boot sequence is enabled by the top-level parameter **`BOOT_ENABLE`** (default **0**):

| `BOOT_ENABLE` | After reset |
|---|---|
| 1 | `bootCtrl` runs the sequence above (DATA-IF reads at `BOOT_SRC_ADDR`, writes to `BOOT_SRC_ADDR` and `BOOT_DST_ADDR`). |
| 0 (default) | No boot and **no DATA-IF accesses**. `BOOT_DONE=1` immediately. One clock after reset, `key1`/`key2` are loaded from the parameters `STATIC_KEY1` (default NIST SP 800-38A key `2b7e1516…`) and `STATIC_KEY2` (default FIPS-197 C.1 key `00010203…`). |

With `BOOT_ENABLE=0` the keys are **public test keys** — there is no confidentiality, and
"keys zeroize on reset" only holds until the first clock after reset.

### 1.4 Data-plane pipeline

```
Memory <--AXI--> axi_dma <--AXIS--> aesStreamAdapter --block--> [ cryptoCoreFSM (CTR)   ]
                                                                [ cmacEngine            ] --> aesArbiter --> AES128
                                                                [ ccmEngine             ]        (mode mux)     |
                                          keyStorage ---------> (key_out)                  io_dataOut broadcast <-
```

The adapter gathers 128-bit blocks from the read stream and feeds the active engine; for
CTR/CCM it scatters the engine's output to the write stream; for CMAC it writes nothing (tag
goes to a register). Bypass routes read beats straight to write beats.

---

## 2. Module reference

| Module | Role |
|---|---|
| `cryptoCore` (top) | Exposes REG-IF + DATA-IF; instantiates arbiter + all engines; decodes CTRL (`mode=CTRL[3:2]`, `decrypt=CTRL[4]`), assembles 8-bit STATUS, generates `eng_start`, latches `TAG_OUT`/`AUTH_OK`, sets `read_only`/length per mode. `eff_mode = boot_active ? CTR : mode`. |
| `aesArbiter` | Combinational 3:1 mux of the AES inputs by `eff_mode`; outputs broadcast to all engines. **`boot_active` forces CTR.** |
| `cmacEngine` | AES-CMAC: subkeys K1/K2 from `AES_K(0)`, CBC-MAC chain, final block XOR K1/K2. Block interface + `tag`/`tag_valid`. Validated vs RFC 4493. |
| `ccmEngine` | AES-CCM: builds B0, single-pass interleaved CTR-then-MAC (2 AES ops/block), tag `U=T⊕S0`; `decrypt` selects direction; reports `auth_ok`. `q=2`, `Tlen=16`, no AAD. Validated vs SP 800-38C. |
| `axi4LiteRegister` | REG-IF register file (§4). Writes gated while `boot_active`. |
| `cryptoDmaCtrl` | Descriptor controller + safety gate. Byte-length = `engine_mode ? payload_len : (DMA_BLOCKS<<4)`; `read_only` (CMAC) skips the write descriptor. |
| `aesStreamAdapter` | 32-bit AXIS ↔ 128-bit engine bridge. Mode-aware feed/scatter; partial-block re-justify (§3). |
| `cryptoCoreFSM` | CTR block controller (`cipher_out = io_dataOut ⊕ cipher_in`); also the boot master. |
| `bootCtrl` | Boot/key-provisioning sequencer; holds `boot_active`, then `boot_done`. |
| `keyStorage` | Two 128-bit keys; no AXI write path; never readable; async-zeroize. |
| `AES128_Sec_0_Area_0` | Generated AES-128, encrypt-only, ≈161 cyc/block. Black box. |
| `axi_dma`, `axi_ram` | Third-party DMA engine; verification-only RAM. |

---

## 3. Data byte-order conventions

Everything follows **"byte 0 is the most-significant byte"** (big-endian at the value level),
matching the AES/NIST convention. A driver **must** match these exactly.

### 3.1 128-bit data blocks in memory (DMA)

Each aligned 16-byte region is one 128-bit big-endian value `V` (byte 0 = MSB). Store as four
little-endian 32-bit words:

```
word[base+0]=V[31:0]   word[base+4]=V[63:32]   word[base+8]=V[95:64]   word[base+12]=V[127:96]
```

Example — block `V = 6bc1bee2 2e409f96 e93d7e11 7393172a`:

```
word[base+0]=7393172a  word[base+4]=e93d7e11  word[base+8]=2e409f96  word[base+12]=6bc1bee2
```

(TB helpers `preload_block(addr,V)` / `read_block(addr)` do this / reverse it.)

### 3.2 Word-aligned partial (short) last block

If the payload length is a multiple of 4 but not 16, the final block is short. Store its valid
words **byte-forward at the low addresses**: first 4 tail bytes `t0 t1 t2 t3` → word
`t0t1t2t3` (t0 = MSB) at `word[base+0]`, next 4 at `word[base+4]`, … Example — 4-byte tail
`ae 2d 8a 57` → `word[base+0]=ae2d8a57`. The adapter re-justifies to the engine's top-of-word
form automatically. **Sub-word tails (length not a multiple of 4) are not supported yet.**

### 3.3 Nonce and tag registers

Also big-endian at the value level: byte 0 in the most-significant bits; register index 0 =
least-significant 32-bit word.

**CCM nonce (13 bytes):** `N0…N12` → value `N0`(MSB)…`N12`(LSB):

```
CCM_NONCE_0 (0x64) = nonce[31:0]     CCM_NONCE_2 (0x6C) = nonce[95:64]
CCM_NONCE_1 (0x68) = nonce[63:32]    CCM_NONCE_3 (0x70) = nonce[103:96]  (low byte)
```
Example `N = 00 11 22 33 44 55 66 77 88 99 aa bb cc`:
```
CCM_NONCE_0=0x99aabbcc  CCM_NONCE_1=0x55667788  CCM_NONCE_2=0x11223344  CCM_NONCE_3=0x00000000
```

**Tag (16 bytes):** `TAG_*_0` = bits[31:0] … `TAG_*_3` = bits[127:96]. Example
`U = 4918ab9a e37c7739 d4a9e14a 28a9c6e0`:
```
TAG_x_0=0x28a9c6e0  TAG_x_1=0xd4a9e14a  TAG_x_2=0xe37c7739  TAG_x_3=0x4918ab9a
```

---

## 4. Register map

All registers 32 bits; offsets are byte addresses from the peripheral base.

| Offset | Name | Acc. | Description |
|---|---|---|---|
| `0x00` | CTRL | R/W | Control (§4.1). |
| `0x04` | STATUS | R | Status (§4.2). |
| `0x40` | CTR_NONCE_1 | R/W | CTR IV[31:0]. **Write resets counter & clears overflow.** |
| `0x44` | CTR_NONCE_2 | R/W | CTR IV[63:32]. (resets counter) |
| `0x48` | CTR_NONCE_3 | R/W | CTR IV[95:64]. (resets counter) |
| `0x50` | SRC_ADDR | R/W | Source byte address. |
| `0x54` | DST_ADDR | R/W | Destination byte address. |
| `0x58` | DMA_BLOCKS | R/W | CTR/bypass length in 128-bit blocks. |
| `0x5C` | GO | R/W | Write bit0=1 to start (one-shot). |
| `0x60` | DMA_STATUS | R | bit0 dma_busy, bit1 dma_done, bit2 dma_error. |
| `0x64`–`0x70` | CCM_NONCE_0..3 | R/W | CCM 13-byte nonce (§3.3). |
| `0x74` | PAYLOAD_LEN | R/W | CMAC/CCM payload length in **bytes**. |
| `0x80`–`0x8C` | TAG_IN_0..3 | R/W | CCM-decrypt received tag `U` (§3.3). |
| `0x90`–`0x9C` | TAG_OUT_0..3 | R | Result tag (CMAC tag / CCM `U`), latched at engine done. |

### 4.1 CTRL (0x00)

| Bits | Name | Meaning |
|---|---|---|
| 0 | KEY_SEL | 0 = key1, 1 = key2. |
| 1 | BYPASS | 1 = plain DMA copy. |
| 3:2 | MODE | 0 = CTR, 1 = CMAC, 2 = CCM. |
| 4 | DECRYPT | CCM only: 0 = encrypt, 1 = decrypt+verify. |

### 4.2 STATUS (0x04)

| Bit | Name | Meaning |
|---|---|---|
| 0 | BUSY | Per-block AES FSM busy (CTR path). |
| 1 | DONE | Per-block result latched (CTR path). |
| 2 | BOOT_DONE | Boot/key provisioning complete. **Wait for this before configuring.** |
| 3 | KEY1_VALID | key1 loaded. |
| 4 | KEY2_VALID | key2 loaded. |
| 5 | CTR_OVERFLOW | CTR counter saturated; CTR refused until a new IV is written. |
| 6 | ENGINE_DONE | CMAC/CCM complete; TAG_OUT/AUTH_OK valid. Cleared on next start. |
| 7 | AUTH_OK | CCM decrypt: 1 if tag verified. |

**Which "done" to poll:** CTR/bypass → `DMA_STATUS.dma_done` (0x60). CMAC/CCM →
`STATUS.ENGINE_DONE` (bit 6); the tag is produced slightly after the DMA read, so `dma_done`
alone is too early.

---

## 5. Operating procedures (per mode)

Prereqs for all: wait `BOOT_DONE=1`; for non-bypass ensure the selected key slot is valid.

**CTR (MODE=0) — encrypt/decrypt**
```
write IV -> 0x40,0x44,0x48        ; resets counter, clears overflow
CTRL     -> KEY_SEL, MODE=0, BYPASS=0
SRC/DST/DMA_BLOCKS -> 0x50/0x54/0x58
GO=1 -> 0x5C ; poll 0x60 dma_done; check dma_error
result: read from memory at DST_ADDR
```
Decrypt = same with SRC=ciphertext and the same IV/counter.

**CMAC (MODE=1) — authenticate**
```
message in memory at SRC_ADDR (byte-order per §3)
PAYLOAD_LEN -> 0x74 = message bytes
CTRL -> KEY_SEL, MODE=1 ; SRC_ADDR -> 0x50 ; DMA_BLOCKS -> 0x58
GO=1 ; poll ENGINE_DONE (STATUS bit6); read TAG_OUT (0x90..0x9C) = 128-bit tag
```
No data is written back (read-only DMA).

**CCM encrypt (MODE=2, DECRYPT=0)**
```
plaintext at SRC_ADDR ; CCM_NONCE_0..3 (0x64..0x70) ; PAYLOAD_LEN (0x74)
CTRL -> KEY_SEL, MODE=2, DECRYPT=0 ; SRC/DST/DMA_BLOCKS
GO=1 ; poll ENGINE_DONE ; ciphertext at DST_ADDR ; TAG_OUT = encrypted tag U
```

**CCM decrypt & verify (MODE=2, DECRYPT=1)**
```
ciphertext at SRC_ADDR ; TAG_IN_0..3 (0x80..0x8C) = received U
CCM_NONCE_0..3, PAYLOAD_LEN as above ; CTRL: MODE=2, DECRYPT=1
GO=1 ; poll ENGINE_DONE ; plaintext at DST_ADDR ; check STATUS.AUTH_OK (bit7)
```
> **Do not trust the recovered plaintext unless `AUTH_OK=1`** — it is streamed out before
> verification; a failed `AUTH_OK` means tampering, discard the plaintext.

**Common notes**
- `PAYLOAD_LEN` drives the DMA byte-length for CMAC/CCM — set it for **every** engine-mode
  transfer (a stale value transfers the wrong number of bytes).
- Word-aligned partial lengths are supported; place the tail per §3.2.
- Reset zeroizes keys & clears registers — re-provision (boot) after any reset.

### 5.1 Worked examples (`tb_cryptoCore_dma`, key1 = `2b7e1516…cf4f3c`)

| Test | Configuration | Result |
|---|---|---|
| CTR 4 blk (T2/T3) | counter=`f0f1…feff`, 4-block NIST plaintext @0x0000 | ct `874d6191…` @0x1000; re-run decrypts back |
| CMAC 16 B (T6) | MODE=1, PAYLOAD_LEN=16, msg `6bc1…172a` | TAG_OUT = `070a16b4 6b4d4144 f79bdd9d d04a287c` |
| CMAC 20 B partial (T9) | MODE=1, PAYLOAD_LEN=20 (16+4 tail) | TAG_OUT = `7d85449e a6ea19c8 23a7bf78 837dfade` |
| CCM enc 20 B (T10) | MODE=2 DEC=0, nonce `0011…cc`, PAYLOAD_LEN=20 | ct `712ef053…6a4cf70a`+`0cbe8409`; U=`d75e527f…14fcfa9a` |
| CCM dec 20 B (T11) | MODE=2 DEC=1, TAG_IN=U | plaintext `2021…33`; AUTH_OK=1 |

---

## 6. Verification & limitations

**Verification**
- `tb_cryptoCore_dma` — top-level integration, **34/34**: CTR enc/dec/bypass, register R/W,
  CMAC & CCM (enc+dec) over DMA, whole-block + word-aligned partial. Waits for `BOOT_DONE`.
- `tb_cryptoCore_safety` — counter overflow, key isolation, reset-during-op, no-key refusal.
- Engine/unit TBs: `tb_cmacEngine` (RFC 4493), `tb_ccmEngine` (SP 800-38C + tamper),
  `tb_aesArbiter` (mode routing/no contention), `tb_axi4LiteRegs`, `tb_cryptoCoreFSM`,
  `tb_keyStorage`.
- `tb/ccm_ref.py` — pure-Python AES-CMAC/CCM reference (validated vs RFC 4493 & SP 800-38C),
  regenerates test vectors.

**Known limitations**
- **Sub-word partial tails not supported** — payloads must be a multiple of 4 bytes (arbitrary
  byte lengths need `tkeep` handling both directions).
- **CCM scope:** no AAD, fixed 16-byte tag, `q=2`.
- **DMA refuse gate** counter-overflow check is CTR-specific; for CMAC/CCM the host writes a
  fresh IV (zeroing the counter) so it doesn't spuriously refuse — a mode-aware gate is a
  pending cleanup.
- **Byte-order convention** (§3) is big-endian at the 128-bit level, inherited from the CTR
  path; unifying with a natural little-endian layout is a possible future change.
- **DATA-IF bus widths** (32/16) are placeholders pending the crossbar parameters.
- The AES engine is an unmodified generated black box; all mode logic is in surrounding RTL.
