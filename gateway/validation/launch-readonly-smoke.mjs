// Source-contract checks only: Swift/macOS runtime is not executed here.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const source = fs.readFileSync('../Sources/MCPHarbor/HarborStore.swift', 'utf8');
const init = source.slice(source.indexOf('    init(configurationFileURL:'), source.indexOf('    @discardableResult func save()'));
assert.match(init, /loadInitialConfiguration\(\)/);
assert.doesNotMatch(init, /acquireConfigurationLease|releaseConfigurationLease|save\(\)|createDirectory/);
const cooperation = fs.readFileSync('../Sources/MCPHarbor/ConfigurationCooperation.swift', 'utf8');
const load = cooperation.slice(cooperation.indexOf('    func loadInitialConfiguration'), cooperation.indexOf('    func revision('));
assert.doesNotMatch(load, /acquireConfigurationLease|\.write\(|removeItem|createDirectory/);
assert.match(load, /indexData == \(try bytes\(indexURL\)\), configData == \(try bytes\(configURL\)\)/);
assert.match(load, /savedRevision = configData.map/);
assert.match(cooperation, /guard initialReadAttempts < 5/);
assert.match(cooperation, /guard !hasUnsavedChanges/);
assert.match(source, /guard initialConfigurationLoaded else/);
console.log('PASS readonly-launch source contracts (Swift runtime not executed)');
assert.match(load, /validatePreferences\(loaded, requireInstalled: false\)/);
