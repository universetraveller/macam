// SPDX-License-Identifier: GPL-3.0-only
// Pure JS regression tests with mocked media devices; no real browser or audio.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const profile = process.argv[2] || 'chromium';
assert.ok(['chromium', 'safari'].includes(profile));
const trackLabel = profile === 'safari' ? 'Macam Audio' : 'Macam Audio (Aggregate)';
const html = fs.readFileSync('Resources/ReceiverTest.html', 'utf8');
const script = html.split('<script>')[1].split('</script>')[0];
const nodes = new Map();
class Element {
  constructor(id = '') { this.id = id; this.children = []; this.dataset = {}; this.textContent = ''; }
  replaceChildren() { this.children = []; }
  append(child) { this.children.push(child); }
  get selectedOptions() { return this.children.filter(c => c.selected).length ? this.children.filter(c => c.selected) : this.children.slice(0, 1); }
  get value() { return this.id === 'devices' ? this.selectedOptions[0]?.value || '' : this._value; }
  set value(v) { this._value = v; }
}
const node = id => { if (!nodes.has(id)) nodes.set(id, new Element(id)); return nodes.get(id); };
let available = true, active = 0, defaultOpens = 0, frameRequests = 0;
let hiddenEnumeration = false, preferredMacam = false, omitIDs = false, exactOpens = 0;
let lastRecorder;
const tracks = [];
class Track {
  constructor(label) { this.label = label; this.enabled = true; this.readyState = 'live'; active++; tracks.push(this); }
  stop() { if (this.readyState === 'live') { active--; this.readyState = 'ended'; } }
  end() { this.stop(); this.onended?.(); }
  getSettings() { return { channelCount: 2, sampleRate: 48000, ...(!omitIDs ? {deviceId: this.label.startsWith('Macam Audio') ? 'macam' : 'physical'} : {}) }; }
}
class AudioContext {
  async resume() {}
  async close() {}
  createChannelSplitter() { return { connect() {} }; }
  createMediaStreamSource() { return { connect() {} }; }
  createAnalyser() { return { fftSize: 2048, getFloatTimeDomainData(a) { a.fill(0.1); } }; }
}
class MediaRecorder {
  static isTypeSupported(type) { return type === (profile === 'safari' ? 'audio/mp4' : 'audio/webm;codecs=opus'); }
  constructor(stream, options = {}) { this.state = 'inactive'; this.mimeType = options.mimeType; lastRecorder = this; }
  start() { this.state = 'recording'; }
  stop() {
    this.state = 'inactive';
    this.ondataavailable?.({data: new Blob(['mock'], {type: this.mimeType})});
    this.onstop?.();
  }
}
const document = { visibilityState: 'visible', getElementById: node, createElement: () => new Element() };
const context = vm.createContext({
  document, window: { addEventListener() {}, ...(profile === 'safari' ? {webkitAudioContext: AudioContext} : {AudioContext}) },
  isSecureContext: true, AudioContext, MediaRecorder,
  navigator: {
    userAgent: profile === 'safari' ? 'Mock Safari' : 'Mock Chromium',
    ...(profile === 'safari' ? {} : {permissions: { async query() { return { state: active ? 'granted' : 'prompt' }; } }}),
    mediaDevices: {
      addEventListener() {},
      async enumerateDevices() {
        if (hiddenEnumeration) return [{kind: 'audioinput', label: '', deviceId: ''}];
        // Temporary permission reveals devices only while a live track exists.
        return active && tracks.some(t => t.readyState === 'live' && t.enabled) ? [{ kind: 'audioinput', label: 'Built-in Microphone', deviceId: 'physical' },
          ...(available ? [{ kind: 'audioinput', label: 'Macam Audio', deviceId: 'macam' }] : [])] : [];
      },
      async getUserMedia(c) {
        const id = c.audio?.deviceId?.exact;
        if (id && (id !== 'macam' || !available)) { const e = new Error('Device absent'); e.name = 'NotFoundError'; throw e; }
        if (!id) defaultOpens++;
        else exactOpens++;
        const track = new Track(id || preferredMacam ? trackLabel : 'Built-in Microphone');
        return { getTracks: () => [track], getAudioTracks: () => [track] };
      }
    }
  },
  performance: { now: () => 100 }, requestAnimationFrame: () => ++frameRequests,
  cancelAnimationFrame() {}, setTimeout: () => 1, clearTimeout() {},
  setInterval: () => 1, clearInterval() {}, Blob, URL, console
});
const settle = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  vm.runInContext(script, context); await settle();
  node('route').value = profile === 'safari' ? 'safari-safari' : 'chrome-chrome';
  assert.match(node('devices').selectedOptions[0].textContent, /no audio inputs/);
  await node('permission').onclick();
  assert.equal(active, 1, 'Permission track must remain live while enumerating temporary device access');
  assert.equal(tracks[0].enabled, true, 'Chrome must still consider the permission track actively capturing to reveal device identities');
  assert.equal(node('devices').selectedOptions[0].textContent, 'Macam Audio');
  await node('connect').onclick();
  assert.equal(defaultOpens, 1);
  assert.equal(active, 1, 'Only the explicit Macam track remains after switching');
  assert.equal(tracks[0].readyState, 'ended');
  assert.match(node('status').textContent, /"nonSilentInputVerified": true/);
  if (profile === 'safari') assert.equal(JSON.parse(node('devicesStatus').textContent).microphonePermission, 'unavailable');
  node('record').onclick();
  assert.equal(lastRecorder.mimeType, profile === 'safari' ? 'audio/mp4' : 'audio/webm;codecs=opus');
  lastRecorder.stop();
  assert.match(node('download').download, profile === 'safari' ? /\.m4a$/ : /\.webm$/);
  available = false; tracks.at(-1).end();
  await vm.runInContext('refreshAndReconnect()', context);
  assert.equal(active, 0);
  available = true;
  await vm.runInContext('refreshAndReconnect()', context);
  assert.equal(active, 1, 'Returning Macam device should reopen specifically by its cached ID');
  assert.equal(defaultOpens, 1, 'Reconnect must never fall back to the physical/default input');
  node('stop').onclick(); await settle();
  assert.equal(active, 0);
  await vm.runInContext('refreshAndReconnect()', context);
  assert.equal(active, 0, 'Stop must cancel automatic reconnection');
  // Regression for the user's actual report: live qualified Macam track, but
  // enumeration exposes one anonymous placeholder and no device ID.
  hiddenEnumeration = true; preferredMacam = true; omitIDs = true;
  await node('permission').onclick();
  assert.equal(node('devices').selectedOptions[0].textContent, trackLabel);
  const exactBefore = exactOpens;
  await node('connect').onclick();
  assert.equal(exactOpens, exactBefore, 'Reuse the verified authorized track when Chrome withholds IDs');
  assert.equal(active, 1);
  assert.equal(JSON.parse(node('status').textContent).device, trackLabel);
  assert.match(node('status').textContent, /"nonSilentInputVerified": true/);
  node('stop').onclick(); await settle();
  assert.equal(active, 0);
  preferredMacam = false;
  await node('permission').onclick();
  await node('connect').onclick();
  assert.match(node('status').textContent, /Grant audio-input access/);
  assert.equal(tracks.at(-1).label, 'Built-in Microphone', 'An unrelated permission track must not be adopted as Macam');
  node('stop').onclick(); await settle();
  assert.equal(active, 0);
  for (const route of ['chrome-chrome', 'safari-safari', 'chrome-safari', 'safari-chrome']) {
    assert.ok(html.includes(`value="${route}"`), `Missing ${route} route in neutral receiver`);
  }
  assert.ok(!html.includes('context.createMediaStreamSource(next).connect(context.destination)'), 'Receiver must not monitor its input');
  console.log(`${profile} browser-page mocks passed (permissions, qualified names, hidden IDs, exact input, reconnect, recording format, Stop). Not a real-browser test.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
