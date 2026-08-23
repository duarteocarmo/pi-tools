import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const dryRun = process.argv.includes("--dry-run");
const requestedPackages = process.argv.slice(2).filter((argument) => argument !== "--dry-run");
const packagesDirectory = fileURLToPath(new URL("../packages/", import.meta.url));

function publishedVersionFor({ name }) {
	try {
		return execFileSync("npm", ["view", name, "version"], {
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		}).trim();
	} catch {
		return undefined;
	}
}

function nextVersion({ current, initial }) {
	if (!current) return initial;
	const match = current.match(/^(\d+)\.(\d+)\.(\d+)$/);
	if (!match) throw new Error(`Cannot increment published version: ${current}`);
	return `${match[1]}.${match[2]}.${Number(match[3]) + 1}`;
}

const availablePackages = readdirSync(packagesDirectory, { withFileTypes: true })
	.filter((entry) => entry.isDirectory())
	.map((entry) => entry.name)
	.filter((directory) => existsSync(join(packagesDirectory, directory, "package.json")))
	.sort();
const packageDirectories = requestedPackages.length > 0 ? requestedPackages : availablePackages;

for (const directory of packageDirectories) {
	if (!availablePackages.includes(directory)) throw new Error(`Unknown package directory: ${directory}`);
	const packagePath = join(packagesDirectory, directory, "package.json");
	const packageJson = JSON.parse(readFileSync(packagePath, "utf8"));
	const publishedVersion = publishedVersionFor({ name: packageJson.name });
	const version = nextVersion({ current: publishedVersion, initial: packageJson.version });
	console.log(`${packageJson.name}: ${publishedVersion ?? "unpublished"} → ${version}`);
	if (!dryRun) writeFileSync(packagePath, `${JSON.stringify({ ...packageJson, version }, null, 2)}\n`);
}
