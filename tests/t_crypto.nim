# Vérifie SHA-256 et PBKDF2-HMAC-SHA256 sur des vecteurs de référence (RFC 7914, FIPS 180)
import std/[times, strutils]
import wdg/crypto

proc b(s: string): seq[byte] =
  for c in s: result.add byte(c)

var echecs = 0
proc verifie(nom, obtenu, attendu: string) =
  if obtenu == attendu: echo "ok    ", nom
  else: inc echecs; echo "ÉCHEC ", nom, "\n  obtenu  ", obtenu, "\n  attendu ", attendu

verifie("sha256 abc", versHex(sha256(b"abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
verifie("sha256 vide", versHex(sha256(b"")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
verifie("sha256 1 million de 'a'", versHex(sha256(b(repeat('a', 1_000_000)))), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
verifie("pbkdf2 RFC 7914 (c=1)", versHex(pbkdf2Sha256(b"passwd", b"salt", 1)), "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
verifie("pbkdf2 RFC 7914 (c=80000)", versHex(pbkdf2Sha256(b"Password", b"NaCl", 80000)), "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56")
verifie("pbkdf2 clé > 64 octets", versHex(pbkdf2Sha256(b(repeat('k', 100)), b"sel", 3)), "a0ddf3dd295ce267e1133584677d6954432e79bd6ddeab84548fd144082b3cff")  # hashlib.pbkdf2_hmac
let t0 = epochTime()
let h = hacherMdp("Bonjour !")
echo "      hachage en ", $int((epochTime() - t0) * 1000), " ms : ", h[0 .. 40], "..."
verifie("verifierMdp correct", $verifierMdp("Bonjour !", h), "true")
verifie("verifierMdp faux", $verifierMdp("bonjour !", h), "false")
verifie("verifierMdp empreinte absente", $verifierMdp("x", ""), "false")
verifie("deux hachages différents (sel)", $(hacherMdp("x", 10) != hacherMdp("x", 10)), "true")
let m = mdpAleatoire()
verifie("mdpAleatoire longueur", $m.len, "16")
if echecs > 0: quit(1)
