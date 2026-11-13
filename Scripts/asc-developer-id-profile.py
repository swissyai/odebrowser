#!/usr/bin/env python3
"""Fetch, creating it when needed, the Developer ID provisioning profile that
lets Ode use its keychain group, through the App Store Connect API.

Registers the bundle identifier if the team has not, finds the team's
Developer ID Application certificate that matches the identity in the login
keychain, and creates or reuses a Developer ID ("MAC_APP_DIRECT") profile
named PROFILE_NAME for them. Writes the profile to OUTPUT and prints its
name. Authentication is a JWT signed with the API key by openssl; no
third-party modules are needed.

Usage: Scripts/asc-developer-id-profile.py --key-id ID --issuer ISSUER --key PATH \
          --bundle-id com.odebrowser.ode --team WUMLCL8SAZ --output PATH
"""

import argparse
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
PROFILE_NAME = "Ode Developer ID"
CERTIFICATE_TYPES = ("DEVELOPER_ID_APPLICATION_G2", "DEVELOPER_ID_APPLICATION")


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(signature):
    """An ECDSA DER signature as the 64-byte r||s a JWT carries."""
    assert signature[0] == 0x30
    index = 2 if signature[1] < 0x80 else 2 + (signature[1] & 0x7F)
    parts = []
    for _ in range(2):
        assert signature[index] == 0x02
        length = signature[index + 1]
        value = signature[index + 2:index + 2 + length].lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
        index += 2 + length
    return parts[0] + parts[1]


def token(key_id, issuer, key_path):
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    claims = {"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(claims).encode())}"
    signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                               input=signing_input.encode(), capture_output=True, check=True).stdout
    return f"{signing_input}.{b64url(der_to_raw(signature))}"


class Client:
    def __init__(self, bearer):
        self.bearer = bearer

    def call(self, method, path, body=None):
        request = urllib.request.Request(API + path, method=method,
                                         data=json.dumps(body).encode() if body is not None else None)
        request.add_header("Authorization", f"Bearer {self.bearer}")
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise SystemExit(f"App Store Connect {method} {path} answered {error.code}: {detail[:600]}")


def local_certificate_serial(team):
    pem = subprocess.run(["security", "find-certificate", "-a", "-c", "Developer ID Application", "-p"],
                         capture_output=True, text=True, check=True).stdout
    serials = []
    for block in pem.split("-----END CERTIFICATE-----"):
        if "BEGIN CERTIFICATE" not in block:
            continue
        text = block + "-----END CERTIFICATE-----\n"
        subject = subprocess.run(["openssl", "x509", "-noout", "-subject", "-serial"], input=text,
                                 capture_output=True, text=True).stdout
        if f"({team})" in subject or f"OU={team}" in subject.replace(" ", ""):
            serials.append(subject.split("serial=")[-1].strip().upper())
    return serials


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    client = Client(token(args.key_id, args.issuer, args.key))

    query = urllib.parse.urlencode({"filter[identifier]": args.bundle_id, "limit": 200})
    found = [entry for entry in client.call("GET", f"/bundleIds?{query}")["data"]
             if entry["attributes"]["identifier"] == args.bundle_id]
    if found:
        bundle = found[0]
    else:
        bundle = client.call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": args.bundle_id, "name": "Ode", "platform": "MAC_OS"}}})["data"]
        print(f"registered {args.bundle_id}", file=sys.stderr)

    serials = local_certificate_serial(args.team)
    certificate = None
    for kind in CERTIFICATE_TYPES:
        query = urllib.parse.urlencode({"filter[certificateType]": kind, "limit": 200})
        for entry in client.call("GET", f"/certificates?{query}")["data"]:
            serial = entry["attributes"].get("serialNumber", "").upper()
            if serial and serial.lstrip("0") in {local.lstrip("0") for local in serials}:
                certificate = entry
                break
        if certificate:
            break
    if not certificate:
        raise SystemExit("No Developer ID Application certificate on the team matches the one in the keychain.")

    query = urllib.parse.urlencode({"filter[name]": PROFILE_NAME, "filter[profileType]": "MAC_APP_DIRECT",
                                    "include": "bundleId", "limit": 50})
    profile = None
    for entry in client.call("GET", f"/profiles?{query}")["data"]:
        if entry["attributes"].get("profileState") == "ACTIVE" and \
                entry["relationships"]["bundleId"]["data"]["id"] == bundle["id"]:
            profile = entry
            break
    if not profile:
        profile = client.call("POST", "/profiles", {"data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "MAC_APP_DIRECT"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": certificate["id"]}]},
            }}})["data"]
        print(f"created the {PROFILE_NAME} profile", file=sys.stderr)
    with open(args.output, "wb") as stream:
        stream.write(base64.b64decode(profile["attributes"]["profileContent"]))
    print(PROFILE_NAME)


if __name__ == "__main__":
    main()
