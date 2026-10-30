import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { runInNewContext } from "node:vm";

async function findClients(directory) {
  const clients = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && entry.name !== "node_modules") {
      clients.push(...(await findClients(path.join(directory, entry.name))));
    } else if (entry.name === "manifest.webmanifest") {
      const manifest = await fs.readFile(path.join(directory, entry.name), "utf8");
      if (manifest.includes("T3 Code")) clients.push(directory);
    }
  }
  return clients;
}

const clients = await findClients(process.argv[2]);
assert.equal(clients.length, 1, "Expected one bundled T3 web client");
const directory = path.join(clients[0], "assets");
const bundles = await Promise.all(
  (await fs.readdir(directory))
    .filter((name) => name.endsWith(".js"))
    .map((name) => fs.readFile(path.join(directory, name), "utf8")),
);
const callbacks = bundles.flatMap((source) => {
  const matches = [
    ...source.matchAll(
      /(?<callbackName>[A-Za-z_$][\w$]*)=(?<callback>\(\)=>\{(?<router>[A-Za-z_$][\w$]*)\.history\.replace\((?:`[^`]*`|"[^"]*"|'[^']*')\),\k<router>\.history\.flush\(\),window\.location\.reload\(\)\})/g,
    ),
  ];
  for (const match of matches) {
    assert.equal(source.match(/onAuthenticated:([\w$]+)[,}]/)?.[1], match.groups.callbackName);
  }
  return matches;
});
assert.equal(callbacks.length, 1, "Expected one pairing success callback");
const historySections = bundles.flatMap((source) => {
  const start = /var [\w$]+=[`"']__TSR_index[`"'],/.exec(source);
  if (!start) return [];
  const ending = /function [\w$]+\(\)\{return\(Math.random\(\)\+1\)\.toString\(36\)\.substring\(7\)\}/.exec(
    source.slice(start.index),
  );
  assert.ok(ending, "Bundled history implementation changed");
  return [source.slice(start.index, start.index + ending.index + ending[0].length)];
});
assert.equal(historySections.length, 1, "Expected one bundled browser history implementation");
const factory = /function ([\w$]+)\([\w$]+\)\{let [\w$]+=[\w$]+\?\.window\?\?\(typeof document/.exec(
  historySections[0],
);
assert.ok(factory, "Bundled browser history factory changed");

const origin = "https://pairing.example";
for (const suffix of ["#synthetic-token", "?source=fixture#synthetic-token", ""]) {
  let url = new URL(`${origin}/t3/pair${suffix}`);
  let reloaded;
  const window = {
    get location() {
      return {
        pathname: url.pathname,
        search: url.search,
        hash: url.hash,
        reload: () => {
          reloaded = url.href;
        },
      };
    },
    history: {
      length: 1,
      state: { __TSR_index: 0, key: "fixture", __TSR_key: "fixture" },
      pushState(state, title, href) {
        this.state = state;
        if (href !== undefined) url = new URL(href, url);
      },
      replaceState(state, title, href) {
        this.state = state;
        if (href !== undefined) url = new URL(href, url);
      },
    },
    addEventListener() {},
    removeEventListener() {},
  };
  const history = runInNewContext(`${historySections[0]}; ${factory[1]}({window})`, { window });
  const authenticated = runInNewContext(`(${callbacks[0].groups.callback})`, {
    window,
    [callbacks[0].groups.router]: { history },
  });
  authenticated();
  await Promise.resolve();
  assert.equal(reloaded, `${origin}/t3/`);
  history.destroy();
}
console.log("Bundled pairing callback and browser history preserve /t3/ after authentication (3 cases)");
