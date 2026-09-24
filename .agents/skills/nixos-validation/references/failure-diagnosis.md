# Diagnose a failed check

Start with the failing command and logs. Compare evaluations only when a
configuration-value change could explain the failure. Select the same small,
JSON-serializable attribute in the recorded commit and current checkout; never
serialize the entire configuration. For example,
`nixosConfigurations.citrus.config.services.openssh.settings` is suitable only
when that host and attribute explain the failure.

Set `repo` to the actual checkout's absolute path, `before` to the recorded
pre-edit commit, `attribute` to the selected attribute, and `comparison_dir` to a
fresh `mktemp -d` directory. Stage new files before evaluating a Git flake. If the
initial worktree was dirty, the commit does not reproduce uncommitted inputs.

Run each evaluation separately and inspect its exit status before continuing:

```sh
nix eval --json --no-write-lock-file "git+file://$repo?rev=$before#$attribute" \
  >"$comparison_dir/before.raw.json" 2>"$comparison_dir/before.stderr"
nix eval --json --no-write-lock-file "$repo#$attribute" \
  >"$comparison_dir/after.raw.json" 2>"$comparison_dir/after.stderr"
```

Only after both succeed, normalize object keys without changing values or array
order, then compare the complete normalized files:

```sh
jq -S . "$comparison_dir/before.raw.json" >"$comparison_dir/before.json" &&
  jq -S . "$comparison_dir/after.raw.json" >"$comparison_dir/after.json"
```

Only after normalization succeeds:

```sh
diff_status=0
diff -u --label before --label after "$comparison_dir/before.json" "$comparison_dir/after.json" \
  >"$comparison_dir/values.diff" || diff_status=$?
printf 'diff exit=%s\n' "$diff_status"
```

Diff status 0 means equal, 1 means different, and 2 or higher means a comparison
error. Report equality briefly. For differences, inspect relevant passages in
the saved diff. Bound displayed excerpts and errors to 8 KiB, announce truncation,
and narrow the attribute or search saved files for missing evidence. Long strings
can exceed a line-based limit.

Compare full values, not summaries or key-only JSON. Evaluation failures are not
empty values or equality; successful display filtering is not a successful source
command. Equal values do not prove a successful build or correct runtime behavior.

Rerun the failed check after repairs. Expand to extra hosts or
`nix flake check --no-write-lock-file` only when the investigation or request
justifies it. Remove only the temporary comparison directory created for this
check; do not add repository scripts, permanent suites, or comparison files.
