# Writing Plans

Use a plan when dependencies or coordination make direct implementation hard
to track. File count alone does not require one.

Inspect the implementation and callers. Record the goal, scope, constraints,
observable acceptance criteria, and any unresolved decision. For each cohesive
task, identify:

- The behavior and exact files or interfaces to change.
- Dependencies, inputs, ownership, and any isolation needed.
- The meaningful check and evidence that will establish completion.

Prefer existing APIs and conventions. Include code or commands where they remove
uncertainty, not a transcript of every keystroke. Separate independent work from
sequential dependencies and include required review and deployment gates.

Keep a short plan in session state. Write a plan file only when requested or
required, in an allowed location. For an implementation request, proceed in the
current session without forcing an execution-mode question. A plan-only request
ends with the plan.
