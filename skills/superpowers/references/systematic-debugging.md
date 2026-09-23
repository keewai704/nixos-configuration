# Systematic Debugging

Use evidence to locate the broken assumption before changing the implementation.

Record the failing operation, expected and actual behavior, environment, exit
status, and a bounded diagnostic excerpt. Reproduce the smallest useful case;
do not replay an operation whose side effects are uncertain.

Trace the failing value or event backward through callers. At component
boundaries, inspect what entered and what left. Use targeted temporary
instrumentation only when existing evidence is insufficient, keeping secrets
and unrelated user data out of logs.

Compare a working case and relevant recent changes. Form a falsifiable hypothesis
with supporting evidence, then run the smallest discriminating check. Avoid
stacking speculative fixes or treating correlation as a cause.

Repair the responsible boundary, add meaningful regression coverage where
appropriate, and rerun the original failing operation and affected checks.
For timing failures, wait for an observable condition with a bounded timeout,
not an arbitrary sleep. If hypotheses keep failing, gather new evidence and
reassess the model; do not force a redesign after a fixed number of attempts.
Distinguish pre-existing limitations, repaired regressions, and remaining unknowns.
