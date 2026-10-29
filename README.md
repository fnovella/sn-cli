# sn-cli — Standalone ServiceNow CLI

A fast, zero-dependency command-line interface (`sn`) for querying, inspecting, and commenting on ServiceNow tickets directly from the terminal. Built using only the Python 3 standard library.

---

## Features

- **Zero External Dependencies**: Uses Python 3 standard library only (`urllib`, `argparse`, `json`, `csv`). No `pip install` or virtual environment required.
- **Smart Table Detection**: Automatically maps ticket prefixes (`INC`, `RITM`, `REQ`, `SCTASK`, `CHG`, `CTASK`, `PRB`, `PTASK`, `KB`, `TASK`) to their corresponding ServiceNow tables.
- **Multiple Authentication Modes**:
  - `basic`: Standard username & password.
  - `token`: OAuth 2.0 / Bearer Personal Access Token.
  - `cookie`: Browser session cookie + `X-UserToken` (ideal for enterprise SSO/SAML environments where Basic Auth is disabled).
- **Multi-Profile & Env Var Support**: Manage multiple ServiceNow instances (`prod`, `dev`, `test`) with `-p <profile>` or environment variables.
- **Flexible Output Formats**: Human-readable colorized terminal tables (`table`), `json`, `csv`, and `tsv` for piping into `jq`, `awk`, or spreadsheets.

---

## Installation

Clone the repository and symlink `sn` into your `~/.local/bin` (or any directory in your `$PATH`):

```bash
git clone https://github.com/fnovella/sn-cli.git ~/Work/sn-cli
chmod +x ~/Work/sn-cli/sn
ln -sf ~/Work/sn-cli/sn ~/.local/bin/sn
```

Verify installation:

```bash
sn --help
```

---

## Configuration & Authentication

### Interactive Setup

Run `sn config` to set up your default profile:

```bash
sn config
```

Credentials are saved in `~/.config/servicenow/config.json` with `0600` (owner-only read/write) permissions.

To configure additional profiles (e.g., a development or staging instance):

```bash
sn -p dev config
sn -p dev list --mine
```

### Authentication Modes

1. **`basic` (Username & Password)**
   Uses HTTP Basic Authentication against the ServiceNow REST API.
2. **`token` (OAuth / Bearer Token)**
   Sends `Authorization: Bearer <token>`.
3. **`cookie` (Enterprise SSO / Browser Session)**
   If your organization enforces SAML/Entra ID SSO and blocks basic authentication:
   - Open your ServiceNow instance in your browser and open DevTools (`F12` -> **Network** tab).
   - Click any `/api/now/...` request and copy the `Cookie` request header (and `X-UserToken` header if present).
   - Select `cookie` during `sn config` and paste the values.

### Environment Variables

You can override any profile setting using environment variables:

| Variable | Description |
| :--- | :--- |
| `SN_INSTANCE` | Instance name (`mycompany`) or full URL (`https://mycompany.service-now.com`) |
| `SN_USER` | ServiceNow username |
| `SN_PASS` | ServiceNow password (sets `basic` auth) |
| `SN_TOKEN` | Bearer token (sets `token` auth) |
| `NO_COLOR` | Set to `1` to disable ANSI terminal colors |

---

## Usage & Examples

### 1. View Ticket Details (`sn get`)

Automatically detects the table from the ticket prefix (`INC`, `RITM`, `REQ`, `SCTASK`, `CHG`, `PRB`, `TASK`) or looks up by `sys_id`:

```bash
# View ticket summary and description
sn get INC0010001

# Include full comment and work note history
sn get INC0010001 --comments

# Inspect a Requested Item (RITM) or Change Request (CHG)
sn get RITM0023456 -c
sn get CHG0034567

# Output full raw JSON record from ServiceNow
sn get INC0010001 --json
```

### 2. Query and List Tickets (`sn list` / `sn query` / `sn ls`)

By default, `sn list` queries active tickets across the base `task` table (which includes Incidents, RITMs, Catalog Tasks, Changes, and Problems) sorted by most recently updated.

```bash
# Active tickets assigned to you
sn list --mine

# Active P1 incidents
sn list -t incident --priority 1

# Tickets assigned to a specific group containing "vpn" in description
sn list --group "Service Desk" --search "vpn"

# Include closed/inactive tickets reported by a specific user
sn list --caller "john.doe" --all

# Custom fields and row limit
sn list -t incident -f "number,state,priority,caller_id,short_description" -l 50
```

#### Exporting to JSON, CSV, or TSV

```bash
# Export to CSV file
sn list --group "Network" -o csv > network_tickets.csv

# Pipe JSON output to jq
sn list --mine -o json | jq '.[] | {number: .number, state: .state}'
```

#### Using Raw ServiceNow Queries (`-q` / `--query`)

You can pass any native ServiceNow encoded query (`sysparm_query`):

```bash
sn list -t incident -q "active=true^priority<=2^assigned_toISEMPTY"
```

> **Tip:** Build any complex filter in the ServiceNow web UI list view, right-click the last condition in the breadcrumb trail, and click **"Copy query"** to paste directly into `-q`.

### 3. Add Comments or Work Notes (`sn comment`)

```bash
# Add a customer-visible comment
sn comment INC0010001 "We have identified the issue and are applying a fix."

# Add an internal work note (--work-note / -w)
sn comment INC0010001 "Restarted backend worker on node-03." --work-note
```

---

## Reference: Common ServiceNow Tables & Query Operators

### Ticket Tables (`-t` / `--table`)

| Table Name | Ticket Prefix | Description |
| :--- | :--- | :--- |
| `task` | `TASK` / All | Base table for all ticket types (default for `sn list`) |
| `incident` | `INC` | Incidents |
| `sc_req_item` | `RITM` | Requested Items |
| `sc_request` | `REQ` | Service Catalog Requests |
| `sc_task` | `SCTASK` | Catalog Tasks |
| `change_request` | `CHG` | Change Requests |
| `problem` | `PRB` | Problems |

### Encoded Query Operators (`-q` / `--query`)

| Operator | Meaning | Example |
| :--- | :--- | :--- |
| `^` | AND | `active=true^priority=1` |
| `^OR` | OR | `priority=1^ORpriority=2` |
| `LIKE` | Contains | `short_descriptionLIKEvpn` |
| `STARTSWITH` | Starts with | `numberSTARTSWITHINC` |
| `!=` | Not equal | `state!=Closed` |
| `ISEMPTY` | Field is empty | `assigned_toISEMPTY` |
| `ISNOTEMPTY` | Field is not empty | `cmdb_ciISNOTEMPTY` |
| `.` (Dot-walking) | Related record field | `assigned_to.email=user@company.com` |
