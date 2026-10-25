# Personal coding preferences

Apply these defaults across projects. Explicit task instructions and repository
guidance, including AGENTS.md, take precedence over these preferences. Use each
project's conventions, runtime, scripts, and authorization rules.

## Implementation

- Read the affected implementation and its callers before making changes. Keep
  the solution focused on the requested behavior and preserve unrelated work.
- Choose straightforward code. Add abstractions, dependencies, and defensive
  machinery only for concrete requirements or demonstrated failure modes.
- Keep cohesive logic together. Extract a helper when it earns its name through
  reuse or by clarifying a complex boundary; place it near the code it supports.
- Check untrusted input at its entry point, then carry validated types inward.
  Trust established internal guarantees instead of repeatedly checking them.
- Make the successful path easy to follow. Use guard clauses to flatten branches
  and handle errors where recovery or useful context is possible. Avoid broad
  catch blocks that conceal failures.
- Favor immutable bindings and direct expressions when they improve readability.
  Inline trivial temporary values without making expressions hard to understand.
- Use clear names and direct property access. Avoid gratuitous destructuring,
  import renaming, and namespace imports; respect necessary framework patterns.
- In TypeScript, let inference handle obvious types and use unknown for values
  awaiting validation. Specify types for public contracts or meaningful clarity.
- Preserve module ownership and dependency direction. Load expensive optional
  dependencies only in paths that need them when startup cost matters.
- For interfaces, choose design tokens by meaning. Introduce a missing semantic
  role rather than borrowing an unrelated color or state token.

## Validation and delivery

- Run the project's documented generators when source contracts change. Keep
  generated outputs consistent with their inputs.
- Check behavior through production code and realistic boundaries. Minimize
  mocking and avoid tests that merely repeat implementation logic.
- Use the relevant package's documented checks and working directory. Verify
  affected themes, fallback behavior, and meaningful interface states when relevant.
- Follow repository branch and commit conventions. When none exist, prefer short
  hyphenated branch names and conventional commit subjects.
- Report the result, checks performed, and remaining blockers precisely. Separate
  verified behavior from assumptions.

## Communication

Respond in concise, natural Japanese unless the user requests another language.
Keep code, commands, identifiers, and persistent agent instructions in their
appropriate original language.
