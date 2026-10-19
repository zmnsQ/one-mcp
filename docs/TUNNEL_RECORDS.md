# Tunnel records

The connection screen now lists independently named tunnel records. Add a record,
select one or more existing MCP services, then select OpenAI or Cloudflare and
configure that record. One service may belong to more than one record. Each record
has its own process, status, start/stop controls, and “start with all” preference.
The existing MCP tool allowlist still applies inside each binding.

## Saved configuration

`preferences.tunnelRecords` is an array of at most 32 records:

```json
{
  "id": "work-tools",
  "name": "Work tools",
  "serverIDs": ["search", "documents"],
  "transport": "openai",
  "profile": "onemcp-work-tools",
  "tunnelID": "tunnel_existing",
  "startWithAll": true
}
```

Optional `profileFile` selects an existing OpenAI profile. Cloudflare records use
`transport: "cloudflare"` and the existing `cloudflare` settings object inside the
record (executable, mode, tunnelID, credentialsFile, publicURL). Credentials stay
in the existing secure store or an explicitly selected credential file, never in
this array. A newly created record has no bindings and cannot expose any service
until at least one is selected. A missing/deleted service blocks startup.

Old aggregate/individual configurations are projected into explicit records in
memory. No file is written merely by launching the app. Saving writes the record
array; legacy fields remain for compatibility. An explicit empty array means no
tunnels and does not recreate legacy entries. Adding a new MCP does not expand
an already migrated record. Existing profile files and old Keychain entries are
not removed. OpenAI migrated records retain their old aggregate/server IDs.

## Runtime isolation

Each active record exposes only its selected service IDs at the private upstream
`/tunnels/RECORD_ID/mcp`. Record endpoints use stable namespaced tool aliases.
Empty, duplicate, unknown, or stopped record routes never fall back to `/mcp`.
Changing bindings requires stopping that record and starting it again. Stopping
a service withdraws the records bound to that service, leaving other records up.

Cloudflare gets a separate loopback proxy per record. It forwards only `/mcp`
and its OAuth resource metadata; root, `/servers/...`, arbitrary paths and
upgrade/CONNECT requests cannot escape into the main gateway. Each Cloudflare
record has its own OAuth audience derived from its public URL. Issuer, JWKS and
required scope remain the shared saved policy and require gateway restart to
change. Quick URLs remain temporary and their audience must be allowed at the
external authorization server. Duplicate named tunnel identities/credential
files are rejected while running.

## CLI

- `onemcp tunnels list`
- `onemcp tunnel doctor --id RECORD_ID` (preview; add `--apply` to execute)
- `onemcp tunnel start --id RECORD_ID --apply`
- `onemcp tunnel stop --id RECORD_ID --apply`
- `onemcp config set --field tunnelRecords --value JSON --expect-revision REV --apply`

Only existing authorized profiles, credentials and tunnels are used. These
commands do not create provider accounts, credentials, DNS routes or grants.

## Verification scope

Linux tests use loopback fixture MCP servers and mock tunnel processes. They
cover migration, explicit empty bindings, duplicate rejection, cross-record tool
isolation, independent stops, route invalidation, Cloudflare proxy path guards,
and mocked process failure/restart. Native SwiftUI compilation and genuine
provider/OAuth end-to-end calls require separate Mac/user acceptance testing.
