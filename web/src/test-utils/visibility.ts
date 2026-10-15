// jsdom reports the tab as always visible. This lets tests hide and show it
// the way a browser does: change visibilityState, then fire visibilitychange.
export function setVisibility(state: DocumentVisibilityState) {
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => state,
  })
  Object.defineProperty(document, 'hidden', {
    configurable: true,
    get: () => state === 'hidden',
  })
  document.dispatchEvent(new Event('visibilitychange'))
}
