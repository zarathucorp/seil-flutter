#!/usr/bin/env node

import { createSign } from 'node:crypto';
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const ANDROID_PUBLISHER_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_PLAY_API_BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3';

const packageName = readEnv('GOOGLE_PLAY_PACKAGE_NAME', 'com.zarathu.seil');
const tracks = readListEnv('GOOGLE_PLAY_TRACKS', ['production', 'alpha']);
const statePath = readEnv('PLAY_RELEASE_STATE_PATH', '.github/state/google-play-release-state.json');
const notifyOnFirstRun = readBoolEnv('NOTIFY_ON_FIRST_RUN', false);

main().catch(async (error) => {
  console.error(`::error::${error.message}`);
  if (error.cause) {
    console.error(error.cause);
  }
  await writeFailureStepSummary(error).catch((summaryError) => {
    console.error(`::warning::Could not write failure summary: ${summaryError.message}`);
  });
  process.exitCode = 1;
});

async function main() {
  const serviceAccount = parseServiceAccount(requiredEnv('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'));
  const accessToken = await getGoogleAccessToken(serviceAccount);
  const previousState = await readJsonIfExists(statePath);
  const currentState = await fetchPlayState(accessToken);
  const changes = diffTrackVersionCodes(previousState, currentState);
  const isFirstRun = previousState == null;

  await writeJson(statePath, currentState);
  await writeStepSummary(previousState, currentState, changes, isFirstRun);

  if (changes.length === 0) {
    console.log('No new Google Play version codes detected.');
    return;
  }

  if (isFirstRun && !notifyOnFirstRun) {
    console.log('Initial Google Play snapshot saved without Slack notification.');
    return;
  }

  await postSlackNotification(changes, currentState);
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function readEnv(name, fallback) {
  const value = process.env[name];
  return value && value.trim() !== '' ? value.trim() : fallback;
}

function readListEnv(name, fallback) {
  const rawValue = process.env[name];
  const values = rawValue
    ? rawValue.split(',').map((value) => value.trim()).filter(Boolean)
    : fallback;
  if (values.length === 0) {
    throw new Error(`${name} must contain at least one track name`);
  }
  return [...new Set(values)];
}

function readBoolEnv(name, fallback) {
  const value = process.env[name];
  if (value == null || value.trim() === '') {
    return fallback;
  }
  return ['1', 'true', 'yes', 'y'].includes(value.trim().toLowerCase());
}

function parseServiceAccount(rawValue) {
  const trimmed = rawValue.trim();
  for (const candidate of [trimmed, decodeBase64(trimmed)]) {
    if (!candidate) {
      continue;
    }
    try {
      const parsed = JSON.parse(candidate);
      if (!parsed.client_email || !parsed.private_key) {
        throw new Error('service account JSON must include client_email and private_key');
      }
      return parsed;
    } catch {
      // Keep secrets out of logs while still allowing raw JSON or base64 input.
    }
  }
  throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON must be raw JSON or base64-encoded JSON');
}

function decodeBase64(value) {
  try {
    return Buffer.from(value, 'base64').toString('utf8');
  } catch {
    return null;
  }
}

async function getGoogleAccessToken(serviceAccount) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: serviceAccount.client_email,
    scope: ANDROID_PUBLISHER_SCOPE,
    aud: GOOGLE_TOKEN_URL,
    exp: nowSeconds + 3600,
    iat: nowSeconds,
  };

  const unsignedJwt = `${base64UrlJson(header)}.${base64UrlJson(claims)}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsignedJwt);
  signer.end();
  const signature = signer.sign(serviceAccount.private_key).toString('base64url');
  const assertion = `${unsignedJwt}.${signature}`;

  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const payload = await readResponseJson(response);
  if (!response.ok) {
    throw new Error(`Google OAuth token request failed: ${response.status}`, {
      cause: JSON.stringify(payload),
    });
  }
  if (!payload.access_token) {
    throw new Error('Google OAuth token response did not include access_token');
  }
  return payload.access_token;
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

async function fetchPlayState(accessToken) {
  const edit = await googlePlayJson(accessToken, 'POST', `/applications/${encodeURIComponent(packageName)}/edits`);
  if (!edit.id) {
    throw new Error('Google Play edit insert response did not include id');
  }

  try {
    const trackStates = [];
    for (const track of tracks) {
      const trackState = await fetchTrackState(accessToken, edit.id, track);
      if (trackState) {
        trackStates.push(trackState);
      }
    }
    return {
      packageName,
      observedAt: new Date().toISOString(),
      tracks: trackStates.sort((a, b) => a.track.localeCompare(b.track)),
    };
  } finally {
    await deleteEdit(accessToken, edit.id);
  }
}

async function fetchTrackState(accessToken, editId, track) {
  try {
    const trackPayload = await googlePlayJson(
      accessToken,
      'GET',
      `/applications/${encodeURIComponent(packageName)}/edits/${encodeURIComponent(editId)}/tracks/${encodeURIComponent(track)}`,
    );
    const releases = Array.isArray(trackPayload.releases) ? trackPayload.releases : [];
    return {
      track,
      releases: releases.map(normalizeRelease).sort(compareReleases),
    };
  } catch (error) {
    if (error instanceof GooglePlayError && error.status === 404) {
      console.log(`::warning::Google Play track not found and skipped: ${track}`);
      return null;
    }
    throw error;
  }
}

async function deleteEdit(accessToken, editId) {
  try {
    await googlePlayJson(
      accessToken,
      'DELETE',
      `/applications/${encodeURIComponent(packageName)}/edits/${encodeURIComponent(editId)}`,
    );
  } catch (error) {
    console.log(`::warning::Could not delete temporary Google Play edit: ${error.message}`);
  }
}

function normalizeRelease(release) {
  return {
    name: release.name ?? null,
    status: release.status ?? null,
    userFraction: release.userFraction ?? null,
    versionCodes: normalizeVersionCodes(release.versionCodes),
    releaseNotes: normalizeReleaseNotes(release.releaseNotes),
  };
}

function normalizeReleaseNotes(releaseNotes) {
  if (!Array.isArray(releaseNotes)) {
    return [];
  }
  return releaseNotes
    .map((releaseNote) => ({
      language: releaseNote.language ?? 'unknown',
      text: releaseNote.text ?? '',
    }))
    .filter((releaseNote) => releaseNote.text.trim() !== '')
    .sort((a, b) => a.language.localeCompare(b.language));
}

function compareReleases(left, right) {
  const leftCode = left.versionCodes[0] ?? '';
  const rightCode = right.versionCodes[0] ?? '';
  return compareVersionCode(leftCode, rightCode) || String(left.name).localeCompare(String(right.name));
}

function normalizeVersionCodes(versionCodes) {
  if (!Array.isArray(versionCodes)) {
    return [];
  }
  return [...new Set(versionCodes.map(String))].sort(compareVersionCode);
}

function compareVersionCode(left, right) {
  const leftNumber = Number(left);
  const rightNumber = Number(right);
  if (Number.isSafeInteger(leftNumber) && Number.isSafeInteger(rightNumber)) {
    return leftNumber - rightNumber;
  }
  return String(left).localeCompare(String(right));
}

async function googlePlayJson(accessToken, method, path) {
  const response = await fetch(`${GOOGLE_PLAY_API_BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
    },
  });
  const payload = await readResponseJson(response);
  if (!response.ok) {
    throw new GooglePlayError(`Google Play API request failed: ${method} ${path} (${response.status})`, response.status, payload);
  }
  return payload;
}

async function readResponseJson(response) {
  const text = await response.text();
  if (text.trim() === '') {
    return {};
  }
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

class GooglePlayError extends Error {
  constructor(message, status, payload) {
    super(message, { cause: JSON.stringify(payload) });
    this.name = 'GooglePlayError';
    this.status = status;
    this.payload = payload;
  }
}

function diffTrackVersionCodes(previousState, currentState) {
  const previousCodesByTrack = new Map((previousState?.tracks ?? []).map((track) => [track.track, collectVersionCodes(track)]));
  return currentState.tracks
    .map((track) => {
      const previousCodes = previousCodesByTrack.get(track.track) ?? [];
      const currentCodes = collectVersionCodes(track);
      const addedVersionCodes = currentCodes.filter((code) => !previousCodes.includes(code));
      return {
        track: track.track,
        addedVersionCodes,
        releases: track.releases.filter((release) =>
          release.versionCodes.some((code) => addedVersionCodes.includes(code)),
        ),
      };
    })
    .filter((change) => change.addedVersionCodes.length > 0);
}

function collectVersionCodes(track) {
  return normalizeVersionCodes(track.releases.flatMap((release) => release.versionCodes));
}

async function postSlackNotification(changes, currentState) {
  const webhookUrl = process.env.SLACK_WEBHOOK_URL;
  if (!webhookUrl || webhookUrl.trim() === '') {
    console.log('::warning::New Google Play version detected, but SLACK_WEBHOOK_URL is not configured.');
    return;
  }

  const runUrl = process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
    : null;
  const changeLines = changes.map(formatSlackChange).join('\n');
  const payload = {
    text: `Google Play 새 버전 감지: ${currentState.packageName}`,
    blocks: [
      {
        type: 'header',
        text: {
          type: 'plain_text',
          text: 'Google Play 새 버전 감지',
        },
      },
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Package*: \`${currentState.packageName}\`\n*Play Store*: ${getPlayStoreUrl(currentState.packageName)}\n${changeLines}`,
        },
      },
      {
        type: 'context',
        elements: [
          {
            type: 'mrkdwn',
            text: runUrl ? `<${runUrl}|GitHub Actions run>에서 감지됨` : 'GitHub Actions에서 감지됨',
          },
        ],
      },
    ],
  };

  const response = await fetch(webhookUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Slack webhook request failed: ${response.status}`, { cause: body });
  }
  console.log('Slack notification sent.');
}

function formatSlackChange(change) {
  const releaseDetails = change.releases.map(formatRelease).filter(Boolean).join(', ');
  const suffix = releaseDetails ? ` (${releaseDetails})` : '';
  return `*${change.track}*: versionCode ${change.addedVersionCodes.join(', ')}${suffix}`;
}

function formatRelease(release) {
  const parts = [release.name, release.status].filter(Boolean);
  return parts.join(' / ');
}

async function readJsonIfExists(path) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') {
      return null;
    }
    throw error;
  }
}

async function writeJson(path, value) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

async function writeStepSummary(previousState, currentState, changes, isFirstRun) {
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (!summaryPath) {
    return;
  }
  const releaseNoteLines = currentState.tracks.flatMap(formatTrackReleaseNotes);
  const reportedChanges = isFirstRun ? [] : changes;
  const lines = [
    '## Google Play Release Watcher',
    '',
    `Status: ${isFirstRun ? 'initial baseline saved' : 'checked'}`,
    `Package: \`${currentState.packageName}\``,
    `Play Store: [${currentState.packageName}](${getPlayStoreUrl(currentState.packageName)})`,
    `Observed at: \`${currentState.observedAt}\``,
    `Previous snapshot: ${previousState ? `\`${previousState.observedAt}\`` : 'none'}`,
    '',
    '### Tracks',
    '',
    ...currentState.tracks.map((track) => `- \`${track.track}\`: ${collectVersionCodes(track).join(', ') || 'no active version codes'}`),
    '',
    '### New version codes',
    '',
    ...(reportedChanges.length > 0
      ? reportedChanges.map((change) => `- \`${change.track}\`: ${change.addedVersionCodes.join(', ')}`)
      : ['- none']),
    '',
    '### Release Notes',
    '',
    ...(releaseNoteLines.length > 0 ? releaseNoteLines : ['- none']),
    '',
  ];
  await appendFile(summaryPath, `${lines.join('\n')}\n`);
}

function formatTrackReleaseNotes(track) {
  return track.releases.flatMap((release) => {
    const versionCodes = release.versionCodes.join(', ') || 'unknown';
    const releaseName = release.name ? ` / ${release.name}` : '';
    return release.releaseNotes.map((releaseNote) => (
      [
        `#### ${track.track} / versionCode ${versionCodes}${releaseName} / ${releaseNote.language}`,
        '',
        '```text',
        releaseNote.text.trim(),
        '```',
        '',
      ].join('\n')
    ));
  });
}

async function writeFailureStepSummary(error) {
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (!summaryPath) {
    return;
  }
  const lines = [
    '## Google Play Release Watcher',
    '',
    'Status: failed',
    `Package: \`${packageName}\``,
    `Play Store: [${packageName}](${getPlayStoreUrl(packageName)})`,
    `Configured tracks: ${tracks.map((track) => `\`${track}\``).join(', ')}`,
    '',
    '### Error',
    '',
    '```text',
    error.message,
    error.cause ? String(error.cause) : '',
    '```',
    '',
  ];
  await appendFile(summaryPath, `${lines.join('\n')}\n`);
}

function getPlayStoreUrl(targetPackageName) {
  return `https://play.google.com/store/apps/details?id=${encodeURIComponent(targetPackageName)}`;
}
