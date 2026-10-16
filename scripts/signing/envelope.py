#!/usr/bin/env python3
"""One-use authenticated CI key envelopes. Never print plaintext key material."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.serialization import pkcs12

REPO = "dr-askar/raff-app"
APP_SOURCE = "efef8f634a68cb32b2a98a7105973420e6d576d6"
ARTIFACT_DIGEST = "bb7d323c9d8a4f8baf780283fbbcbfe180a4eaff65105815431b8ee6537046c5"
OAEP = padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None)


def encoded(value):
    return base64.b64encode(value).decode()


def decoded(value):
    return base64.b64decode(value, validate=True)


def private_write(path, value):
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(value)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def context(session, head, fingerprint):
    return dict(repository=REPO, session=str(session), ci_head=head,
                app_source=APP_SOURCE, artifact_digest=ARTIFACT_DIGEST,
                certificate_sha256=fingerprint.strip().lower())


def init(directory, pin):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory.chmod(0o700)
    key_file, password_file = directory / "release.p12", directory / "password.txt"
    if not key_file.exists():
        if pin.exists() or password_file.exists():
            raise ValueError("Signing state incomplete: restore the original key; never replace it")
        password = secrets.token_urlsafe(48)
        private_write(password_file, (password + "\n").encode())
        result = subprocess.run([
            "keytool", "-genkeypair", "-storetype", "PKCS12",
            "-keystore", str(key_file), "-alias", "raff-release",
            "-keyalg", "RSA", "-keysize", "3072", "-validity", "10950",
            "-dname", "CN=Raff App Release, O=Raff",
            "-storepass:file", str(password_file), "-keypass:file", str(password_file),
            "-noprompt"], capture_output=True, check=False)
        if result.returncode:
            raise ValueError("Key generation failed; private input was not logged")
        key_file.chmod(0o600)
    password = password_file.read_text().strip().encode()
    key, certificate, _ = pkcs12.load_key_and_certificates(key_file.read_bytes(), password)
    if key is None or certificate is None:
        raise ValueError("Missing key or certificate")
    digest = certificate.fingerprint(hashes.SHA256()).hex()
    if pin.exists() and pin.read_text().strip() != digest:
        raise ValueError("Certificate pin mismatch: original key required")
    pin.parent.mkdir(parents=True, exist_ok=True)
    pin.write_text(digest + "\n")
    (directory / "certificate.pem").write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    return digest


def recipient(directory, ctx):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory.chmod(0o700)
    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    private_write(directory / "session.pem", key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    value = dict(context=ctx, expires=int(time.time()) + 1800,
                 public_key=key.public_key().public_bytes(
                     serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode())
    (directory / "recipient.json").write_text(json.dumps(value))
    return value


def seal(public, expected, payload):
    if public["context"] != expected or not time.time() < public["expires"] <= time.time() + 1900:
        raise ValueError("Wrong or expired signing session")
    key = serialization.load_pem_public_key(public["public_key"].encode())
    if not isinstance(key, rsa.RSAPublicKey) or key.key_size < 3072:
        raise ValueError("Weak or invalid recipient")
    aes = AESGCM.generate_key(bit_length=256)
    nonce = secrets.token_bytes(12)
    return dict(context=expected, nonce=encoded(nonce),
                wrapped_key=encoded(key.encrypt(aes, OAEP)),
                ciphertext=encoded(AESGCM(aes).encrypt(nonce, canonical(payload), canonical(expected))))


def unseal(directory, envelope, expected):
    if envelope["context"] != expected:
        raise ValueError("Session context mismatch")
    key = serialization.load_pem_private_key((directory / "session.pem").read_bytes(), None)
    aes = key.decrypt(decoded(envelope["wrapped_key"]), OAEP)
    return json.loads(AESGCM(aes).decrypt(decoded(envelope["nonce"]),
                      decoded(envelope["ciphertext"]), canonical(expected)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["init", "recipient", "seal", "open"])
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--pin", type=Path, required=True)
    parser.add_argument("--session")
    parser.add_argument("--head")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.operation == "init":
        print("Certificate SHA-256:", init(args.directory, args.pin))
        return
    ctx = context(args.session, args.head, args.pin.read_text())
    if args.operation == "recipient":
        recipient(args.directory, ctx)
    elif args.operation == "seal":
        payload = dict(keystore=encoded((args.directory / "release.p12").read_bytes()),
                       password=(args.directory / "password.txt").read_text().strip())
        value = seal(json.loads(args.input.read_text()), ctx, payload)
        args.output.write_text(json.dumps(value))
    else:
        payload = unseal(args.directory, json.loads(args.input.read_text()), ctx)
        raw = decoded(payload["keystore"])
        password = payload["password"].encode()
        key, cert, _ = pkcs12.load_key_and_certificates(raw, password)
        if key is None or cert is None or cert.fingerprint(hashes.SHA256()).hex() != ctx["certificate_sha256"]:
            raise ValueError("Keystore does not match the pinned release certificate")
        private_write(args.directory / "release.p12", raw)
        private_write(args.directory / "password.txt", password + b"\n")
        (args.directory / "session.pem").unlink()
    print("Signing operation completed; no private material printed.")


if __name__ == "__main__":
    main()
