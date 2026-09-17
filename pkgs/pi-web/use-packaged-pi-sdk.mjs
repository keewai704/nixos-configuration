import { readFileSync, writeFileSync } from "node:fs";

const packageName = "@earendil-works/pi-coding-agent";
const dependencyPath = `node_modules/${packageName}`;

for (const path of ["package.json", "package-lock.json"]) {
	const manifest = JSON.parse(readFileSync(path, "utf8"));
	if (manifest.dependencies) delete manifest.dependencies[packageName];
	if (manifest.packages) {
		delete manifest.packages[""].dependencies[packageName];
		for (const name of Object.keys(manifest.packages)) {
			if (name === dependencyPath || name.startsWith(`${dependencyPath}/`)) {
				delete manifest.packages[name];
			}
		}
	}
	writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
}
