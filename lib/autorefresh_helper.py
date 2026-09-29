#!/usr/bin/env python3
"""State/profile helper for the WeChat 2 deployment kit.

This helper does not sign or decrypt anything. It validates development
provisioning profiles, writes install receipts, and transactionally backs up
matching local provisioning-profile cache entries before an automatic renewal.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

UTC = dt.timezone.utc


class Failure(RuntimeError):
    pass


def atomic_write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, str(path))
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def write_json(path, obj):
    atomic_write(path, (json.dumps(obj, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def epoch(value):
    if not isinstance(value, dt.datetime):
        raise Failure("Provisioning profile has no valid ExpirationDate")
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return int(value.timestamp())


def decode_mobileprovision(path):
    p = subprocess.run(
        ["/usr/bin/security", "cms", "-D", "-i", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if p.returncode:
        raise Failure(
            "Unable to decode provisioning profile {}: {}".format(
                path, p.stderr.decode("utf-8", "replace")[-1500:]
            )
        )
    try:
        return plistlib.loads(p.stdout)
    except Exception as exc:
        raise Failure("Invalid provisioning plist {}: {}".format(path, exc))


def installed_development_identities():
    p = subprocess.run(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    text = p.stdout.decode("utf-8", "replace")
    return {
        m.group(1).upper()
        for m in re.finditer(
            r'\)\s+([A-Fa-f0-9]{40})\s+"Apple Development:[^\n]*"', text
        )
    }


def cert_hashes(profile):
    return {
        hashlib.sha1(bytes(cert)).hexdigest().upper()
        for cert in profile.get("DeveloperCertificates", [])
    }


def bundle_from_app_id(app_id):
    if not isinstance(app_id, str) or "." not in app_id:
        return ""
    return app_id.split(".", 1)[1]


def profile_meta(path):
    profile = decode_mobileprovision(path)
    ent = profile.get("Entitlements", {})
    app_id = ent.get("application-identifier", "")
    return {
        "path": str(path),
        "uuid": profile.get("UUID", ""),
        "expiration_epoch": epoch(profile.get("ExpirationDate")),
        "team_ids": list(profile.get("TeamIdentifier", [])),
        "application_identifier": app_id,
        "bundle_id": bundle_from_app_id(app_id),
        "devices": list(profile.get("ProvisionedDevices", [])),
        "get_task_allow": ent.get("get-task-allow") is True,
        "certificate_hashes": sorted(cert_hashes(profile)),
    }


def profile_matches(meta, bundle, device, team):
    return (
        meta.get("bundle_id") == bundle
        and device in meta.get("devices", [])
        and team in meta.get("team_ids", [])
        and meta.get("get_task_allow") is True
    )


def bundle_dirs(app):
    root = Path(app).resolve()
    if not root.is_dir() or root.suffix != ".app":
        raise Failure("Signed app path is not an .app directory: {}".format(root))
    found = [root]
    for p in root.rglob("*"):
        try:
            if p.is_dir() and p != root and p.suffix in (".app", ".appex"):
                found.append(p)
        except OSError:
            continue
    # deterministic and de-duplicated
    unique = {str(p.resolve()): p.resolve() for p in found}
    return [unique[k] for k in sorted(unique)]


def build_manifest(app, device, main_bundle, team):
    identities = installed_development_identities()
    if not identities:
        raise Failure("No usable Apple Development signing identity is available in Keychain")

    now = int(time.time())
    rows = []
    seen = set()
    root = Path(app).resolve()

    for b in bundle_dirs(root):
        info_path = b / "Info.plist"
        if not info_path.is_file():
            raise Failure("Missing Info.plist in embedded bundle: {}".format(b))
        try:
            with open(info_path, "rb") as f:
                info = plistlib.load(f)
        except Exception as exc:
            raise Failure("Cannot read {}: {}".format(info_path, exc))

        bundle = info.get("CFBundleIdentifier", "")
        if not bundle:
            raise Failure("Missing CFBundleIdentifier in {}".format(b))
        if bundle in seen:
            raise Failure("Duplicate embedded bundle identifier: {}".format(bundle))
        seen.add(bundle)

        profile_path = b / "embedded.mobileprovision"
        if not profile_path.is_file():
            raise Failure(
                "Embedded bundle {} has no embedded.mobileprovision. "
                "Use REMOVE_EXTENSIONS=1 unless that extension has its own profile.".format(bundle)
            )

        profile = decode_mobileprovision(profile_path)
        ent = profile.get("Entitlements", {})
        app_id = ent.get("application-identifier", "")
        if bundle_from_app_id(app_id) != bundle:
            raise Failure(
                "Profile application-identifier {} does not match bundle {}".format(app_id, bundle)
            )
        if team not in profile.get("TeamIdentifier", []):
            raise Failure("Profile TeamIdentifier does not authorize {} for Team {}".format(bundle, team))
        if device not in profile.get("ProvisionedDevices", []):
            raise Failure("Profile for {} does not authorize target iPhone {}".format(bundle, device))
        if ent.get("get-task-allow") is not True:
            raise Failure("Profile for {} is not an iOS development profile".format(bundle))

        expiration = epoch(profile.get("ExpirationDate"))
        if expiration <= now:
            raise Failure("Profile for {} is already expired".format(bundle))

        allowed = cert_hashes(profile)
        shared = allowed & identities
        if not shared:
            raise Failure(
                "Profile for {} has no DeveloperCertificate matching a private-key "
                "Apple Development identity on this Mac".format(bundle)
            )

        rows.append(
            {
                "bundle": bundle,
                "relative_bundle": "." if b == root else str(b.relative_to(root)),
                "profile_uuid": profile.get("UUID", ""),
                "expiration_epoch": expiration,
                "certificate_hashes": sorted(allowed),
                "usable_identity_hashes": sorted(shared),
                "profile_sha256": hashlib.sha256(profile_path.read_bytes()).hexdigest(),
            }
        )

    if main_bundle not in seen:
        raise Failure("Main configured bundle {} is not present in signed app".format(main_bundle))
    main_row = next((r for r in rows if r["relative_bundle"] == "."), None)
    if not main_row or main_row["bundle"] != main_bundle:
        raise Failure(
            "Top-level app bundle is {}, expected {}".format(
                main_row["bundle"] if main_row else "<missing>", main_bundle
            )
        )

    rows.sort(key=lambda x: x["bundle"])
    effective = min(r["expiration_epoch"] for r in rows)
    return {
        "schema": 2,
        "app_path": str(root),
        "device": device,
        "bundle": main_bundle,
        "team": team,
        "profiles": rows,
        "profile_count": len(rows),
        "effective_expiry": effective,
        "main_expiry": main_row["expiration_epoch"],
        "main_profile_uuid": main_row["profile_uuid"],
    }


def validate_receipt(data, device, bundle):
    if not isinstance(data, dict):
        raise Failure("Install receipt is invalid")
    if data.get("device") != device:
        raise Failure("Install receipt belongs to another iPhone")
    if data.get("bundle") != bundle:
        raise Failure("Install receipt belongs to another bundle")
    rows = data.get("profiles")
    if not isinstance(rows, list) or not rows:
        raise Failure("Install receipt has no profile manifest")
    expiries = [int(r["expiration_epoch"]) for r in rows]
    effective = int(data.get("effective_expiry", 0))
    if effective != min(expiries):
        raise Failure("Install receipt effective expiry does not match its profile manifest")
    if not data.get("receipt_id") or not int(data.get("installed_at", 0)):
        raise Failure("Install receipt is missing successful-install proof fields")
    return effective


def restore_transaction(tx):
    tx = Path(tx)
    manifest_path = tx / "transaction.json"
    if not manifest_path.is_file():
        return
    data = read_json(manifest_path)
    for item in data.get("files", []):
        original = Path(item["original"])
        backup = Path(item["backup"])
        if backup.is_file() and not original.exists():
            original.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(str(backup), str(original))
    atomic_write(tx / "restored", b"Missing old profile-cache entries restored.\n")
    try:
        (tx / "pending").unlink()
    except FileNotFoundError:
        pass


def recover_transactions(state_dir):
    root = Path(state_dir) / "profile-backups"
    if not root.is_dir():
        return 0
    count = 0
    for marker in sorted(root.glob("*/pending")):
        restore_transaction(marker.parent)
        count += 1
    return count


def begin_transaction(state_dir, bundle, device, team):
    state = Path(state_dir)
    backup_root = state / "profile-backups"
    backup_root.mkdir(parents=True, exist_ok=True)
    prefix = time.strftime("%Y%m%d-%H%M%S-") + bundle.replace("/", "_") + "-"
    tx = Path(tempfile.mkdtemp(prefix=prefix, dir=str(backup_root)))

    home = Path.home()
    roots = [
        home / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        home / "Library/MobileDevice/Provisioning Profiles",
    ]
    matches = []
    seen = set()
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.rglob("*.mobileprovision"):
            try:
                real = str(path.resolve())
                if real in seen:
                    continue
                seen.add(real)
                meta = profile_meta(path)
                if profile_matches(meta, bundle, device, team):
                    matches.append((path, meta))
            except Exception:
                continue

    files = []
    try:
        files_dir = tx / "files"
        files_dir.mkdir()
        for idx, (path, meta) in enumerate(matches):
            backup = files_dir / ("{:03d}-{}".format(idx, path.name))
            shutil.copyfile(str(path), str(backup))
            files.append(
                {
                    "original": str(path),
                    "backup": str(backup),
                    "uuid": meta.get("uuid", ""),
                    "expiration_epoch": int(meta.get("expiration_epoch", 0)),
                }
            )
        write_json(
            tx / "transaction.json",
            {
                "bundle": bundle,
                "device": device,
                "team": team,
                "created_at": int(time.time()),
                "files": files,
            },
        )
        atomic_write(tx / "pending", b"Restore missing originals if renewal is interrupted.\n")
        for item in files:
            Path(item["original"]).unlink()
    except BaseException:
        restore_transaction(tx)
        raise

    return tx


def cmd_manifest(args):
    data = build_manifest(args.app, args.device, args.bundle, args.team)
    sys.stdout.write(json.dumps(data, indent=2, sort_keys=True) + "\n")


def cmd_receipt_write(args):
    data = read_json(args.manifest)
    # Validate deterministic manifest shape before converting it to proof of install.
    validate = dict(data)
    if not validate.get("profiles") or not validate.get("effective_expiry"):
        raise Failure("Cannot write receipt from an invalid profile manifest")
    data["installed_at"] = int(time.time())
    data["receipt_id"] = "{}-{}".format(time.strftime("%Y%m%d-%H%M%S"), uuid.uuid4().hex[:10])
    write_json(args.output, data)
    print(data["effective_expiry"])


def cmd_receipt_expiry(args):
    data = read_json(args.receipt)
    print(validate_receipt(data, args.device, args.bundle))


def cmd_receipt_dump(args):
    data = read_json(args.receipt)
    validate_receipt(data, args.device, args.bundle)
    sys.stdout.write(json.dumps(data, indent=2, sort_keys=True) + "\n")


def cmd_plist_expiry(args):
    with open(args.plist, "rb") as f:
        data = plistlib.load(f)
    print(epoch(data.get("ExpirationDate")))


def cmd_tx_begin(args):
    recover_transactions(args.state_dir)
    tx = begin_transaction(args.state_dir, args.bundle, args.device, args.team)
    print(str(tx))


def cmd_tx_restore(args):
    restore_transaction(args.transaction)


def cmd_tx_success(args):
    tx = Path(args.transaction)
    try:
        (tx / "pending").unlink()
    except FileNotFoundError:
        pass
    atomic_write(tx / "success", b"Fresh profile validated; old cache backup retained.\n")


def cmd_tx_recover(args):
    print(recover_transactions(args.state_dir))


def parser():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("manifest")
    m.add_argument("app")
    m.add_argument("device")
    m.add_argument("bundle")
    m.add_argument("team")
    m.set_defaults(func=cmd_manifest)

    w = sub.add_parser("receipt-write")
    w.add_argument("manifest")
    w.add_argument("output")
    w.set_defaults(func=cmd_receipt_write)

    e = sub.add_parser("receipt-expiry")
    e.add_argument("receipt")
    e.add_argument("device")
    e.add_argument("bundle")
    e.set_defaults(func=cmd_receipt_expiry)

    d = sub.add_parser("receipt-dump")
    d.add_argument("receipt")
    d.add_argument("device")
    d.add_argument("bundle")
    d.set_defaults(func=cmd_receipt_dump)

    x = sub.add_parser("plist-expiry")
    x.add_argument("plist")
    x.set_defaults(func=cmd_plist_expiry)

    b = sub.add_parser("tx-begin")
    b.add_argument("state_dir")
    b.add_argument("bundle")
    b.add_argument("device")
    b.add_argument("team")
    b.set_defaults(func=cmd_tx_begin)

    r = sub.add_parser("tx-restore")
    r.add_argument("transaction")
    r.set_defaults(func=cmd_tx_restore)

    s = sub.add_parser("tx-success")
    s.add_argument("transaction")
    s.set_defaults(func=cmd_tx_success)

    rr = sub.add_parser("tx-recover")
    rr.add_argument("state_dir")
    rr.set_defaults(func=cmd_tx_recover)

    return p


def main():
    args = parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except (Failure, OSError, ValueError, KeyError, plistlib.InvalidFileException) as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        sys.exit(1)
