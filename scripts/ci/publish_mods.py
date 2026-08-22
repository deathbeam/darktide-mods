#!/usr/bin/env python3
"""Release mods to Nexus Mods, using the published version there as the source
of truth (no git diffing).

For every mod folder with an ``info.json`` that declares ``version`` and
``mod_id``:
  1. Fetch the mod's currently published MAIN version from the Nexus Mods API.
  2. Compare it to the local ``version`` in ``info.json``.
  3. If they differ (or --force), zip the mod folder and upload a new version.

``mod_id`` is the NexusMods mod id (the number in the mod's URL). The
file_group_id is resolved automatically from the API.

With --collection <Name>, after uploading mods the script also syncs a Nexus
Mods collection that references every published mod by mod_id + file_id. The
collection is created on first run and gets a new draft revision whenever a
mod was uploaded (or --force). Revisions stay in draft until published on the
website.

Usage:
    python scripts/ci/publish_mods.py [--dry-run] [--force] [--mod <Name>] [--collection <Name>]

Required environment variables:
    NEXUSMODS_APIKEY        Your Nexus Mods API key

Optional environment variables:
    NEXUSMODS_GAME_DOMAIN   Nexus Mods game domain slug (default: warhammer40kdarktide)
    NEXUSMODS_API_BASE      Default: https://api.nexusmods.com/v3
    NEXUSMODS_AUTHOR_NAME   Fallback author name if /users/validate fails (default: deathbeam)
    NEXUSMODS_COLLECTION_SUMMARY     Collection summary text
    NEXUSMODS_COLLECTION_DESCRIPTION  Collection description text
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import requests

API_BASE = os.environ.get("NEXUSMODS_API_BASE", "https://api.nexusmods.com/v3").rstrip("/")
V1_BASE = "https://api.nexusmods.com/v1"
GRAPHQL_BASE = "https://api.nexusmods.com/v2/graphql"
GAME_DOMAIN = os.environ.get("NEXUSMODS_GAME_DOMAIN", "warhammer40kdarktide")
USER_AGENT = "deathbeam/darktide-mods publish script"

# ANSI colors; auto-disabled when output isn't a TTY (e.g. piped).
_USE_COLOR = sys.stderr.isatty()


def _c(code: str, msg: str) -> str:
    return f"\033[{code}m{msg}\033[0m" if _USE_COLOR else msg


def log_ok(msg: str) -> None:
    print(f"  {_c('32', '✓')} {msg}")


def log_skip(msg: str) -> None:
    print(f"  {_c('33', '·')} {msg}")


def log_fail(msg: str) -> None:
    print(f"  {_c('31', '✗')} {msg}")


def log_info(msg: str) -> None:
    print(f"  {_c('36', '→')} {msg}")


def _dump_collection(manifest: dict, name: str) -> None:
    # Write the manifest next to the other build artefacts for inspection.
    safe = name.replace(" ", "_").lower()
    out = Path(f"{safe}.collection.json")
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    log_info(f"wrote {out}")


def log_step(msg: str) -> None:
    print(f"      {msg}")


def log_section(title: str) -> None:
    print(f"\n{_c('1', f'== {title} ==')}")


# ---------------------------------------------------------------------------
# info.json metadata parsing
# ---------------------------------------------------------------------------

def extract_mod_info(mod_name: str) -> dict | None:
    """Read release metadata from a mod's info.json file."""
    file_path = Path(mod_name) / "info.json"
    try:
        metadata = json.loads(file_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"Warning: could not read {file_path}: {e}", file=sys.stderr)
        return None

    if not isinstance(metadata, dict):
        print(f"Warning: {file_path} must contain a JSON object", file=sys.stderr)
        return None

    version = metadata.get("version")
    mod_id = metadata.get("mod_id")
    return {
        "version": str(version) if version is not None else None,
        "mod_id": str(mod_id) if mod_id is not None else None,
    }


def find_mod_folders() -> list[str]:
    """List mod folders tracked by git that contain a .mod file."""
    result = subprocess.run(
        ["git", "ls-files", "*.mod"], capture_output=True, text=True, check=True
    )
    folders: list[str] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith(".template-dmf/"):
            continue
        folders.append(line.split("/")[0])
    return folders


# ---------------------------------------------------------------------------
# Zipping
# ---------------------------------------------------------------------------

def zip_mod(mod_name: str, zip_name: str) -> bool:
    """Zip a mod folder. Returns True on success."""
    result = subprocess.run(["zip", "-r", zip_name, mod_name], capture_output=True, text=True)
    return result.returncode == 0 and Path(zip_name).exists()


# ---------------------------------------------------------------------------
# Nexus Mods API client
# ---------------------------------------------------------------------------

class NexusAPI:
    """Thin client over the Nexus Mods v1 (REST), v3 (REST), and v2 (GraphQL) APIs."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.session = requests.Session()
        self.session.headers.update({"apikey": api_key, "User-Agent": USER_AGENT})

    # -- v3 REST (returns the unwrapped `data` field) --

    def v3(self, method: str, path: str, body: dict | None = None) -> dict | None:
        url = f"{API_BASE}{path}"
        headers = {}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body)
        resp = self.session.request(method, url, headers=headers, data=data)
        if not resp.ok:
            raise RuntimeError(f"HTTP {resp.status_code} from {method} {url}: {resp.text}")
        if not resp.text:
            return None
        parsed = resp.json()
        return parsed.get("data", parsed)

    # -- v1 REST (returns the raw JSON) --

    def v1(self, method: str, path: str) -> dict:
        url = f"{V1_BASE}{path}"
        resp = self.session.request(method, url)
        if not resp.ok:
            raise RuntimeError(f"HTTP {resp.status_code} from {method} {url}: {resp.text}")
        return resp.json()

    # -- v2 GraphQL --

    def graphql(self, query: str, variables: dict | None = None) -> dict:
        resp = self.session.post(
            GRAPHQL_BASE,
            json={"query": query, "variables": variables or {}},
            headers={"Content-Type": "application/json"},
        )
        parsed = resp.json()
        if not resp.ok or parsed.get("errors"):
            errors = parsed.get("errors")
            msg = "; ".join(e["message"] for e in errors) if errors else resp.text
            raise RuntimeError(f"GraphQL error: {msg}")
        return parsed["data"]

    # -- presigned PUT (for multipart upload parts) --

    @staticmethod
    def put_presigned(url: str, chunk: bytes) -> str:
        resp = requests.put(
            url,
            data=chunk,
            headers={"Content-Type": "application/octet-stream", "Content-Length": str(len(chunk))},
        )
        if not resp.ok:
            raise RuntimeError(f"HTTP {resp.status_code} uploading to presigned URL: {resp.text}")
        return (resp.headers.get("ETag") or "").strip('"')


# ---------------------------------------------------------------------------
# Mod file resolution
# ---------------------------------------------------------------------------

def resolve_mod_uuid(api: NexusAPI, mod_id: str) -> str:
    """Resolve the mod's UUID from its game-scoped mod_id."""
    info = api.v3("GET", f"/games/{GAME_DOMAIN}/mods/{mod_id}")
    if not info or not info.get("id"):
        raise RuntimeError(f"no 'id' field for mod {mod_id}")
    return info["id"]


def get_published_file(api: NexusAPI, mod_id: str) -> dict | None:
    """Fetch the currently published MAIN file from the v1 files list.

    Falls back to the most recently uploaded file when no MAIN category exists.
    Returns version, file_id, file_size_kb, logical_filename.
    """
    data = api.v1("GET", f"/games/{GAME_DOMAIN}/mods/{mod_id}/files.json")
    files = data.get("files", [])
    if not files:
        return None

    main = next(
        (f for f in files if f.get("category_name") == "MAIN" or f.get("category_id") == 1),
        None,
    )
    f = main or max(files, key=lambda x: x.get("uploaded_time", ""))

    # size/size_kb are both in kilobytes; file_name is the logical filename.
    return {
        "version": f.get("version"),
        "file_id": f.get("file_id"),
        "file_size_kb": f.get("size_kb", f.get("size")),
        "logical_filename": f.get("file_name"),
    }


def resolve_file_group_id(api: NexusAPI, mod_uuid: str) -> str:
    """Resolve the file-update group id (where new versions get uploaded)."""
    info = api.v3("GET", f"/mods/{mod_uuid}/files")
    groups = info.get("mod_files", []) if info else []
    if not groups:
        raise RuntimeError("no file update groups found; create one on Nexus Mods first")

    active = [g for g in groups if g.get("is_active")]
    candidates = active if active else groups
    # Prefer the group with the most recent upload.
    candidates.sort(
        key=lambda g: g.get("last_file_uploaded_at") or "",
        reverse=True,
    )
    return candidates[0]["id"]


# ---------------------------------------------------------------------------
# Upload (v3 multipart flow)
# ---------------------------------------------------------------------------

def poll_until_available(api: NexusAPI, upload_id: str) -> None:
    """Poll the upload status until Nexus finishes processing it."""
    for attempt in range(60):
        state_info = api.v3("GET", f"/uploads/{upload_id}")
        if state_info and state_info.get("state") == "available":
            return
        log_step(f"processing: {state_info.get('state') if state_info else '?'}")
        time.sleep(min(2 * 1.5**attempt, 30))
    raise RuntimeError(f"timed out waiting for upload {upload_id} to become available")


def upload_file(api: NexusAPI, file_path: str) -> str:
    """Upload a file via the v3 multipart flow and wait for it to be processed.

    Returns the finalised upload_id, ready to be claimed by a mod file version
    or a collection/revision.
    """
    file_size = os.path.getsize(file_path)
    file_basename = Path(file_path).name

    # Multipart upload for all sizes; the single `/uploads` endpoint signs
    # `content-disposition`, which R2 rejects unless echoed byte-for-byte.
    upload_info = api.v3("POST", "/uploads/multipart", {"filename": file_basename, "size_bytes": file_size})
    upload_id = upload_info["id"]
    part_urls = upload_info.get("part_presigned_urls") or upload_info.get("parts_presigned_url")
    part_size = upload_info.get("part_size_bytes") or upload_info.get("parts_size")
    complete_url = upload_info["complete_presigned_url"]
    log_info(f"uploading {file_basename} ({file_size} bytes), {len(part_urls)} part(s)")

    parts = []
    with open(file_path, "rb") as f:
        for i, part_url in enumerate(part_urls):
            part_number = i + 1
            chunk = f.read(part_size)
            log_step(f"part {part_number}/{len(part_urls)} ({len(chunk)} bytes)")
            etag = api.put_presigned(part_url, chunk)
            parts.append((part_number, etag))

    log_step("completing multipart upload")
    xml_parts = "\n".join(
        f"  <Part>\n    <PartNumber>{n}</PartNumber>\n    <ETag>{e}</ETag>\n  </Part>"
        for n, e in parts
    )
    xml = f"<CompleteMultipartUpload>\n{xml_parts}\n</CompleteMultipartUpload>"
    complete_resp = requests.post(complete_url, data=xml, headers={"Content-Type": "application/xml"})
    if not complete_resp.ok:
        raise RuntimeError(f"HTTP {complete_resp.status_code} completing multipart upload: {complete_resp.text}")

    log_step("finalising upload")
    api.v3("POST", f"/uploads/{upload_id}/finalise")
    log_step("waiting for processing")
    poll_until_available(api, upload_id)
    return upload_id


def upload_mod(api: NexusAPI, mod_name: str, zip_path: str, version: str, file_group_id: str) -> None:
    upload_id = upload_file(api, zip_path)
    log_info(f"creating version {version} for mod file {file_group_id}")
    result = api.v3(
        "POST",
        f"/mod-files/{file_group_id}/versions",
        {
            "upload_id": upload_id,
            "name": mod_name,
            "version": version,
            "file_category": "main",
            "archive_existing_file": False,
            "primary_mod_manager_download": True,
        },
    )
    version_id = result.get("version", {}).get("id") if result else None
    fallback = result.get("id") if result else None
    log_ok(f"uploaded, version id {version_id or fallback or '?'}")


# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

def get_author_info(api: NexusAPI) -> dict:
    try:
        data = api.v1("GET", "/users/validate.json")
        return {"name": data["name"]}
    except Exception:
        return {"name": os.environ.get("NEXUSMODS_AUTHOR_NAME", "deathbeam")}


def get_my_collections(api: NexusAPI, game_domain: str) -> list[dict]:
    """List the authenticated user's collections, filtered to the target game."""
    query = """
    query {
        myCollections(viewAdultContent: true, viewUnderModeration: true, viewUnlisted: true) {
            nodes { id slug name game { domainName } }
        }
    }"""
    data = api.graphql(query)
    nodes = (data.get("myCollections") or {}).get("nodes", [])
    return [c for c in nodes if c.get("game", {}).get("domainName") == game_domain]


def build_collection_manifest(
    mods: list[dict], author_name: str, author_url: str, name: str, summary: str, description: str
) -> dict:
    # The API POST payload (CollectionManifestInfo schema) uses snake_case. The
    # collection.json embedded in the archive (Vortex ICollection schema) uses
    # camelCase — _to_camel_case_manifest converts a copy for the archive only.
    return {
        "info": {
            "author": author_name,
            "author_url": author_url,
            "name": name,
            "summary": summary or None,
            "description": description or None,
            "domain_name": GAME_DOMAIN,
        },
        "mods": [
            {
                "name": m["name"],
                "version": m["version"],
                "optional": False,
                "domain_name": GAME_DOMAIN,
                "author": author_name,
                "source": {
                    "type": "nexus",
                    "mod_id": str(m["mod_id"]),
                    "file_id": str(m["file_id"]),
                    "file_size": m.get("file_size_kb"),
                    "logical_filename": m.get("logical_filename"),
                    "update_policy": "exact",
                },
            }
            for m in mods
        ],
        "mod_rules": [],
    }


def _to_camel_case_manifest(manifest: dict) -> dict:
    """Convert the snake_case API manifest to the camelCase Vortex collection.json.

    Vortex's ICollection schema expects modId/fileId as numbers, while the API
    CollectionManifestInfo schema wants mod_id/file_id as strings.
    """
    # snake_case manifest keys (API payload) → camelCase keys (Vortex archive).
    camel = {
        "author_url": "authorUrl",
        "domain_name": "domainName",
        "mod_id": "modId",
        "file_id": "fileId",
        "file_size": "fileSize",
        "logical_filename": "logicalFilename",
        "update_policy": "updatePolicy",
        "mod_rules": "modRules",
    }

    def fix(obj):
        if isinstance(obj, dict):
            out = {}
            for k, v in obj.items():
                if v is None:
                    continue
                nk = camel.get(k, k)
                # mod_id/file_id are strings in the API payload but numbers in
                # the Vortex archive schema.
                if k in ("mod_id", "file_id") and v != "":
                    out[nk] = int(v)
                else:
                    out[nk] = fix(v)
            return out
        if isinstance(obj, list):
            return [fix(v) for v in obj]
        return obj

    return fix(manifest)

def create_collection_archive(manifest: dict, out_path: str) -> None:
    """Pack the manifest into a .7z archive (Nexus expects 7z for collections)."""
    with tempfile.TemporaryDirectory(prefix="nx-collection-") as tmp_dir:
        manifest_path = Path(tmp_dir) / "collection.json"
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        result = subprocess.run(
            ["7z", "a", "-t7z", "-mx=9", out_path, "collection.json"],
            cwd=tmp_dir,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or not Path(out_path).exists():
            raise RuntimeError(
                f"7z failed (status {result.returncode}): {result.stderr.strip()}. Is p7zip-full installed?"
            )


def upload_collection_archive(api: NexusAPI, manifest: dict) -> str:
    """Pack the manifest into a .7z archive, upload it, and clean up."""
    archive_path = str(Path("collection.7z").resolve())
    create_collection_archive(manifest, archive_path)
    try:
        return upload_file(api, archive_path)
    finally:
        if Path(archive_path).exists():
            Path(archive_path).unlink()


def sync_collection(
    api: NexusAPI,
    name: str,
    uploaded_mods: list[str],
    dry_run: bool,
    force: str,
) -> None:
    log_section(f"Collection: {name}")

    author = get_author_info(api)
    author_url = f"https://next.nexusmods.com/profile/{author['name']}"

    # Resolve the current file_id for every published mod.
    collection_mods: list[dict] = []
    for mod_name in find_mod_folders():
        info = extract_mod_info(mod_name)
        if not info or not info["version"] or not info["mod_id"]:
            continue
        try:
            file = get_published_file(api, info["mod_id"])
            if file and file["file_id"]:
                collection_mods.append(
                    {
                        "name": mod_name,
                        "version": file["version"],
                        "mod_id": info["mod_id"],
                        "file_id": file["file_id"],
                        "file_size_kb": file["file_size_kb"],
                        "logical_filename": file["logical_filename"],
                    }
                )
            else:
                log_skip(f"{mod_name}: no published file, excluding")
        except Exception as e:
            log_skip(f"{mod_name}: could not resolve file ({e}), excluding")

    if not collection_mods:
        log_skip("no publishable mods found, skipping collection")
        return

    mod_list = ', '.join(f"{m['name']} v{m['version']}" for m in collection_mods)
    log_info(f"mods: {mod_list}")

    summary = os.environ.get(
        "NEXUSMODS_COLLECTION_SUMMARY"
    ) or f"{len(collection_mods)} Darktide mods by {author['name']}"
    description = os.environ.get("NEXUSMODS_COLLECTION_DESCRIPTION") or "\n".join(
        f"{m['name']} v{m['version']}" for m in collection_mods
    )
    manifest = build_collection_manifest(
        collection_mods, author["name"], author_url, name, summary, description
    )
    collection_data = {
        "adult_content": False,
        "collection_manifest": manifest,
        "collection_schema_id": 1,
    }

    my_collections = get_my_collections(api, GAME_DOMAIN)
    existing = next((c for c in my_collections if c["name"] == name), None)

    force_collection = force in ("collection", "all")
    if existing and not uploaded_mods and not force_collection:
        log_skip(f'"{name}" exists, no mods uploaded — skipping (use --force collection to revise)')
        return

    if dry_run:
        if existing:
            log_info(f'would create new revision on "{name}" (slug: {existing["slug"]})')
        else:
            log_info(f'would create new collection "{name}"')
        _dump_collection(_to_camel_case_manifest(manifest), name)
        return

    archive_manifest = _to_camel_case_manifest(manifest)
    upload_id = upload_collection_archive(api, archive_manifest)

    if existing:
        log_info(f'creating new revision on "{name}" (slug: {existing["slug"]})')
        try:
            api.v3("PATCH", f"/collections/{existing['id']}", {"name": name, "summary": summary, "description": description})
        except Exception as e:
            log_fail(f"could not sync metadata: {e}")
        result = api.v3("POST", f"/collections/{existing['id']}/revisions", {"upload_id": upload_id, "collection_data": collection_data})
        log_ok(f"revision {result['revision_number']} created (status: {result['revision_status']})")
        log_step(f"publish at: https://www.nexusmods.com/{GAME_DOMAIN}/collections/{existing['slug']}")
    else:
        log_info(f'creating new collection "{name}"')
        result = api.v3("POST", "/collections", {"upload_id": upload_id, "collection_data": collection_data})
        log_ok(
            f"collection created (slug: {result['slug']}, revision {result['revision_number']}, status: {result['revision_status']})"
        )
        log_step(f"publish at: https://www.nexusmods.com/{GAME_DOMAIN}/collections/{result['slug']}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Publish Darktide mods to Nexus Mods.")
    parser.add_argument("--dry-run", action="store_true", help="check versions, no uploads")
    parser.add_argument(
        "--force",
        metavar="target",
        choices=["mods", "collection", "all"],
        default=None,
        help="force re-upload of mods, collection, or both (default: off — skip up-to-date mods)",
    )
    parser.add_argument("--mod", metavar="Name", help="only publish this mod folder")
    parser.add_argument("--collection", metavar="Name", help="sync a collection with this name")
    args = parser.parse_args()

    dry_run = args.dry_run
    api_key = os.environ.get("NEXUSMODS_APIKEY", "")

    if not api_key:
        print("Error: NEXUSMODS_APIKEY is not set", file=sys.stderr)
        return 1
    if dry_run:
        log_section("Dry run mode")
    else:
        print()

    folders = find_mod_folders()
    if args.mod:
        if args.mod not in folders:
            print(f'Error: mod folder "{args.mod}" not found', file=sys.stderr)
            return 1
        folders = [args.mod]

    api = NexusAPI(api_key)

    uploaded: list[str] = []
    skipped: list[str] = []
    failed: list[str] = []

    for mod_name in folders:
        cur = extract_mod_info(mod_name)

        if not cur or not cur["version"]:
            log_skip(f"{mod_name}: no version in info.json")
            skipped.append(mod_name)
            continue
        if not cur["mod_id"]:
            log_skip(f"{mod_name}: no mod_id in info.json")
            skipped.append(mod_name)
            continue

        try:
            published_file = get_published_file(api, cur["mod_id"])
        except Exception as e:
            log_fail(f"{mod_name} v{cur['version']}: could not fetch published version ({e})")
            failed.append(mod_name)
            continue
        published_version = published_file["version"] if published_file else None

        pub = f"v{published_version}" if published_version else "none"
        force_mods = args.force in ("mods", "all")
        if not force_mods and cur["version"] == published_version:
            log_skip(f"{mod_name} v{cur['version']}: up to date (published {pub})")
            skipped.append(mod_name)
            continue

        if dry_run:
            log_info(f"{mod_name} v{cur['version']}: would upload (published {pub})")
            uploaded.append(mod_name)
            continue

        log_info(f"{mod_name} v{cur['version']}: uploading (published {pub})")

        try:
            mod_uuid = resolve_mod_uuid(api, cur["mod_id"])
            file_group_id = resolve_file_group_id(api, mod_uuid)
        except Exception as e:
            log_fail(f"could not resolve file group: {e}")
            failed.append(mod_name)
            continue

        zip_name = f"{mod_name}-v{cur['version']}.zip"
        if not zip_mod(mod_name, zip_name):
            log_fail(f"could not create {zip_name}")
            failed.append(mod_name)
            continue

        try:
            upload_mod(api, mod_name, zip_name, cur["version"], file_group_id)
            uploaded.append(mod_name)
        except Exception as e:
            log_fail(f"upload failed: {e}")
            failed.append(mod_name)

    log_section("Summary")
    verb = "Would upload" if dry_run else "Uploaded"
    if uploaded:
        log_ok(f"{verb} {len(uploaded)} mod(s): {', '.join(uploaded)}")
    else:
        log_skip("no mods to upload")
    if skipped:
        log_skip(f"skipped {len(skipped)} mod(s): {', '.join(skipped)}")
    if failed:
        log_fail(f"failed {len(failed)} mod(s): {', '.join(failed)}")

    if args.collection:
        try:
            sync_collection(api, args.collection, uploaded, dry_run, args.force or "none")
        except Exception as e:
            log_fail(f"collection sync failed: {e}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
