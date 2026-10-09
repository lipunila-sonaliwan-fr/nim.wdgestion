# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdGestion V/FR - hachage des mots de passe : SHA-256, HMAC-SHA256, PBKDF2-HMAC-SHA256
#
# Format stocké : "pbkdf2-sha256$<itérations>$<sel hex>$<empreinte hex>"
# Le sel (16 octets) vient du générateur cryptographique du système.

import std/[strutils, sysrand]

const
  iterationsMdp* = 120_000
  prefixeMdp = "pbkdf2-sha256"

const K: array[64, uint32] = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32, 0x59f111f1'u32,
  0x923f82a4'u32, 0xab1c5ed5'u32, 0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
  0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32, 0xe49b69c1'u32, 0xefbe4786'u32,
  0x0fc19dc6'u32, 0x240ca1cc'u32, 0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32,
  0x06ca6351'u32, 0x14292967'u32, 0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
  0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32, 0xa2bfe8a1'u32, 0xa81a664b'u32,
  0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32,
  0x5b9cca4f'u32, 0x682e6ff3'u32, 0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
  0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]

type
  Empreinte* = array[32, byte]
  Sha256 = object
    h: array[8, uint32]
    buf: array[64, byte]
    nbuf: int
    total: uint64

proc rotr(x: uint32, n: int): uint32 {.inline.} = (x shr n) or (x shl (32 - n))

proc compresser(h: var array[8, uint32], b: openArray[byte], o: int) =
  var w: array[64, uint32]
  for i in 0 .. 15:
    w[i] = (b[o+4*i].uint32 shl 24) or (b[o+4*i+1].uint32 shl 16) or
           (b[o+4*i+2].uint32 shl 8) or b[o+4*i+3].uint32
  for i in 16 .. 63:
    let s0 = rotr(w[i-15], 7) xor rotr(w[i-15], 18) xor (w[i-15] shr 3)
    let s1 = rotr(w[i-2], 17) xor rotr(w[i-2], 19) xor (w[i-2] shr 10)
    w[i] = w[i-16] + s0 + w[i-7] + s1
  var a = h[0]; var bb = h[1]; var c = h[2]; var d = h[3]
  var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7]
  for i in 0 .. 63:
    let t1 = hh + (rotr(e, 6) xor rotr(e, 11) xor rotr(e, 25)) + ((e and f) xor ((not e) and g)) + K[i] + w[i]
    let t2 = (rotr(a, 2) xor rotr(a, 13) xor rotr(a, 22)) + ((a and bb) xor (a and c) xor (bb and c))
    hh = g; g = f; f = e; e = d + t1; d = c; c = bb; bb = a; a = t1 + t2
  h[0] += a; h[1] += bb; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh

proc initSha256(): Sha256 =
  result.h = [0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
              0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32]

proc maj(c: var Sha256, data: openArray[byte]) =
  c.total += data.len.uint64
  var i = 0
  if c.nbuf > 0:
    while i < data.len and c.nbuf < 64:
      c.buf[c.nbuf] = data[i]; inc c.nbuf; inc i
    if c.nbuf == 64:
      compresser(c.h, c.buf, 0); c.nbuf = 0
  while i + 64 <= data.len:
    compresser(c.h, data, i); i += 64
  while i < data.len:
    c.buf[c.nbuf] = data[i]; inc c.nbuf; inc i

proc fin(c: var Sha256): Empreinte =
  let bits = c.total * 8
  var pad = @[0x80'u8]
  while (c.total.int + pad.len) mod 64 != 56: pad.add 0
  for k in countdown(7, 0): pad.add byte((bits shr (8 * k)) and 0xff)
  let total = c.total
  c.maj(pad)
  c.total = total
  for i in 0 .. 7:
    for j in 0 .. 3:
      result[4*i + j] = byte((c.h[i] shr (24 - 8 * j)) and 0xff)

proc sha256*(data: openArray[byte]): Empreinte =
  var c = initSha256()
  c.maj(data)
  c.fin()

proc octets(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, ch in s: result[i] = byte(ch)

proc versHex*(b: openArray[byte]): string =
  for x in b: result.add toHex(x.int, 2).toLowerAscii

proc depuisHex(s: string): seq[byte] =
  if s.len mod 2 != 0: raise newException(ValueError, "hex")
  for i in countup(0, s.len - 2, 2): result.add byte(parseHexInt(s[i .. i+1]))

proc pbkdf2Sha256*(mdp, sel: openArray[byte], iterations: int): Empreinte =
  # PBKDF2-HMAC-SHA256, un seul bloc de 32 octets (RFC 8018).
  var cle: seq[byte]
  if mdp.len > 64: cle = @(sha256(mdp)) else: cle = @mdp
  cle.setLen(64)
  var ipad, opad: array[64, byte]
  for i in 0 .. 63:
    ipad[i] = cle[i] xor 0x36
    opad[i] = cle[i] xor 0x5c
  var ci = initSha256(); ci.maj(ipad)                             # états pré-calculés : 2 compressions par itération.
  var co = initSha256(); co.maj(opad)
  proc hmac(ci, co: Sha256, m: openArray[byte]): Empreinte =
    var a = ci; a.maj(m)
    let interne = a.fin()
    var b = co; b.maj(interne)
    b.fin()
  var u = hmac(ci, co, @sel & @[0'u8, 0, 0, 1])
  result = u
  for _ in 2 .. iterations:
    u = hmac(ci, co, u)
    for j in 0 .. 31: result[j] = result[j] xor u[j]

proc egaliteConstante(a, b: openArray[byte]): bool =
  if a.len != b.len: return false
  var d = 0'u8
  for i in 0 ..< a.len: d = d or (a[i] xor b[i])
  d == 0

proc hacherMdp*(mdp: string, iterations = iterationsMdp): string =
  var sel: array[16, byte]
  if not urandom(sel): raise newException(OSError, "générateur aléatoire indisponible")
  prefixeMdp & "$" & $iterations & "$" & versHex(sel) & "$" &
    versHex(pbkdf2Sha256(octets(mdp), sel, iterations))

proc verifierMdp*(mdp, stocke: string): bool =
  # Vrai si `mdp` correspond à l'empreinte stockée. Si l'empreinte est absente
  # ou invalide, un calcul complet est fait quand même (temps de réponse identique,
  # l'existence d'un compte ne se devine pas au chronomètre).
  let p = stocke.split('$')
  var iterations = iterationsMdp
  var sel, attendu: seq[byte]
  var valide = false
  if p.len == 4 and p[0] == prefixeMdp:
    try:
      iterations = parseInt(p[1])
      sel = depuisHex(p[2])
      attendu = depuisHex(p[3])
      valide = iterations in 1 .. 10_000_000 and attendu.len == 32
    except ValueError: valide = false
  if not valide:
    iterations = iterationsMdp
    sel = newSeq[byte](16)
    attendu = newSeq[byte](32)
  let calcule = pbkdf2Sha256(octets(mdp), sel, iterations)
  egaliteConstante(calcule, attendu) and valide

proc mdpAleatoire*(longueur = 16): string =
  # Mot de passe aléatoire (sans caractères ambigus : 0/O, 1/l/I).
  const alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  let n = max(8, min(longueur, 128))
  while result.len < n:
    var b: array[32, byte]
    if not urandom(b): raise newException(OSError, "générateur aléatoire indisponible")
    for x in b:
      # rejet pour éviter le biais du modulo.
      if x.int < (256 div alphabet.len) * alphabet.len and result.len < n:
        result.add alphabet[x.int mod alphabet.len]
