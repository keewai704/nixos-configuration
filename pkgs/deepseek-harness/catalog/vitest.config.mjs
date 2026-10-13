import tsconfigPaths from 'vite-tsconfig-paths';

export default {
  plugins: [tsconfigPaths({ projects: ['./tsconfig.base.json'] })],
  test: { include: ['scripts/gen-config-catalog.spec.ts'], maxWorkers: 1 },
};
