# Boot Path — Specification & Open Questions (Brainstorm)

> **Status:** brainstorming / scoping. Nothing here is committed yet. The goal of
> this document is to pin down *what we need to know* (about the bitstream, the key
> source, and the core's contract) **before** writing any boot-path RTL.

---

## 1. Why a boot path is needed (current reality)

The runtime datapath is finished and verified, but the core **cannot load a key on
real hardware today**. Everything that makes the testbench pass is a stand-in:

| Concern | Current state in RTL | File / line |
|---|---|---|
| Key write-enables to `keyStorage` | Hardwired to `0` in the FSM ("change later when implementing boot phase") | [cryptoCoreFSM.v:96-99](../rtl/cryptoCoreFSM.v#L96-L99) |
| `boot_done` status bit | Hardwired to `1'b1` (faked) | [cryptoCore.v:74](../rtl/cryptoCore.v#L74) |
| Reserved FSM states for boot | Comment placeholder `3'd4..3'd6`, no states implemented | [cryptoCoreFSM.v:56](../rtl/cryptoCoreFSM.v#L56) |
| How keys actually get into `keyStorage` today | Testbench `force`/`release` (sim-only hack) | [tb_cryptoCore.v:181-207](../tb/tb_cryptoCore.v#L181-L207) |
| Key path into `keyStorage` | Intentionally **no AXI path** — "FSM only" | [keyStorage.v:8](../rtl/keyStorage.v#L8) |

**So the boot path's job:** at power-on/reset, fetch the real key material from some
trusted source, drive `key1_wr_en/key1_wr_data` (and key2) to load `keyStorage`,
then assert a real `boot_done` and only *then* allow runtime crypto operations.

---

## 2. The central open question: where do the keys come from?

This is the decision everything else depends on. `keyStorage` has no AXI write path
by design, so the key bytes must originate somewhere the FSM can read at boot. Options:

- **(A) Embedded in the FPGA bitstream** — keys baked into a BRAM/ROM init or
  `initial`-loaded memory, fixed at synthesis time.
- **(B) On-chip OTP / eFuse** — keys burned into device fuses, read over a small
  internal interface at boot.
- **(C) External secure element / host hand-off** — keys streamed in once at boot
  over a dedicated (not the runtime AXI-Lite) interface, then locked.
- **(D) Key derivation** — a root/master secret in the bitstream or eFuse, with the
  two working keys *derived* (e.g., via the AES engine itself) during boot.

> **Note:** the project memory records that the **nonce/IV strategy was deferred** and
> the boot path was flagged as the next step. The key-source decision here is the
> companion question for the boot path. See `project_nonce_design`.

### What we need to know about the bitstream (if option A or D)

If keys (or a root secret) live in the bitstream, we must specify the *contract* with
whatever tool generates that bitstream:

- [ ] **Format**: how is the key represented in the bitstream image? (BRAM `.mem`/`.coe`
  init? a parameter? a dedicated synthesis attribute?)
- [ ] **Endianness / byte order**: `keyStorage` and the AES engine expect a 128-bit
  word `[127:0]`. The AXI map writes CIPHER_IN little-endian across four 32-bit words
  ([axi4LiteRegs.v:168-206](../rtl/axi4LiteRegs.v#L168-L206)) — does the key follow the
  same convention?
- [ ] **Number of keys**: design has exactly **two** key slots (`key1`, `key2`). Does
  the bitstream carry one, two, or a root from which both are derived?
- [ ] **Key size**: AES-128 → **128 bits per key**. Confirm no padding/expansion is
  expected at the boot interface (the AES core does its own key schedule internally).
- [ ] **Addressing**: if multiple secrets share one memory, what offsets/layout?
- [ ] **Mutability**: is the bitstream-resident key updateable in the field
  (re-flash) or fix-at-manufacture?
- [ ] **Toolchain**: which tool injects the key (Vivado `updatemem`/BRAM init, a custom
  script, key-provisioning flow)? This determines the file format we must target.

---

## 3. The core's contract (what the boot path must satisfy)

Things that are *already true* about the design and constrain the boot path:

- **Reset behavior**: `keyStorage` async-zeroizes keys and clears `keyN_valid` on
  `rst` ([keyStorage.v:29-47](../rtl/keyStorage.v#L29-L47)). Boot must run *after*
  reset deasserts and re-load keys every time, since reset wipes them.
- **Key-valid gating**: the runtime FSM already refuses to start unless the selected
  key's `keyN_valid` is set ([cryptoCoreFSM.v:104-108](../rtl/cryptoCoreFSM.v#L104-L108)).
  So setting `keyN_valid` is effectively the "key is ready" signal — the boot path
  drives this for free by using the existing write ports.
- **`boot_done` consumers**: STATUS bit 2 is exposed over AXI
  ([axi4LiteRegs.v:120](../rtl/axi4LiteRegs.v#L120)) and read by software. Today it's
  faked high. A real boot path must drive it low during boot and high when complete.
- **Single key write port per slot**: only the FSM may write `keyStorage`. The boot
  logic therefore most naturally lives **in the FSM** (new boot states) rather than as
  a separate module fighting for the write port.

---

## 4. FSM boot sequencing (sketch of states to add)

Reserved encodings `3'd4..3'd6` are already set aside. A plausible boot sequence:

1. **BOOT_IDLE / BOOT_START** — entered out of reset (before `RUNTIME_IDLE`).
2. **BOOT_LOAD_KEY1** — drive `key1_wr_en` + `key1_wr_data` from the key source.
3. **BOOT_LOAD_KEY2** — same for key2 (if two independent keys).
4. **BOOT_DONE** — assert `boot_done`, fall through to `RUNTIME_IDLE`.

Open sequencing questions:
- [ ] Does boot run **automatically** on reset deassert, or is it triggered (e.g., a
  CTRL bit)? Note CTRL has an unused `RESET` bit at `CTRL[3]`
  ([axi4LiteRegs.v:115](../rtl/axi4LiteRegs.v#L115)) — candidate trigger.
- [ ] If the key source has latency (eFuse read, derivation via AES), how many cycles,
  and does boot need its own handshake/wait state?
- [ ] For derivation (option D), boot must *use the AES engine*, which means arbitrating
  `fsm_enable`/`io_key`/`io_dataIn` between boot and runtime — a bigger change.
- [ ] What happens if the key source fails / returns garbage? Is there a boot-error
  status, or does the core simply never assert `boot_done`?

---

## 5. Runtime gating (must-not-forget)

Once boot is real, runtime ops must be **blocked until `boot_done`**. Today
`RUNTIME_IDLE` only checks `ctrl_start && fsm_ready && !ctr_overflow` and key-valid
([cryptoCoreFSM.v:104](../rtl/cryptoCoreFSM.v#L104)). After the boot path exists:

- [ ] Should `RUNTIME_IDLE` be unreachable until boot completes (FSM structurally
  starts in a boot state)?
- [ ] Should a runtime `start` arriving mid-boot be ignored, queued, or error?

---

## 6. Security considerations to decide explicitly

- [ ] **No key readback**: `keyStorage` deliberately exposes only `keyN_valid`, not key
  bytes ([keyStorage.v:18](../rtl/keyStorage.v#L18)). Confirm the boot source path
  doesn't accidentally make keys observable (e.g., via a debug register).
- [ ] **Zeroization on tamper/reset**: already async on `rst`. Is reset the only
  zeroize trigger, or do we want a tamper/`RESET`-bit-driven wipe too?
- [ ] **Bitstream confidentiality** (option A/D): a key in the bitstream is only as
  safe as the bitstream. Do we rely on FPGA bitstream encryption? Document the
  assumption.
- [ ] **Boot-once / lock**: after boot, should the key write ports be permanently
  locked until the next reset (so nothing can overwrite a key at runtime)?

---

## 7. Things to confirm / collect next

- [ ] Decide the **key source** (Section 2) — this unblocks everything else.
- [ ] If bitstream-resident: obtain the **exact file format + endianness** the
  provisioning tool produces, and a sample.
- [ ] Confirm whether boot is **auto** or **triggered**, and whether it must use the
  AES engine (derivation) or is a plain copy.
- [ ] Define the **boot-failure** behavior and any new STATUS bits.
- [ ] Replace the testbench `force`/`release` key load with a real boot stimulus once
  the interface is fixed.

---

### Quick reference — relevant existing facts

- AES core: AES-128, round-based, 161-cycle latency, single key input `io_key[127:0]`
  ([AES128_Sec_0_Area_0.v:5-8,36](../rtl/AES128_Sec_0_Area_0.v#L36)).
- Two key slots, FSM-only write, mux on `key_sel` ([keyStorage.v](../rtl/keyStorage.v)).
- STATUS layout: `{ctr_overflow, key2_valid, key1_valid, boot_done, done, busy}`
  ([cryptoCore.v:74](../rtl/cryptoCore.v#L74)).
- CTRL layout: `{RESET, KEY_SEL, OP_MODE, START}` ([axi4LiteRegs.v:112-115](../rtl/axi4LiteRegs.v#L112-L115)).
