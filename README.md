# Hackathon Environment Management

Automated SQL scripts to provision and manage isolated Snowflake environments for hackathon participants.

## Overview

These scripts create isolated databases and warehouses for each hackathon participant, grant necessary permissions including Cortex AI access, and manage user defaults. They also provide cleanup functionality to restore users to their original state.

## Files

### 1. `hackathon_setup.sql`
Creates hackathon environments for a list of users.

**What it does:**
- Backs up existing user defaults (role, warehouse, database)
- Creates two roles:
  - `HACKATHON_ADMIN` - Administrative role with create database/warehouse privileges
  - `HACKATHON_PARTICIPANT` - Participant role with full database access
- For each user creates:
  - Database: `DB_HACK_<USERNAME>`
  - Warehouse: `WH_HACK_<USERNAME>` (XSMALL, auto-suspend 5min)
- Grants Cortex AI permissions (`SNOWFLAKE.CORTEX_USER`)
- Sets user defaults to hackathon role, database, and warehouse
- Logs all execution with detailed error tracking

**Usage:**
1. Edit the `user_list` table to add your usernames
2. Run the entire script
3. Review results in `HACK_ADMIN.PUBLIC.execution_log`

**Requirements:**
- Users must already exist in Snowflake
- Must run with `ACCOUNTADMIN` role
- Requires `COMPUTE_WH` warehouse

---

### 2. `hackathon_cleanup.sql`
Restores users to pre-hackathon state and optionally removes resources.

**Two cleanup options:**

#### Option A: Restore User Defaults Only
```sql
CALL HACK_ADMIN.PUBLIC.restore_user_defaults();
```
- Revokes `HACKATHON_PARTICIPANT` role from users
- Restores original role/warehouse/database defaults
- Keeps databases and warehouses intact

#### Option B: Full Cleanup
```sql
CALL HACK_ADMIN.PUBLIC.full_hackathon_cleanup();
```
- Restores user defaults (same as Option A)
- Drops all `DB_HACK_*` databases
- Drops all `WH_HACK_*` warehouses
- Drops `HACKATHON_ADMIN` and `HACKATHON_PARTICIPANT` roles

**Usage:**
1. Uncomment your preferred option at the bottom of the script
2. Run the script
3. Review results in `HACK_ADMIN.PUBLIC.restore_log` or `HACK_ADMIN.PUBLIC.cleanup_log`

---

## Database Schema

All metadata is stored in `HACK_ADMIN` database:

| Table | Description |
|-------|-------------|
| `user_list` | List of hackathon participant usernames |
| `user_defaults_backup` | Backup of original user defaults before hackathon |
| `setup_commands` | Generated SQL commands for environment setup |
| `execution_log` | Setup execution results (success/error tracking) |
| `restore_log` | User defaults restoration results (Option A) |
| `cleanup_log` | Full cleanup execution results (Option B) |

---

## Permissions Granted

### To HACKATHON_ADMIN
- Create databases and warehouses on account
- Ownership of all created resources

### To HACKATHON_PARTICIPANT
- Full privileges on assigned database (`DB_HACK_<USERNAME>`)
- Usage and operate on assigned warehouse (`WH_HACK_<USERNAME>`)
- Cortex AI functions (via `SNOWFLAKE.CORTEX_USER`)
- Create Streamlit apps in PUBLIC schema

---

## Example Workflow

```sql
-- 1. Setup hackathon environments
-- Edit user_list in hackathon_setup.sql, then run it
-- Review: SELECT * FROM HACK_ADMIN.PUBLIC.execution_log WHERE status = 'ERROR';

-- 2. Participants work in their isolated environments
-- Each user logs in with:
--   - Role: HACKATHON_PARTICIPANT
--   - Database: DB_HACK_<USERNAME>
--   - Warehouse: WH_HACK_<USERNAME>

-- 3. After hackathon: Restore defaults only
CALL HACK_ADMIN.PUBLIC.restore_user_defaults();

-- OR: Full cleanup (removes all resources)
CALL HACK_ADMIN.PUBLIC.full_hackathon_cleanup();

-- Verify cleanup
SELECT * FROM HACK_ADMIN.PUBLIC.cleanup_log;
```

---

## Troubleshooting

**Error: "Table does not exist or not authorized"**
- Ensure you're running with `ACCOUNTADMIN` role
- The script automatically uses fully qualified table names

**Error: "User does not exist"**
- All users must exist before running setup
- Check usernames: `SELECT name FROM SNOWFLAKE.ACCOUNT_USAGE.USERS WHERE name LIKE '%USERNAME%';`

**Restore fails**
- Verify backup exists: `SELECT * FROM HACK_ADMIN.PUBLIC.user_defaults_backup;`
- Check if resources are in use (active queries/sessions)

---

## Notes

- All warehouses are created as XSMALL with 5-minute auto-suspend
- Databases are created as permanent (not transient)
- User defaults are automatically set, no manual configuration needed
- Scripts are idempotent - safe to re-run if errors occur
