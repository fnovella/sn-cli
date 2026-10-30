# sn-cli — Standalone ServiceNow CLI

A fast, zero-dependency command-line interface (`sn`) for querying, creating, and updating ServiceNow tickets and **CMDB Configuration Items (CIs)** directly from the terminal. Built using only the Ruby standard library.

---

## Features

- **Zero External Dependencies**: Uses Ruby standard library only (`net/http`, `optparse`, `json`, `uri`, `io/console`, `csv`). No `gem install` or `bundle install` required.
- **Full Ticket Lifecycle**: Query (`sn list`), inspect (`sn get`), create (`sn create`), update/resolve (`sn update`), and comment (`sn comment`) on Incidents, Change Requests, Requested Items, Catalog Tasks, and Problems.
- **CMDB Management (`sn cmdb`)**: Search, inspect (including CI upstream/downstream relationships), create, and update CMDB Configuration Items via either the direct **Table API** or ServiceNow's **Identification and Reconciliation Engine (IRE)** (`--ire`).
- **Smart Table & Class Detection**:
  - Automatically maps ticket prefixes (`INC`, `RITM`, `REQ`, `SCTASK`, `CHG`, `CTASK`, `PRB`, `PTASK`, `KB`, `TASK`) to their corresponding ServiceNow tables.
  - Built-in short aliases for CMDB classes (`linux`, `win`, `server`, `computer`, `vm`, `netgear`, `switch`, `router`, `firewall`, `app`, `service`, `db`).
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
   - Open your ServiceNow instance in Chrome/Firefox and open DevTools (`F12` -> **Network** tab).
   - Right-click any `/api/now/...` request and select **Copy** -> **Copy as cURL**.
   - Run `sn config` (or `sn config --curl`)—it will automatically detect the `Copy as cURL` command in your clipboard (or let you paste it directly) and extract your instance URL, `Cookie`, and `X-UserToken` automatically.

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

## Ticket Operations

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

# Export to CSV or JSON
sn list --group "Network" -o csv > network_tickets.csv
sn list --mine -o json | jq '.[] | {number: .number, state: .state}'

# Raw ServiceNow encoded query (sysparm_query)
sn list -t incident -q "active=true^priority<=2^assigned_toISEMPTY"
```

### 3. Create Incidents or Other Tickets (`sn create`)

Creates an Incident by default (`-t incident`), or any other ticket type (`-t change_request`, `-t problem`):

```bash
# Create an incident with impact, urgency, assignment group, and CMDB CI
sn create "VPN gateway unreachable in Madrid" \
  -D "Users unable to connect to corporate VPN since 17:30 CET" \
  --urgency 1 \
  --impact 2 \
  -g "Network Support" \
  --ci "mad-vpn-gw01"

# Create an incident with custom fields (-S KEY=VALUE) or raw JSON (-d)
sn create "Database backup failure" \
  --category "software" \
  -S u_environment=Production \
  -S contact_type=monitoring

# Create a Change Request
sn create "Upgrade core router firmware" -t change_request -g "Network Engineering"
```

### 4. Update or Resolve Tickets (`sn update`)

Updates any existing ticket by number or `sys_id`:

```bash
# Assign a ticket to yourself, set state to In Progress, and add a work note
sn update INC0010001 --state "In Progress" -a fnovella -w "Investigating BGP session logs"

# Reassign to another group and change urgency
sn update INC0010001 -g "Firewall Team" --urgency 1

# Resolve an incident with resolution code and notes
sn update INC0010001 \
  --state "Resolved" \
  --close-code "Solved (Permanently)" \
  --close-notes "Replaced faulty SFP module on interface xe-0/0/1"

# Update custom fields
sn update CHG0034567 -S u_approval_status=Approved
```

### 5. Add Comments or Work Notes (`sn comment`)

```bash
# Add a customer-visible comment
sn comment INC0010001 "We have identified the issue and are applying a fix."

# Add an internal work note (--work-note / -w)
sn comment INC0010001 "Restarted backend worker on node-03." --work-note
```

---

## CMDB Operations (`sn cmdb`)

Manage Configuration Items (CIs) across any CMDB class table. You can pass either the full ServiceNow table name (e.g. `cmdb_ci_linux_server`) or a built-in short alias via `-c` / `--class`:

| Alias | ServiceNow CMDB Table | Description |
| :--- | :--- | :--- |
| `ci` | `cmdb_ci` | Base Configuration Item table (default for `list` / `get`) |
| `server` | `cmdb_ci_server` | Base Server table (default for `create`) |
| `linux` | `cmdb_ci_linux_server` | Linux Servers |
| `win` / `windows` | `cmdb_ci_win_server` | Windows Servers |
| `computer` | `cmdb_ci_computer` | Workstations & Laptops |
| `vm` | `cmdb_ci_vm_instance` | Virtual Machine Instances |
| `netgear` | `cmdb_ci_netgear` | Network Gear |
| `switch` | `cmdb_ci_ip_switch` | IP Switches |
| `router` | `cmdb_ci_ip_router` | IP Routers |
| `firewall` | `cmdb_ci_ip_firewall` | Firewalls |
| `app` | `cmdb_ci_appl` | Applications |
| `service` | `cmdb_ci_service` | Business / IT Services |
| `db` | `cmdb_ci_database` | Databases |

### 1. Search and List CIs (`sn cmdb list` / `ls`)

```bash
# Search across all CMDB classes by name, IP, serial number, or asset tag
sn cmdb list -s "mad"

# List Linux servers running Red Hat
sn cmdb list -c linux --os "Red Hat"

# Search by IP subnet or exact serial number
sn cmdb list --ip "10.20.30."
sn cmdb list --serial "SN-99887766"

# Export server inventory to CSV
sn cmdb list -c server -f "name,ip_address,serial_number,os,ram,cpu_count,location" -l 500 -o csv > servers.csv
```

### 2. Inspect a CI and its Relationships (`sn cmdb get`)

Look up any CI by **name**, **`sys_id`**, **serial number**, or **IP address**:

```bash
# Inspect CI details
sn cmdb get srv-linux-mad01

# Include upstream and downstream CI relationships (cmdb_rel_ci)
sn cmdb get srv-linux-mad01 --relationships

# Look up a device directly by IP address or serial number
sn cmdb get 10.20.30.40
```

### 3. Create New CMDB Items (`sn cmdb create`)

Supports both the **Direct Table API** (default) and ServiceNow's **Identification and Reconciliation Engine (IRE)** (`--ire`):

```bash
# Create a Linux server via the Table API
sn cmdb create srv-linux-mad02 \
  -c linux \
  --ip 10.20.30.42 \
  --serial "VMware-42-00-aa-bb" \
  --os "Linux Red Hat" \
  --ram 32768 \
  --cpu-count 8 \
  --location "Madrid" \
  -g "Linux Admin" \
  --status 1

# Create or reconcile (upsert) via the CMDB IRE API (--ire) to prevent duplicates
sn cmdb create srv-linux-mad02 \
  -c linux \
  --ire \
  --source "Manual Entry" \
  --serial "VMware-42-00-aa-bb" \
  --ip 10.20.30.42

# Create an Application CI with custom attributes
sn cmdb create "Payments API" -c app -S u_criticality=High -S version=2.4.0
```

### 4. Update Existing CMDB Items (`sn cmdb update`)

Update any CI by its name, `sys_id`, serial number, or IP address:

```bash
# Update hardware specs and IP address
sn cmdb update srv-linux-mad02 --ip 10.20.30.99 --ram 65536 --cpu-count 16

# Decommission / change operational status and add custom fields
sn cmdb update srv-linux-mad02 --status 2 -S install_status=7 -D "Decommissioned on 2026-10-29"
```

---

## Reference: Common ServiceNow Tables & Query Operators

### Ticket Tables (`-t` / `--table`)

| Table Name | Ticket Prefix | Description |
| :--- | :--- | :--- |
| `task` | `TASK` / All | Base table for all ticket types (default for `sn list`) |
| `incident` | `INC` | Incidents (default for `sn create`) |
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
