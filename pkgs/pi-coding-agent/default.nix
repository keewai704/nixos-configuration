{
  pi-coding-agent,
  fetchFromGitHub,
  fetchNpmDeps,
  fetchurl,
}:
pi-coding-agent.overrideAttrs (
  final: old: {
    version = "0.87.0";
    src = fetchFromGitHub {
      owner = "earendil-works";
      repo = "pi";
      tag = "v${final.version}";
      hash = "sha256-7YkIA5IEs4U0qnoaO3IzlY+p/M7j30fSVelLeyoV+F8=";
    };
    npmDepsHash = "sha256-fbxwpQHnrUihO9MU72m331Uwt9dv0fQtEjdJ9hU8UxA=";
    npmDeps = fetchNpmDeps {
      name = "pi-coding-agent-${final.version}-npm-deps";
      inherit (final) src;
      hash = final.npmDepsHash;
    };
    modelData = fetchurl {
      url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${final.version}.tgz";
      hash = "sha256-8q353oCdA192+NrfPRSHIOvu9GBqhIqzbug02JWugS8=";
    };
    patches = (old.patches or [ ]) ++ [ ./cache-affinity-header.patch ];
  }
)
