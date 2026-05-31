import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

try {
  // Read package.json version
  const packageJsonPath = path.join(__dirname, '../package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  const version = packageJson.version;

  if (!version) {
    throw new Error('Version in package.json not found.');
  }

  // Update Cargo.toml
  const cargoTomlPath = path.join(__dirname, '../src-tauri/Cargo.toml');
  let cargoToml = fs.readFileSync(cargoTomlPath, 'utf8');

  // Match version = "x.y.z" at the start of a line
  const versionRegex = /^version\s*=\s*"[^"]*"/m;
  if (!versionRegex.test(cargoToml)) {
    throw new Error('Could not find version entry in Cargo.toml');
  }

  cargoToml = cargoToml.replace(versionRegex, `version = "${version}"`);
  fs.writeFileSync(cargoTomlPath, cargoToml, 'utf8');

  console.log(`[sync-version] Cargo.toml successfully updated to version ${version}`);
} catch (error) {
  console.error('[sync-version] Error:', error.message);
  process.exit(1);
}
