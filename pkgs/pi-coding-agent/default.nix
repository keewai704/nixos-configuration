{
  pi-coding-agent,
  fetchFromGitHub,
  fetchNpmDeps,
  fetchurl,
}:
pi-coding-agent.overrideAttrs (
  final: old: {
    version = "0.87.1";
    src = fetchFromGitHub {
      owner = "earendil-works";
      repo = "pi";
      tag = "v${final.version}";
      hash = "sha256-GUhlq6t+l6iiViOZ0bkV28v3ZDqcLvEwpZpYZ5JAyDk=";
    };
    npmDepsHash = "sha256-JBIYoP2vvRNz1HONNvDJ1U3c+nmCJ7/VgNthRTkrkIA=";
    npmDeps = fetchNpmDeps {
      name = "pi-coding-agent-${final.version}-npm-deps";
      inherit (final) src;
      hash = final.npmDepsHash;
    };
    modelData = fetchurl {
      url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${final.version}.tgz";
      hash = "sha256-NbRDLyfMJmX4a+67mvajmxJRlwiDwwRL2L5PToxzHKA=";
    };
    patches = (old.patches or [ ]) ++ [ ./cache-affinity-header.patch ];
  }
)
