---
name: systematic-debugging
description: Use when investigating a bug, failed command or test, flaky behavior, performance regression, or an unexpected result before proposing repairs.
license: MIT
---

# Systematic Debugging

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Understand the failure before changing the implementation.

## Establish evidence

Record the failing operation, expected and actual behavior, environment, exit
status, and a bounded diagnostic excerpt. Preserve the original log and source
coordinates. Reproduce with the smallest reliable case when useful; do not
replay operations with uncertain side effects. Follow configured log-triage
guidance without sending private data to an external service.

Trace the failing value or event backward through callers to the first broken
assumption. At component boundaries, inspect what entered and what left. Add
temporary targeted instrumentation only when current evidence is insufficient;
avoid broad logs containing secrets or user data.

## Compare and hypothesize

Find a working case or nearby implementation and list relevant differences.
Check required dependencies and recent changes. Form one falsifiable hypothesis
with supporting evidence, then choose the smallest discriminating check.
Do not stack speculative fixes or mistake correlation for root cause.

## Repair and verify

Fix the defect at its responsible boundary. Add a meaningful regression check
using [test-driven-development](../test-driven-development/SKILL.md) where
appropriate, then rerun the original failing operation and affected checks.
Protect other boundaries only when evidence shows an independent validation need.

For timing failures, wait for an observable condition with a bounded timeout
instead of adding arbitrary sleeps or weakening assertions. If hypotheses keep
failing, reassess the model and gather new evidence rather than retrying the
same operation. Escalate a concrete architectural decision when necessary;
do not force a redesign after an arbitrary number of attempts. Separate
pre-existing failures, repaired regressions, and remaining uncertainty.
