// SPDX-License-Identifier: GPL-3.0-only
// Test graph topology/lifecycle with mocks; this does not verify audible playback.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const nodes = Object.fromEntries(['play', 'stop', 'status'].map(id => [id, {}]));
let contexts = [], gains = [], oscillators = [], timer;
class AudioContext {
  constructor() { this.destination = {}; contexts.push(this); }
  async resume() {}
  async close() { this.closed = true; }
  createChannelMerger(channels) { assert.equal(channels, 2); return {connect: output => assert.equal(output, this.destination)}; }
  createOscillator() {
    const oscillator = {frequency: {}, connect() {}, start() { this.started = true; }, stop() { this.stopped = true; }};
    oscillators.push(oscillator); return oscillator;
  }
  createGain() { const gain = {gain: {}, connect() {}}; gains.push(gain); return gain; }
}
const html = fs.readFileSync('Resources/ToneSource.html', 'utf8');
const context = vm.createContext({
  window: {AudioContext, addEventListener() {}},
  document: {getElementById: id => nodes[id]},
  setTimeout(callback, delay) { assert.equal(delay, 120000); timer = callback; return 1; },
  clearTimeout() {}
});
(async () => {
  vm.runInContext(html.split('<script>')[1].split('</script>')[0], context);
  assert.equal(contexts.length, 0, 'Opening the source must remain silent until Play');
  await nodes.play.onclick();
  assert.deepEqual(oscillators.map(o => o.frequency.value), [440, 660]);
  assert.ok(oscillators.every(o => o.started));
  assert.ok(gains.every(g => g.gain.value === 0.035));
  nodes.stop.onclick();
  assert.ok(oscillators.every(o => o.stopped));
  assert.ok(contexts[0].closed);
  await nodes.play.onclick(); timer();
  assert.ok(contexts[1].closed, 'Automatic stop must release the output context');
  console.log('Tone-source graph/lifecycle mocks passed. Not an audible playback test.');
})().catch(error => { console.error(error); process.exitCode = 1; });
