export const ready = (async () => {
  if (!('serviceWorker' in navigator)) {
    throw new Error('OpenPencil requires service workers for subpath hosting.');
  }
  await navigator.serviceWorker.register('/openpencil/service-worker.js', {
    scope: '/openpencil/',
    updateViaCache: 'none',
  });
  await navigator.serviceWorker.ready;
  if (!navigator.serviceWorker.controller?.scriptURL.endsWith('/openpencil/service-worker.js')) {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('OpenPencil routing did not start. Reload this page.')), 15000);
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        clearTimeout(timeout);
        resolve();
      }, { once: true });
    });
  }
})();
