import { z } from 'zod';
import { createScopedUsageSchemas } from './schema.mjs';
import { applyUsageEvent, createUsageState, usageView } from './accounting.mjs';

const schemas = createScopedUsageSchemas(z);

export const scopedUsageProjectionDefinition = {
  key: 'scopedUsage',
  stateVersion: 1,
  stateSchema: schemas.state,
  init: createUsageState,
  apply: applyUsageEvent,
  wire: { viewSchema: schemas.view, view: usageView },
};
