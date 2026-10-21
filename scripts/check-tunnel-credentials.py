#!/usr/bin/env python3
"""Run credential policy XCTest and production persistence against a fake-only vault.

Usage: SWIFTC=/path/to/swiftc python3 scripts/check-tunnel-credentials.py
This does not build the macOS UI or link Security/real SecretVault code. All test
credentials are synthetic. Temporary modules, executables and fixture defaults
are isolated and removed when the checks finish.
"""
from pathlib import Path
import os
import re
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SWIFTC = os.environ.get("SWIFTC") or shutil.which("swiftc")
if not SWIFTC:
    raise SystemExit("Swift compiler not found. Set SWIFTC to a supported Swift compiler path.")


def run(command, *, env=None):
    print("+ " + shlex.join(str(part) for part in command), flush=True)
    subprocess.run([str(part) for part in command], cwd=ROOT, env=env, check=True)


with tempfile.TemporaryDirectory(prefix="onemcp-credential-check-") as temporary:
    temp = Path(temporary)
    compiler = [SWIFTC, "-swift-version", "5", "-module-cache-path", temp / "modules"]
    production = [ROOT / "Sources/MCPHarbor/Models.swift",
                  ROOT / "Sources/MCPHarbor/TunnelCredentialReferencePolicy.swift"]
    tests = (ROOT / "Tests/MCPHarborTests/TunnelCredentialReferencePolicyTests.swift").read_text()
    tests = tests.replace("@testable import MCPHarbor\n", "")
    (temp / "PolicyTests.swift").write_text(tests)
    names = re.findall(r"func (test\w+)\(", tests)
    assert names, "No credential policy tests discovered"
    entries = ",\n".join(f'    ("{name}", TunnelCredentialReferencePolicyTests.{name})' for name in names)
    (temp / "main.swift").write_text("import XCTest\nXCTMain([testCase([\n" + entries + "\n])])\n")
    run(compiler + production + [temp / "PolicyTests.swift", temp / "main.swift", "-o", temp / "policy-tests"])
    run([temp / "policy-tests"])

    fixture = ROOT / "Tests/Fixtures/CredentialReferenceHarness.swift"
    run(compiler + production + [ROOT / "Sources/MCPHarbor/TunnelCredentialPersistence.swift", fixture,
                                "-o", temp / "persistence-fixture"])
    environment = os.environ.copy()
    environment["HOME"] = str(temp / "home")
    environment["XDG_CONFIG_HOME"] = str(temp / "config")
    (temp / "home").mkdir()
    (temp / "config").mkdir()
    run([temp / "persistence-fixture"], env=environment)
    print(f"PASS {len(names)} production-model policy XCTest cases and 1 fake-vault production-persistence integration harness.", flush=True)
    print("Not verified here: macOS SwiftUI rendering or real Keychain permissions. No remote Runtime API calls.", flush=True)
