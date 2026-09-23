# Test-Driven Development

Use a regression test when changing executable behavior that can be exercised
meaningfully in the project's test environment.

Write the smallest test for the desired behavior and confirm it fails for the
missing behavior, not a broken fixture or unavailable dependency. Implement the
simplest change that satisfies it, run the focused and affected checks, then
refactor where needed while keeping behavior covered.

Test observable contracts and relevant failure paths. Mock external boundaries
for determinism without replacing the behavior under test. Avoid tests coupled
to private structure or production APIs added only to satisfy a mock.

For declarative configuration, prose, generated artifacts, or environment-bound
behavior, use an appropriate parser, loader, build, or runtime check instead of
tests that repeat constants. Explain a genuine coverage limit. If code already
exists, preserve it and add coverage; never delete work to recreate a red phase.
Distinguish a witnessed red-green cycle from tests added afterward.

Reuse passing results with unchanged relevant inputs. Do not impose a fixed test
count, a new framework, or paid model calls without a concrete need.
