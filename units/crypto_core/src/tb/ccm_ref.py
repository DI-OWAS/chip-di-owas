# AES-128 CCM (SP 800-38C) reference generator for ccmEngine vectors.
# Pure Python, no deps. AES validated against RFC4493 CMAC; CCM validated
# against NIST SP 800-38C Appendix C Examples 1 & 2 (see checks at bottom).
# Run:  python ccm_ref.py

def _init():
    def gmul(a, b):
        r = 0
        for _ in range(8):
            if b & 1: r ^= a
            hi = a & 0x80; a = (a << 1) & 0xff
            if hi: a ^= 0x1b
            b >>= 1
        return r
    inv = [0] * 256
    for a in range(1, 256):
        for b in range(256):
            if gmul(a, b) == 1: inv[a] = b; break
    sb = [0] * 256
    for a in range(256):
        s = inv[a]; x = s
        for _ in range(4):
            x = ((x << 1) | (x >> 7)) & 0xff; s ^= x
        sb[a] = s ^ 0x63
    return sb, gmul
sbox, gmul = _init()
Rcon = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]

def kexp(key):
    w = [list(key[4*i:4*i+4]) for i in range(4)]
    for i in range(4, 44):
        t = list(w[i-1])
        if i % 4 == 0:
            t = t[1:] + t[:1]; t = [sbox[b] for b in t]; t[0] ^= Rcon[i//4 - 1]
        w.append([w[i-4][j] ^ t[j] for j in range(4)])
    return w

def aes(block, key):
    w = kexp(key); s = [[block[r+4*c] for c in range(4)] for r in range(4)]
    def ark(rnd):
        for c in range(4):
            for r in range(4): s[r][c] ^= w[rnd*4+c][r]
    ark(0)
    for rnd in range(1, 10):
        for r in range(4):
            for c in range(4): s[r][c] = sbox[s[r][c]]
        s[1] = s[1][1:]+s[1][:1]; s[2] = s[2][2:]+s[2][:2]; s[3] = s[3][3:]+s[3][:3]
        for c in range(4):
            a = [s[r][c] for r in range(4)]
            s[0][c] = gmul(a[0],2)^gmul(a[1],3)^a[2]^a[3]
            s[1][c] = a[0]^gmul(a[1],2)^gmul(a[2],3)^a[3]
            s[2][c] = a[0]^a[1]^gmul(a[2],2)^gmul(a[3],3)
            s[3][c] = gmul(a[0],3)^a[1]^a[2]^gmul(a[3],2)
        ark(rnd)
    for r in range(4):
        for c in range(4): s[r][c] = sbox[s[r][c]]
    s[1] = s[1][1:]+s[1][:1]; s[2] = s[2][2:]+s[2][:2]; s[3] = s[3][3:]+s[3][:3]
    ark(10)
    return bytes(s[r][c] for c in range(4) for r in range(4))

def xorb(a, b): return bytes(x ^ y for x, y in zip(a, b))

def ccm_encrypt(key, nonce, adata, payload, tlen):
    q = 15 - len(nonce)
    flags = (64 if adata else 0) | (((tlen-2)//2) << 3) | (q-1)
    mac_in = bytes([flags]) + nonce + len(payload).to_bytes(q, 'big')
    if adata:
        a = len(adata)
        if a < (1<<16)-(1<<8): enc = a.to_bytes(2,'big')
        elif a < (1<<32):      enc = b'\xff\xfe' + a.to_bytes(4,'big')
        else:                  enc = b'\xff\xff' + a.to_bytes(8,'big')
        ad = enc + adata; ad += b'\x00' * ((-len(ad)) % 16); mac_in += ad
    mac_in += payload + b'\x00' * ((-len(payload)) % 16)
    Y = bytes(16)
    for i in range(0, len(mac_in), 16):
        Y = aes(xorb(Y, mac_in[i:i+16]), key)
    T = Y[:tlen]
    ctr = lambda i: bytes([q-1]) + nonce + i.to_bytes(q, 'big')
    S0 = aes(ctr(0), key)
    U = xorb(T, S0[:tlen])
    C = b''
    for idx, i in enumerate(range(0, len(payload), 16), start=1):
        blk = payload[i:i+16]; S = aes(ctr(idx), key); C += xorb(blk, S[:len(blk)])
    return C, U

if __name__ == "__main__":
    # ---- self-validation against SP 800-38C ----
    K = bytes.fromhex("404142434445464748494a4b4c4d4e4f")
    c, u = ccm_encrypt(K, bytes.fromhex("10111213141516"),
                       bytes.fromhex("0001020304050607"), bytes.fromhex("20212223"), 4)
    assert (c+u).hex() == "7162015b4dac255d", "Ex1 failed"
    c, u = ccm_encrypt(K, bytes.fromhex("1011121314151617"),
                       bytes.fromhex("000102030405060708090a0b0c0d0e0f"),
                       bytes.fromhex("202122232425262728292a2b2c2d2e2f"), 6)
    assert (c+u).hex() == "d2a1f0e051ea5f62081a7792073d593d1fc64fbfaccd", "Ex2 failed"
    print("SP 800-38C Examples 1 & 2: OK")

    # ---- vectors for ccmEngine: no AAD, Q=2 (Nlen=13), Tlen=16 ----
    KEY   = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    NONCE = bytes.fromhex("00112233445566778899aabbcc")
    blk = lambda b: (b + b'\x00'*(16-len(b))).hex()
    msg = bytes(range(0x20, 0x20+64))
    print(f"key={KEY.hex()} nonce={NONCE.hex()}")
    for n in [0, 16, 20, 40]:
        P = msg[:n]; C, U = ccm_encrypt(KEY, NONCE, b"", P, 16)
        print(f"\nlen={n}  payload={P.hex() or '(empty)'}")
        print(f"  ciphertext={C.hex() or '(empty)'}  U={U.hex()}")
