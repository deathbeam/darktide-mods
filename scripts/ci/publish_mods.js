#!/usr/bin/env node
/**
 * Release mods to Nexus Mods, using the published version there as the source
 * of truth (no git diffing).
 *
 * For every mod folder with a `.mod` file that declares `version` and `mod_id`:
 *   1. Fetch the mod's currently published MAIN version from the Nexus Mods API.
 *   2. Compare it to the local `version` in the `.mod` file.
 *   3. If they differ (or --force), zip the mod folder and upload a new version.
 *
 * `mod_id` is the NexusMods mod id (the number in the mod's URL). The
 * file_group_id is resolved automatically from the API.
 *
 * With --collection <Name>, after uploading mods the script also syncs a Nexus
 * Mods collection that references every published mod by mod_id + file_id. The
 * collection is created on first run and gets a new draft revision whenever a
 * mod was uploaded (or --force). Revisions stay in draft until published on the
 * website.
 *
 * Usage:
 *     node scripts/ci/publish_mods.js [--dry-run] [--force] [--mod <Name>] [--collection <Name>]
 *
 * Required environment variables (unless --dry-run):
 *     NEXUSMODS_APIKEY        Your Nexus Mods API key
 *
 * Optional environment variables:
 *     NEXUSMODS_GAME_DOMAIN   Nexus Mods game domain slug (default: warhammer40kdarktide)
 *     NEXUSMODS_API_BASE      Default: https://api.nexusmods.com/v3
 *     NEXUSMODS_AUTHOR_NAME   Fallback author name if /users/validate fails (default: deathbeam)
 *     NEXUSMODS_COLLECTION_SUMMARY     Collection summary text
 *     NEXUSMODS_COLLECTION_DESCRIPTION  Collection description text
 */

"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const API_BASE = (
  process.env.NEXUSMODS_API_BASE || "https://api.nexusmods.com/v3"
).replace(/\/$/, "");
const V1_BASE = "https://api.nexusmods.com/v1";
const GRAPHQL_BASE = "https://api.nexusmods.com/v2/graphql";
const GAME_DOMAIN = process.env.NEXUSMODS_GAME_DOMAIN || "warhammer40kdarktide";

function execCmd(args) {
  const result = spawnSync(args[0], args.slice(1), { encoding: "utf8" });
  return (result.stdout || "").trim();
}

function parseArgs(argv) {
  const out = { dryRun: false, force: false, mod: null, collection: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") out.dryRun = true;
    else if (a === "--force") out.force = true;
    else if (a === "--mod") out.mod = argv[++i];
    else if (a.startsWith("--mod=")) out.mod = a.slice("--mod=".length);
    else if (a === "--collection") out.collection = argv[++i];
    else if (a.startsWith("--collection=")) out.collection = a.slice("--collection=".length);
    else if (a === "-h" || a === "--help") {
      console.log("Usage: publish_mods.js [--dry-run] [--force] [--mod <Name>] [--collection <Name>]");
      process.exit(0);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// .mod file parsing
// ---------------------------------------------------------------------------

function extractModInfo(filePath) {
  let content;
  try {
    content = fs.readFileSync(filePath, "utf8");
  } catch (e) {
    console.error(`Warning: could not read ${filePath}: ${e.message}`);
    return null;
  }
  // Match single or double quoted values (StyLua prefers single quotes).
  const versionM = content.match(/\bversion\s*=\s*["']([^"']+)["']/);
  const modIdM = content.match(/\bmod_id\s*=\s*["']([^"']+)["']/);
  return {
    version: versionM ? versionM[1] : null,
    mod_id: modIdM ? modIdM[1] : null,
  };
}

function findModFolders() {
  const out = execCmd(["git", "ls-files", "*.mod"]);
  return out
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith(".template-dmf/"))
    .map((p) => p.split("/")[0]);
}

// ---------------------------------------------------------------------------
// Zipping
// ---------------------------------------------------------------------------

function zipMod(modName, zipName) {
  const result = spawnSync("zip", ["-r", zipName, modName], { encoding: "utf8" });
  return result.status === 0 && fs.existsSync(zipName);
}

// ---------------------------------------------------------------------------
// Nexus Mods API
// ---------------------------------------------------------------------------

async function v3Request(method, urlPath, apiKey, body) {
  const url = `${API_BASE}${urlPath}`;
  const headers = {
    apikey: apiKey,
    "User-Agent": "deathbeam/darktide-mods publish script",
  };
  const init = { method };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  init.headers = headers;

  const resp = await fetch(url, init);
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`HTTP ${resp.status} from ${method} ${url}: ${text}`);
  }
  if (!text) return null;
  const parsed = JSON.parse(text);
  return parsed.data ?? parsed;
}

async function v1Request(method, urlPath, apiKey) {
  const url = `${V1_BASE}${urlPath}`;
  const resp = await fetch(url, {
    method,
    headers: {
      apikey: apiKey,
      "User-Agent": "deathbeam/darktide-mods publish script",
    },
  });
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`HTTP ${resp.status} from ${method} ${url}: ${text}`);
  }
  return JSON.parse(text);
}

async function graphqlRequest(query, variables, apiKey) {
  const resp = await fetch(GRAPHQL_BASE, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: apiKey,
      "User-Agent": "deathbeam/darktide-mods publish script",
    },
    body: JSON.stringify({ query, variables }),
  });
  const text = await resp.text();
  const parsed = JSON.parse(text);
  if (!resp.ok || parsed.errors) {
    const msg = parsed.errors ? parsed.errors.map((e) => e.message).join("; ") : text;
    throw new Error(`GraphQL error: ${msg}`);
  }
  return parsed.data;
}

// Resolve the mod's UUID from its game-scoped mod_id.
async function resolveModUuid(modId, apiKey) {
  const info = await v3Request(
    "GET",
    `/games/${GAME_DOMAIN}/mods/${modId}`,
    apiKey,
  );
  if (!info.id) {
    throw new Error(`no 'id' field for mod ${modId}`);
  }
  return info.id;
}

// Fetch the currently published MAIN file from the v1 files list.
// Falls back to the most recently uploaded file when no MAIN category exists.
async function getPublishedFile(modId, apiKey) {
  const data = await v1Request(
    "GET",
    `/games/${GAME_DOMAIN}/mods/${modId}/files.json`,
    apiKey,
  );
  const files = data.files || [];
  if (files.length === 0) return null;

  const main = files.find(
    (f) => f.category_name === "MAIN" || f.category_id === 1,
  );
  const f = main || [...files].sort(
    (a, b) =>
      new Date(b.uploaded_time).getTime() - new Date(a.uploaded_time).getTime(),
  )[0];
  // size/size_kb are both in kilobytes; file_name is the logical filename.
  return {
    version: f.version || null,
    file_id: f.file_id,
    file_size_kb: f.size_kb ?? f.size ?? null,
    logical_filename: f.file_name || null,
  };
}

// Resolve the file-update group id (where new versions get uploaded).
async function resolveFileGroupId(modUuid, apiKey) {
  const info = await v3Request("GET", `/mods/${modUuid}/files`, apiKey);
  const groups = info.mod_files || [];
  if (groups.length === 0) {
    throw new Error("no file update groups found; create one on Nexus Mods first");
  }

  const activeGroups = groups.filter((g) => g.is_active);
  const candidates = activeGroups.length > 0 ? activeGroups : groups;

  candidates.sort((a, b) => {
    const aTime = a.last_file_uploaded_at
      ? new Date(a.last_file_uploaded_at).getTime()
      : 0;
    const bTime = b.last_file_uploaded_at
      ? new Date(b.last_file_uploaded_at).getTime()
      : 0;
    return bTime - aTime;
  });

  return candidates[0].id;
}

async function putToPresignedUrl(url, data) {
  const resp = await fetch(url, {
    method: "PUT",
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Length": String(data.byteLength ?? data.length),
    },
    body: data,
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`HTTP ${resp.status} uploading to presigned URL: ${text}`);
  }
  const etag = resp.headers.get("ETag") || "";
  return etag.replace(/^"|"$/g, "");
}

async function pollUntilAvailable(uploadId, apiKey) {
  for (let attempt = 0; attempt < 60; attempt++) {
    const stateInfo = await v3Request("GET", `/uploads/${uploadId}`, apiKey);
    if (stateInfo.state === "available") return;
    console.log(`  processing: ${stateInfo.state}`);
    const delay = Math.min(2 * Math.pow(1.5, attempt), 30) * 1000;
    await new Promise((resolve) => setTimeout(resolve, delay));
  }
  throw new Error(`timed out waiting for upload ${uploadId} to become available`);
}

// Upload a file via the v3 multipart flow and wait for it to be processed.
// Returns the finalised upload_id, ready to be claimed by a mod file version
// or a collection/revision.
async function uploadFile(filePath, apiKey) {
  const fileSize = fs.statSync(filePath).size;
  const fileBasename = path.basename(filePath);

  // Multipart upload for all sizes; the single `/uploads` endpoint signs
  // `content-disposition`, which R2 rejects unless echoed byte-for-byte.
  const uploadInfo = await v3Request("POST", "/uploads/multipart", apiKey, {
    filename: fileBasename,
    size_bytes: fileSize,
  });
  const uploadId = uploadInfo.id;
  const partUrls = uploadInfo.part_presigned_urls || uploadInfo.parts_presigned_url;
  const partSize = uploadInfo.part_size_bytes || uploadInfo.parts_size;
  const completeUrl = uploadInfo.complete_presigned_url;
  console.log(
    `  Uploading ${fileBasename} (${fileSize} bytes), ${partUrls.length} part(s)`,
  );

  const fd = fs.openSync(filePath, "r");
  const parts = [];
  for (let i = 0; i < partUrls.length; i++) {
    const partNumber = i + 1;
    const chunk = Buffer.alloc(
      Math.max(0, Math.min(partSize, fileSize - i * partSize)),
    );
    fs.readSync(fd, chunk, 0, chunk.length, i * partSize);
    console.log(`  Part ${partNumber}/${partUrls.length} (${chunk.length} bytes)`);
    const etag = await putToPresignedUrl(partUrls[i], chunk);
    parts.push({ partNumber, etag });
  }
  fs.closeSync(fd);

  console.log("  Completing multipart upload");
  const xmlParts = parts
    .map(
      ({ partNumber, etag }) =>
        `  <Part>\n    <PartNumber>${partNumber}</PartNumber>\n    <ETag>${etag}</ETag>\n  </Part>`,
    )
    .join("\n");
  const xml = `<CompleteMultipartUpload>\n${xmlParts}\n</CompleteMultipartUpload>`;
  const completeResp = await fetch(completeUrl, {
    method: "POST",
    headers: { "Content-Type": "application/xml" },
    body: xml,
  });
  if (!completeResp.ok) {
    const text = await completeResp.text();
    throw new Error(`HTTP ${completeResp.status} completing multipart upload: ${text}`);
  }

  console.log("  Finalising upload");
  await v3Request("POST", `/uploads/${uploadId}/finalise`, apiKey);
  console.log("  Waiting for processing");
  await pollUntilAvailable(uploadId, apiKey);
  return uploadId;
}

async function uploadMod(modName, zipPath, version, fileGroupId, apiKey) {
  const uploadId = await uploadFile(zipPath, apiKey);
  console.log(`  Creating version ${version} for mod file ${fileGroupId}`);
  const result = await v3Request(
    "POST",
    `/mod-files/${fileGroupId}/versions`,
    apiKey,
    {
      upload_id: uploadId,
      name: modName,
      version,
      file_category: "main",
      archive_existing_file: false,
      primary_mod_manager_download: true,
    },
  );
  const versionId = result.version && result.version.id;
  console.log(`  uploaded, version id ${versionId || result.id || "?"}`);
}

// ---------------------------------------------------------------------------
// Collections
// ---------------------------------------------------------------------------

async function getAuthorInfo(apiKey) {
  try {
    const data = await v1Request("GET", "/users/validate.json", apiKey);
    return { name: data.name };
  } catch (e) {
    return { name: process.env.NEXUSMODS_AUTHOR_NAME || "deathbeam" };
  }
}

// List the authenticated user's collections, filtered to the target game.
async function getMyCollections(apiKey, gameDomain) {
  const query = `query {
    myCollections(viewAdultContent: true, viewUnderModeration: true, viewUnlisted: true) {
      nodes { id slug name game { domainName } }
    }
  }`;
  const data = await graphqlRequest(query, {}, apiKey);
  const nodes = (data.myCollections && data.myCollections.nodes) || [];
  return nodes.filter((c) => c.game && c.game.domainName === gameDomain);
}

function buildCollectionManifest(mods, authorName, authorUrl, name, summary, description) {
  return {
    info: {
      author: authorName,
      author_url: authorUrl,
      name,
      summary: summary || null,
      description: description || null,
      domain_name: GAME_DOMAIN,
    },
    mods: mods.map((m) => ({
      name: m.name,
      version: m.version,
      optional: false,
      domain_name: GAME_DOMAIN,
      author: authorName,
      source: {
        type: "nexus",
        mod_id: String(m.mod_id),
        file_id: String(m.file_id),
        file_size: m.file_size_kb,
        logical_filename: m.logical_filename,
        update_policy: "exact",
      },
    })),
  };
}

// Pack the manifest into a .7z archive (Nexus expects 7z for collections).
function createCollectionArchive(manifest, outPath) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nx-collection-"));
  const manifestPath = path.join(tmpDir, "collection.json");
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  const result = spawnSync("7z", ["a", "-t7z", "-mx=9", outPath, "collection.json"], {
    cwd: tmpDir,
    encoding: "utf8",
  });
  fs.rmSync(tmpDir, { recursive: true, force: true });
  if (result.status !== 0 || !fs.existsSync(outPath)) {
    throw new Error(
      `7z failed (status ${result.status}): ${(result.stderr || "").trim()}. Is p7zip-full installed?`,
    );
  }
}

async function createCollection(uploadId, collectionData, apiKey) {
  return v3Request("POST", "/collections", apiKey, {
    upload_id: uploadId,
    collection_data: collectionData,
  });
}

async function createCollectionRevision(collectionId, uploadId, collectionData, apiKey) {
  return v3Request("POST", `/collections/${collectionId}/revisions`, apiKey, {
    upload_id: uploadId,
    collection_data: collectionData,
  });
}

// Best-effort metadata sync; failures are non-fatal.
async function editCollection(collectionId, patch, apiKey) {
  await v3Request("PATCH", `/collections/${collectionId}`, apiKey, patch);
}

// Pack the manifest into a .7z archive, upload it, and clean up.
async function uploadCollectionArchive(manifest, apiKey) {
  const archivePath = path.resolve("collection.7z");
  createCollectionArchive(manifest, archivePath);
  try {
    return await uploadFile(archivePath, apiKey);
  } finally {
    if (fs.existsSync(archivePath)) fs.unlinkSync(archivePath);
  }
}

async function syncCollection(name, uploadedMods, apiKey, dryRun, force) {
  console.log(`\n--- Collection: ${name} ---`);

  const author = await getAuthorInfo(apiKey);
  const authorUrl = `https://next.nexusmods.com/profile/${author.name}`;

  // Resolve the current file_id for every published mod.
  const collectionMods = [];
  for (const modName of findModFolders()) {
    const info = extractModInfo(`${modName}/${modName}.mod`);
    if (!info || !info.version || !info.mod_id) continue;
    try {
      const file = await getPublishedFile(info.mod_id, apiKey);
      if (file && file.file_id) {
        collectionMods.push({
          name: modName,
          version: file.version,
          mod_id: info.mod_id,
          file_id: file.file_id,
          file_size_kb: file.file_size_kb,
          logical_filename: file.logical_filename,
        });
      } else {
        console.log(`  ${modName}: no published file, excluding`);
      }
    } catch (e) {
      console.log(`  ${modName}: could not resolve file (${e.message}), excluding`);
    }
  }

  if (collectionMods.length === 0) {
    console.log("  no publishable mods found, skipping collection");
    return;
  }

  console.log(`  mods: ${collectionMods.map((m) => `${m.name} v${m.version}`).join(", ")}`);

  const summary =
    process.env.NEXUSMODS_COLLECTION_SUMMARY ||
    `${collectionMods.length} Darktide mods by ${author.name}`;
  const description =
    process.env.NEXUSMODS_COLLECTION_DESCRIPTION ||
    collectionMods.map((m) => `${m.name} v${m.version}`).join("\n");
  const manifest = buildCollectionManifest(
    collectionMods,
    author.name,
    authorUrl,
    name,
    summary,
    description,
  );
  const collectionData = {
    adult_content: false,
    collection_manifest: manifest,
    collection_schema_id: 1,
  };

  const myCollections = await getMyCollections(apiKey, GAME_DOMAIN);
  const existing = myCollections.find((c) => c.name === name);

  if (existing && uploadedMods.length === 0 && !force) {
    console.log(`  "${name}" exists, no mods uploaded — skipping (use --force to revise)`);
    return;
  }

  if (dryRun) {
    if (existing) {
      console.log(`  would create new revision on "${name}" (slug: ${existing.slug})`);
    } else {
      console.log(`  would create new collection "${name}"`);
    }
    return;
  }

  const uploadId = await uploadCollectionArchive(manifest, apiKey);

  if (existing) {
    console.log(`  creating new revision on "${name}" (slug: ${existing.slug})`);
    try {
      await editCollection(existing.id, { name, summary, description }, apiKey);
    } catch (e) {
      console.log(`  warning: could not sync metadata: ${e.message}`);
    }
    const result = await createCollectionRevision(existing.id, uploadId, collectionData, apiKey);
    console.log(`  revision ${result.revision_number} created (status: ${result.revision_status})`);
    console.log(`  publish at: https://www.nexusmods.com/${GAME_DOMAIN}/collections/${existing.slug}`);
  } else {
    console.log(`  creating new collection "${name}"`);
    const result = await createCollection(uploadId, collectionData, apiKey);
    console.log(
      `  collection created (slug: ${result.slug}, revision ${result.revision_number}, status: ${result.revision_status})`,
    );
    console.log(`  publish at: https://www.nexusmods.com/${GAME_DOMAIN}/collections/${result.slug}`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const dryRun = args.dryRun;
  const apiKey = process.env.NEXUSMODS_APIKEY || "";

  if (dryRun) console.log("Dry run mode");
  if (!apiKey && !dryRun) {
    console.error("Error: NEXUSMODS_APIKEY is not set");
    process.exit(1);
  }
  console.log("");

  let folders = findModFolders();
  if (args.mod) {
    if (!folders.includes(args.mod)) {
      console.error(`Error: mod folder "${args.mod}" not found`);
      process.exit(1);
    }
    folders = [args.mod];
  }

  const uploaded = [];
  const skipped = [];
  const failed = [];

  for (const modName of folders) {
    const filePath = `${modName}/${modName}.mod`;
    const cur = extractModInfo(filePath);

    if (!cur || !cur.version) {
      console.log(`${modName}: no version in .mod file, skipping`);
      skipped.push(modName);
      continue;
    }
    if (!cur.mod_id) {
      console.log(`${modName}: no mod_id in .mod file, skipping`);
      skipped.push(modName);
      continue;
    }

    let publishedFile;
    try {
      publishedFile = await getPublishedFile(cur.mod_id, apiKey);
    } catch (e) {
      console.log(
        `${modName} v${cur.version}: could not fetch published version (${e.message}), failed`,
      );
      failed.push(modName);
      continue;
    }
    const publishedVersion = publishedFile ? publishedFile.version : null;

    const pub = publishedVersion ? `v${publishedVersion}` : "none";
    if (!args.force && cur.version === publishedVersion) {
      console.log(`${modName} v${cur.version}: up to date (published ${pub}), skipping`);
      skipped.push(modName);
      continue;
    }

    if (dryRun) {
      console.log(`${modName} v${cur.version}: would upload (published ${pub})`);
      uploaded.push(modName);
      continue;
    }

    console.log(`${modName} v${cur.version}: uploading (published ${pub})`);

    let fileGroupId;
    try {
      const modUuid = await resolveModUuid(cur.mod_id, apiKey);
      fileGroupId = await resolveFileGroupId(modUuid, apiKey);
    } catch (e) {
      console.log(`  could not resolve file group: ${e.message}`);
      failed.push(modName);
      continue;
    }

    const zipName = `${modName}-v${cur.version}.zip`;
    if (!zipMod(modName, zipName)) {
      console.log(`  could not create ${zipName}`);
      failed.push(modName);
      continue;
    }

    try {
      await uploadMod(modName, zipName, cur.version, fileGroupId, apiKey);
      uploaded.push(modName);
    } catch (e) {
      console.log(`  upload failed: ${e.message}`);
      failed.push(modName);
    }
  }

  console.log("");
  const verb = dryRun ? "Would upload" : "Uploaded";
  if (uploaded.length > 0) {
    console.log(`${verb} ${uploaded.length} mod(s): ${uploaded.join(", ")}`);
  } else {
    console.log("No mods were uploaded.");
  }
  if (skipped.length > 0) {
    console.log(`Skipped ${skipped.length} mod(s): ${skipped.join(", ")}`);
  }
  if (failed.length > 0) {
    console.log(`Failed ${failed.length} mod(s): ${failed.join(", ")}`);
  }

  if (args.collection) {
    if (!apiKey) {
      console.log("\nCollection sync skipped: NEXUSMODS_APIKEY required for collection lookups");
    } else {
      try {
        await syncCollection(args.collection, uploaded, apiKey, dryRun, args.force);
      } catch (e) {
        console.log(`\nCollection sync failed: ${e.message}`);
      }
    }
  }

  process.exit(failed.length > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
