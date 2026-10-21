# CLI services

One MCP can wrap an explicitly configured command-line program as an MCP tool service. In the service editor select **CLI**, set an absolute executable path, fixed argument lines, and an optional absolute working directory. Add named tools and their parameter definitions, then enable only the tools you intend to expose. Saving a draft does not execute a command or start a tunnel.

CLI services start excluded from “start all”, with no tools and an empty allowlist. A draft with no tools can be saved but cannot start. The updated app refuses to start a CLI through an older gateway without the CLI capability marker. Restart the gateway explicitly after updating binaries.

## Parameters and limits

- Each service wraps one fixed executable and argument prefix. Put a subcommand in the fixed prefix; use separate services for different fixed subcommands.
- Parameter names map in the configured order to positional values or long options such as `--format`. Supported types: string, finite number, boolean. A boolean needs an option and emits it only when true. String choices can restrict allowed values.
- Dynamic values beginning with `-` are rejected to prevent them becoming additional option switches; this first version therefore does not support negative numeric values. Unknown parameters, wrong types, missing required values and invalid choices are rejected at runtime.
- No shell command-string parsing, no arbitrary `args` escape hatch, no runtime package download and no implicit fallback executable.
- Defaults: 30-second timeout, 64 KiB combined output, one concurrent call. Configurable bounds: 100–120000 ms, 1024–1048576 bytes, 1–4 calls.
- Standard input is closed. Interactive/password-prompting CLIs are not supported.
- Child output is captured separately from MCP protocol stdout. Responses are JSON text containing `stdout`, `stderr`, `exitCode`, and `truncated`; nonzero exit or truncated output is a tool error. A raw output overflow terminates the process and omits captured output to avoid returning a partially cut secret. Encoded output remains bounded after redaction and JSON escaping.
- Timeout, cancellation and stop clean up the process group on the supported macOS/POSIX host. Windows process-tree behavior is not an acceptance target for this native Mac app.

## Permissions and credentials

This is **not a sandbox**. The selected binary still has the current OS account's access, and program-specific flags or inputs can perform file, network or other consequential operations. Expose narrow, understood functions. No-shell invocation does not make a dangerous CLI harmless.

Only explicitly configured session environment keys plus the fixed locale reach the wrapped child; the gateway's ambient environment is not passed wholesale. Supply PATH or HOME explicitly only if the tool needs them. `ONEMCP_` keys are reserved. Do not place secrets in fixed arguments, tool descriptions or choices. Existing session credential UI and explicit Keychain workflow remain unchanged. Known session values and common credential patterns are redacted from returned output, but arbitrary application output cannot be guaranteed free of sensitive data.

The existing gateway allowlist, local/aggregate routes, authentication and independently selected tunnel bindings still apply. Adding a CLI does not automatically publish it through a tunnel.

## Deliberately limited first version

Schemas are manual. Opening, editing or previewing does not run `--help`. Automatic help parsing is not claimed: arbitrary CLI help text cannot reliably prove parameter semantics or permission safety. The architecture was researched against [RonieNeubauer/cli2mcp](https://github.com/RonieNeubauer/cli2mcp) (MIT, early 0.1 release); One MCP's bounded executor and explicit configuration are original implementations, not a runtime dependency on that package.

## Validation

Run `cd gateway && npm run build && node validation/cli-service-smoke.mjs`. The fixture covers descriptor/runtime validation, literal argv, environment isolation/redaction, encoded output limits, timeout, cancellation, concurrency, descendant cleanup, legacy configuration, draft handling, fingerprints, actual MCP stdio, and actual gateway tool routing. Fixtures execute only test-owned harmless Node programs, not user tools or public tunnels.

Native SwiftUI/AppKit compilation and real Mac visual/interaction acceptance still require a supported macOS/Xcode host; Linux syntax parsing and Foundation model checks are not substitutes.
