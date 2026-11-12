'use strict';
const output = new URLSearchParams(location.search).get('output') || '1';
const ids = output === 'usb' ? ['usb', 'visitor'] : ['esp32', 'pi', 'visitor'];
for (const id of ['pi', 'esp32', 'usb', 'visitor']) {
  if (!ids.includes(id)) document.getElementById(id).remove();
}
const feeds = ids.map(id => ({
  id, element: document.getElementById(id), seen: -Infinity, liveSince: null, live: false,
  loadedAt: performance.now(),
}));
let selected = 'visitor';
function chooseFeed(now) {
  // Require a stable ten seconds before leaving the offline presentation.
  const candidate = feeds.find(feed => feed.id !== 'visitor' && feed.live &&
    now - feed.seen < 6000 && feed.liveSince !== null && now - feed.liveSince >= 10000);
  return candidate ? candidate.id : 'visitor';
}
function refreshLayout() {
  const now = performance.now();
  for (const feed of feeds) {
    if (now - feed.seen >= 6000) { feed.live = false; feed.liveSince = null; }
    if (now - feed.seen >= 20000 && now - feed.loadedAt >= 60000) {
      console.warn('Reloading unresponsive kiosk frame', feed.id);
      const frame = feed.element.querySelector('iframe');
      frame.src = frame.src;
      feed.loadedAt = now;
    }
  }
  selected = chooseFeed(now);
  for (const feed of feeds) feed.element.hidden = feed.id !== selected;
}
window.addEventListener('message', event => {
  if (event.origin !== location.origin || event.data?.type !== 'traincam-viewer-heartbeat') return;
  const feed = feeds.find(feed => feed.element.querySelector('iframe').contentWindow === event.source);
  if (!feed) return;
  const now = performance.now();
  if (event.data.live === true) {
    if (!feed.live || now - feed.seen >= 6000) feed.liveSince = now;
    feed.live = true;
  } else {
    feed.live = false;
    feed.liveSince = null;
  }
  feed.seen = now;
  refreshLayout();
});
refreshLayout();
// Assign URLs only after screen selection so discarded viewers never connect.
for (const feed of feeds) {
  const frame = feed.element.querySelector('iframe');
  frame.src = frame.dataset.src;
}
setInterval(refreshLayout, 1000);
setInterval(() => {
  const feed = feeds.find(feed => feed.id === selected);
  if (performance.now() - feed.seen >= 6000) return;
  fetch('/_kiosk/heartbeat/' + output, {
    method: 'POST', cache: 'no-store', signal: AbortSignal.timeout(3000),
  }).catch(error => console.warn('Kiosk heartbeat failed', error));
}, 5000);
