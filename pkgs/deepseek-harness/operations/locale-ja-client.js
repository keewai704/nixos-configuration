export function createJapaneseLocalePlugin(dictionaries) {
  const entries = Object.entries(dictionaries);
  if (entries.some(([namespace]) => namespace === 'common' || namespace === 'operations')) {
    throw new Error('The Japanese feature pack must not own common or operations');
  }
  return {
    name: 'locale-ja-client',
    inject: ['locale'],
    apply(ctx) {
      ctx.effect(() => {
        const disposers = [];
        const dispose = () => {
          for (const release of disposers.splice(0).reverse()) release();
        };
        try {
          for (const [namespace, dictionary] of entries) {
            disposers.push(ctx.locale.register(namespace, 'ja', dictionary));
          }
        } catch (error) {
          dispose();
          throw error;
        }
        return dispose;
      });
    },
  };
}
