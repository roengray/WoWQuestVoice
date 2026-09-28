const MAX_BODY_BYTES = 512 * 1024;
const MAX_RECORDS = 100;
const PUBLIC_REQUESTS_PER_DAY = 500;
const PUBLIC_RECORDS_PER_DAY = 20000;
const VALID_SECTIONS = new Set(["accept", "progress", "complete"]);
const DOWNLOAD_VERSION = "0.10.5";
const DOWNLOAD_SHA256 = "2832437ABDB156F5CBBA8B1B0F49BD272D178FE88EB7E7649F971EB69CEC0F8C";
const DOWNLOAD_URL = "https://github.com/roengray/WoWQuestVoice/releases/download/v0.10.5/WoWQuestVoice-v0.10.5-addon.zip";

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function html(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
    },
  });
}

async function landingPage(env) {
  const download = `<a class="button" href="${DOWNLOAD_URL}">애드온 ZIP 다운로드</a>`;
  const downloadNote = `애드온 전체 ZIP v${DOWNLOAD_VERSION} · 343.2MB · 실행 파일 없음 · 음성 1,639개 포함<br>SHA-256: <code>${DOWNLOAD_SHA256}</code>`;
  return html(`<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>WoWQuestVoice</title><meta name="description" content="월드 오브 워크래프트 한국어 퀘스트 음성 애드온">
<style>
:root{color-scheme:dark;--bg:#0b1018;--panel:#151d29;--line:#2a394c;--text:#f5f7fa;--muted:#9eb0c5;--blue:#42a5ff;--gold:#efb84a}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 70% 0,#172c47 0,transparent 42%),var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Segoe UI",sans-serif;line-height:1.65}main{max-width:960px;margin:auto;padding:72px 24px}.eyebrow{color:var(--gold);font-weight:700;letter-spacing:.08em}h1{font-size:clamp(42px,8vw,76px);line-height:1.05;margin:12px 0 22px}h2{font-size:25px;margin:0 0 10px}.lead{max-width:720px;color:#cad5e2;font-size:20px}.actions{margin:34px 0 10px}.button{display:inline-block;background:var(--blue);color:#06111d;text-decoration:none;font-weight:800;padding:14px 22px;border-radius:9px}.button.disabled{background:#4c5968;color:#c8d0d9}.note{color:var(--muted);font-size:14px}.note code{overflow-wrap:anywhere}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-top:62px}.card{background:color-mix(in srgb,var(--panel) 92%,transparent);border:1px solid var(--line);border-radius:14px;padding:24px}.card p{color:var(--muted);margin:0}.privacy{margin-top:42px;padding-top:28px;border-top:1px solid var(--line);color:var(--muted)}footer{margin-top:54px;color:#73869b;font-size:13px}@media(max-width:720px){main{padding-top:48px}.grid{grid-template-columns:1fr;margin-top:44px}}
</style></head><body><main>
<div class="eyebrow">한국어 퀘스트 보이스오버</div><h1>WoWQuestVoice</h1>
<p class="lead">퀘스트 창에서 바로 한국어 음성을 듣고, 재생 중에는 게임 음악과 효과음을 자동으로 낮춥니다.</p>
<div class="actions">${download}</div><p class="note">${downloadNote}</p>
<section class="grid">
  <article class="card"><h2>게임 안에서 바로</h2><p>퀘스트 창의 재생·정지 버튼으로 음성을 조작합니다.</p></article>
  <article class="card"><h2>간단한 ZIP 설치</h2><p>압축을 풀어 WoW의 _classic_beta_\Interface\AddOns 폴더에 넣으면 됩니다.</p></article>
  <article class="card"><h2>실행 파일 없음</h2><p>ZIP 배포본에는 업데이터나 백그라운드 수집 프로그램이 포함되지 않습니다.</p></article>
</section>
<section class="privacy"><h2>설치 및 업데이트</h2><p>ZIP 안의 WoWQuestVoice 폴더를 World of Warcraft\_classic_beta_\Interface\AddOns 안에 복사하세요. 새 버전은 같은 위치에 덮어쓰면 됩니다. ZIP 배포본은 외부로 데이터를 전송하지 않습니다.</p></section>
<footer>WoWQuestVoice · World of Warcraft는 Blizzard Entertainment의 상표입니다.</footer>
</main></body></html>`);
}

async function downloadArchive(env) {
  return Response.redirect(DOWNLOAD_URL, 302);
}

function bearerToken(request) {
  const value = request.headers.get("authorization") || "";
  return value.startsWith("Bearer ") ? value.slice(7) : "";
}

function constantTimeEqual(left, right) {
  const a = new TextEncoder().encode(left || "");
  const b = new TextEncoder().encode(right || "");
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

async function hmacHex(secret, value) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function enforcePublicRateLimit(request, env, recordCount) {
  if (!env.ABUSE_SALT) {
    return { ok: false, response: json({ ok: false, error: "collector_not_configured" }, 503) };
  }
  const address = request.headers.get("CF-Connecting-IP") || "unknown";
  const now = Math.floor(Date.now() / 1000);
  const windowStart = Math.floor(now / 86400) * 86400;
  const bucket = await hmacHex(env.ABUSE_SALT, `${windowStart}\n${address}`);
  await env.DB.prepare(
    "DELETE FROM upload_rate_limits WHERE expires_at < ?",
  ).bind(now).run();
  const row = await env.DB.prepare(`
    INSERT INTO upload_rate_limits
      (bucket, window_start, request_count, record_count, expires_at)
    VALUES (?, ?, 1, ?, ?)
    ON CONFLICT(bucket) DO UPDATE SET
      request_count = request_count + 1,
      record_count = record_count + excluded.record_count
    RETURNING request_count AS requestCount, record_count AS recordCount
  `).bind(bucket, windowStart, recordCount, windowStart + 172800).first();
  if ((row?.requestCount || 0) > PUBLIC_REQUESTS_PER_DAY ||
      (row?.recordCount || 0) > PUBLIC_RECORDS_PER_DAY) {
    return { ok: false, response: json({ ok: false, error: "rate_limited" }, 429) };
  }
  return { ok: true };
}

function cleanString(value, maxLength) {
  if (typeof value !== "string") return "";
  return value.replace(/\u0000/g, "").trim().slice(0, maxLength);
}

async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function receiveBatch(request, env) {
  const contentLength = Number(request.headers.get("content-length") || 0);
  if (contentLength > MAX_BODY_BYTES) {
    return json({ ok: false, error: "payload_too_large" }, 413);
  }

  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
    return json({ ok: false, error: "payload_too_large" }, 413);
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  if (payload?.schemaVersion !== 1 || !Array.isArray(payload.records)) {
    return json({ ok: false, error: "invalid_schema" }, 400);
  }
  if (payload.records.length < 1 || payload.records.length > MAX_RECORDS) {
    return json({ ok: false, error: "invalid_record_count" }, 400);
  }

  const suppliedToken = bearerToken(request);
  const trustedClient = Boolean(
    env.UPLOAD_TOKEN && suppliedToken && constantTimeEqual(suppliedToken, env.UPLOAD_TOKEN),
  );
  if (!trustedClient) {
    const limit = await enforcePublicRateLimit(request, env, payload.records.length);
    if (!limit.ok) return limit.response;
  }

  const locale = cleanString(payload.locale, 12);
  const clientBuild = cleanString(payload.clientBuild, 40);
  const addonVersion = cleanString(payload.addonVersion, 24);
  if (locale !== "koKR") {
    return json({ ok: false, error: "unsupported_locale" }, 400);
  }

  const records = [];
  for (const input of payload.records) {
    const questId = Number(input?.questId);
    const section = cleanString(input?.section, 16);
    const title = cleanString(input?.title, 512);
    const text = cleanString(input?.text, 16000);
    if (!Number.isInteger(questId) || questId < 1 || questId > 200000) {
      return json({ ok: false, error: "invalid_quest_id" }, 400);
    }
    if (!VALID_SECTIONS.has(section) || !text) {
      return json({ ok: false, error: "invalid_record" }, 400);
    }
    const textHash = await sha256Hex(`${locale}\n${questId}\n${section}\n${title}\n${text}`);
    records.push({ questId, section, title, text, textHash });
  }

  const statement = env.DB.prepare(`
    INSERT INTO quest_texts
      (locale, quest_id, section, title, text, text_hash, client_build, addon_version)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(locale, quest_id, section, text_hash) DO UPDATE SET
      last_seen = CURRENT_TIMESTAMP,
      submission_count = submission_count + 1,
      client_build = excluded.client_build,
      addon_version = excluded.addon_version
  `);
  await env.DB.batch(records.map((record) => statement.bind(
    locale,
    record.questId,
    record.section,
    record.title,
    record.text,
    record.textHash,
    clientBuild,
    addonVersion,
  )));

  return json({ ok: true, accepted: records.length });
}

async function exportRows(request, env) {
  if (!env.ADMIN_TOKEN || bearerToken(request) !== env.ADMIN_TOKEN) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  const url = new URL(request.url);
  const after = Math.max(0, Number(url.searchParams.get("after") || 0));
  const limit = Math.min(1000, Math.max(1, Number(url.searchParams.get("limit") || 500)));
  const result = await env.DB.prepare(`
    SELECT id, locale, quest_id AS questId, section, title, text, text_hash AS textHash,
           client_build AS clientBuild, addon_version AS addonVersion,
           first_seen AS firstSeen, last_seen AS lastSeen,
           submission_count AS submissionCount
      FROM quest_texts
     WHERE id > ?
     ORDER BY id
     LIMIT ?
  `).bind(after, limit).all();
  return json({ ok: true, records: result.results || [] });
}

async function stats(env) {
  const row = await env.DB.prepare(`
    SELECT COUNT(*) AS records, COUNT(DISTINCT quest_id) AS quests
      FROM quest_texts
  `).first();
  return json({ ok: true, records: row?.records || 0, quests: row?.quests || 0 });
}

async function audioManifest(env) {
  const object = await env.AUDIO.get("releases/manifest.json");
  if (!object) {
    return json({ schemaVersion: 1, version: "0", packages: [] });
  }
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "public, max-age=60");
  return new Response(object.body, { headers });
}

async function audioFile(request, env, pathname) {
  const encoded = pathname.slice("/v1/audio/files/".length);
  let key;
  try {
    key = decodeURIComponent(encoded);
  } catch {
    return json({ ok: false, error: "invalid_path" }, 400);
  }
  if (!key || key.includes("..") || key.startsWith("/") || key.includes("\\")) {
    return json({ ok: false, error: "invalid_path" }, 400);
  }

  const rangeHeader = request.headers.get("range");
  const options = rangeHeader ? { range: request.headers } : undefined;
  const object = await env.AUDIO.get(`releases/${key}`, options);
  if (!object) return json({ ok: false, error: "not_found" }, 404);

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("accept-ranges", "bytes");
  headers.set("cache-control", "public, max-age=31536000, immutable");
  if (object.range) {
    const offset = object.range.offset || 0;
    const length = object.range.length || object.size;
    headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("content-length", String(length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("content-length", String(object.size));
  return new Response(object.body, { headers });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return landingPage(env);
    }
    if (request.method === "GET" && url.pathname === "/download") {
      return downloadArchive(env);
    }
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "WoWQuestVoice Collector", schemaVersion: 1, audioUpdates: true });
    }
    if (request.method === "GET" && url.pathname === "/v1/audio/manifest") {
      return audioManifest(env);
    }
    if (request.method === "GET" && url.pathname.startsWith("/v1/audio/files/")) {
      return audioFile(request, env, url.pathname);
    }
    if (request.method === "POST" && url.pathname === "/v1/quests") {
      return receiveBatch(request, env);
    }
    if (request.method === "GET" && url.pathname === "/v1/export") {
      return exportRows(request, env);
    }
    if (request.method === "GET" && url.pathname === "/v1/stats") {
      if (!env.ADMIN_TOKEN || bearerToken(request) !== env.ADMIN_TOKEN) {
        return json({ ok: false, error: "unauthorized" }, 401);
      }
      return stats(env);
    }
    return json({ ok: false, error: "not_found" }, 404);
  },
};
