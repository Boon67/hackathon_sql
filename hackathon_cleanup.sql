-- ============================================
-- HACKATHON ENVIRONMENT CLEANUP & RESET
-- ============================================
-- Restores user defaults to pre-hackathon state
-- Optionally drops hackathon databases and warehouses

USE ROLE ACCOUNTADMIN;
USE DATABASE HACK_ADMIN;

-- ============================================
-- OPTION 1: RESTORE USER DEFAULTS ONLY
-- ============================================
-- This keeps databases/warehouses but resets user defaults to original values

CREATE OR REPLACE PROCEDURE restore_user_defaults()
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var success = 0, errors = 0, no_backup = 0;
    
    try {
        snowflake.createStatement({sqlText: "USE ROLE ACCOUNTADMIN"}).execute();
        snowflake.createStatement({sqlText: "USE DATABASE HACK_ADMIN"}).execute();
        snowflake.createStatement({sqlText: 
            "CREATE OR REPLACE TABLE HACK_ADMIN.PUBLIC.restore_log " +
            "(username VARCHAR, status VARCHAR, action VARCHAR, error_message VARCHAR, " +
            "restored_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())"
        }).execute();
    } catch (err) {
        return "FATAL ERROR: " + err.message;
    }
    
    var users = snowflake.createStatement({
        sqlText: "SELECT username, default_role, default_warehouse, default_namespace FROM HACK_ADMIN.PUBLIC.user_defaults_backup"
    }).execute();
    
    while (users.next()) {
        var username = users.getColumnValue(1);
        var def_role = users.getColumnValue(2);
        var def_wh = users.getColumnValue(3);
        var def_ns = users.getColumnValue(4);
        var status = 'SUCCESS', error_msg = null, action = '';
        
        try {
            // Revoke hackathon role
            snowflake.createStatement({
                sqlText: `REVOKE ROLE HACKATHON_PARTICIPANT FROM USER ${username}`
            }).execute();
            
            // Restore or clear defaults
            if (def_role || def_wh || def_ns) {
                var set_parts = [];
                if (def_role) set_parts.push(`DEFAULT_ROLE = '${def_role}'`);
                if (def_wh) set_parts.push(`DEFAULT_WAREHOUSE = '${def_wh}'`);
                if (def_ns) set_parts.push(`DEFAULT_NAMESPACE = '${def_ns}'`);
                
                snowflake.createStatement({
                    sqlText: `ALTER USER ${username} SET ${set_parts.join(', ')}`
                }).execute();
                action = 'Restored to original defaults';
            } else {
                snowflake.createStatement({
                    sqlText: `ALTER USER ${username} UNSET DEFAULT_ROLE, DEFAULT_WAREHOUSE, DEFAULT_NAMESPACE`
                }).execute();
                action = 'Cleared all defaults (no previous values)';
            }
            success++;
        } catch (err) {
            status = 'ERROR';
            error_msg = err.message;
            action = 'Failed to restore';
            errors++;
        }
        
        snowflake.createStatement({sqlText: 
            `INSERT INTO HACK_ADMIN.PUBLIC.restore_log (username, status, action, error_message) VALUES (
                '${username}', '${status}', '${action}',
                ${error_msg ? "'" + error_msg.substring(0, 500).replace(/'/g, "''") + "'" : "NULL"}
            )`
        }).execute();
    }
    
    return `RESTORE COMPLETE!\nSuccess: ${success} | Errors: ${errors}\n\n` +
           `View details: SELECT * FROM HACK_ADMIN.PUBLIC.restore_log ORDER BY username;`;
$$;

-- ============================================
-- OPTION 2: FULL CLEANUP (RESTORE + DROP RESOURCES)
-- ============================================
-- Restores user defaults AND drops all hackathon databases/warehouses

CREATE OR REPLACE PROCEDURE full_hackathon_cleanup()
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var user_success = 0, user_errors = 0;
    var db_success = 0, db_errors = 0;
    var wh_success = 0, wh_errors = 0;
    
    try {
        snowflake.createStatement({sqlText: "USE ROLE ACCOUNTADMIN"}).execute();
        snowflake.createStatement({sqlText: "USE DATABASE HACK_ADMIN"}).execute();
        snowflake.createStatement({sqlText: 
            "CREATE OR REPLACE TABLE HACK_ADMIN.PUBLIC.cleanup_log " +
            "(resource_type VARCHAR, resource_name VARCHAR, status VARCHAR, error_message VARCHAR, " +
            "cleaned_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())"
        }).execute();
    } catch (err) {
        return "FATAL ERROR: " + err.message;
    }
    
    // Step 1: Restore user defaults and revoke roles
    var users = snowflake.createStatement({
        sqlText: "SELECT username, default_role, default_warehouse, default_namespace FROM HACK_ADMIN.PUBLIC.user_defaults_backup"
    }).execute();
    
    while (users.next()) {
        var username = users.getColumnValue(1);
        var def_role = users.getColumnValue(2);
        var def_wh = users.getColumnValue(3);
        var def_ns = users.getColumnValue(4);
        var status = 'SUCCESS', error_msg = null;
        
        try {
            snowflake.createStatement({
                sqlText: `REVOKE ROLE HACKATHON_PARTICIPANT FROM USER ${username}`
            }).execute();
            
            if (def_role || def_wh || def_ns) {
                var set_parts = [];
                if (def_role) set_parts.push(`DEFAULT_ROLE = '${def_role}'`);
                if (def_wh) set_parts.push(`DEFAULT_WAREHOUSE = '${def_wh}'`);
                if (def_ns) set_parts.push(`DEFAULT_NAMESPACE = '${def_ns}'`);
                
                snowflake.createStatement({
                    sqlText: `ALTER USER ${username} SET ${set_parts.join(', ')}`
                }).execute();
            } else {
                snowflake.createStatement({
                    sqlText: `ALTER USER ${username} UNSET DEFAULT_ROLE, DEFAULT_WAREHOUSE, DEFAULT_NAMESPACE`
                }).execute();
            }
            user_success++;
        } catch (err) {
            status = 'ERROR';
            error_msg = err.message;
            user_errors++;
        }
        
        snowflake.createStatement({sqlText: 
            `INSERT INTO HACK_ADMIN.PUBLIC.cleanup_log (resource_type, resource_name, status, error_message) VALUES (
                'USER', '${username}', '${status}',
                ${error_msg ? "'" + error_msg.substring(0, 500).replace(/'/g, "''") + "'" : "NULL"}
            )`
        }).execute();
    }
    
    // Step 2: Drop databases
    var databases = snowflake.createStatement({
        sqlText: "SELECT DISTINCT db_name FROM HACK_ADMIN.PUBLIC.setup_commands"
    }).execute();
    
    while (databases.next()) {
        var db_name = databases.getColumnValue(1);
        var status = 'SUCCESS', error_msg = null;
        
        try {
            snowflake.createStatement({
                sqlText: `DROP DATABASE IF EXISTS ${db_name}`
            }).execute();
            db_success++;
        } catch (err) {
            status = 'ERROR';
            error_msg = err.message;
            db_errors++;
        }
        
        snowflake.createStatement({sqlText: 
            `INSERT INTO HACK_ADMIN.PUBLIC.cleanup_log (resource_type, resource_name, status, error_message) VALUES (
                'DATABASE', '${db_name}', '${status}',
                ${error_msg ? "'" + error_msg.substring(0, 500).replace(/'/g, "''") + "'" : "NULL"}
            )`
        }).execute();
    }
    
    // Step 3: Drop warehouses
    var warehouses = snowflake.createStatement({
        sqlText: "SELECT DISTINCT wh_name FROM HACK_ADMIN.PUBLIC.setup_commands"
    }).execute();
    
    while (warehouses.next()) {
        var wh_name = warehouses.getColumnValue(1);
        var status = 'SUCCESS', error_msg = null;
        
        try {
            snowflake.createStatement({
                sqlText: `DROP WAREHOUSE IF EXISTS ${wh_name}`
            }).execute();
            wh_success++;
        } catch (err) {
            status = 'ERROR';
            error_msg = err.message;
            wh_errors++;
        }
        
        snowflake.createStatement({sqlText: 
            `INSERT INTO HACK_ADMIN.PUBLIC.cleanup_log (resource_type, resource_name, status, error_message) VALUES (
                'WAREHOUSE', '${wh_name}', '${status}',
                ${error_msg ? "'" + error_msg.substring(0, 500).replace(/'/g, "''") + "'" : "NULL"}
            )`
        }).execute();
    }
    
    // Step 4: Drop roles
    try {
        snowflake.createStatement({sqlText: "DROP ROLE IF EXISTS HACKATHON_PARTICIPANT"}).execute();
        snowflake.createStatement({sqlText: "DROP ROLE IF EXISTS HACKATHON_ADMIN"}).execute();
        snowflake.createStatement({sqlText: 
            "INSERT INTO HACK_ADMIN.PUBLIC.cleanup_log (resource_type, resource_name, status) VALUES " +
            "('ROLE', 'HACKATHON_PARTICIPANT', 'SUCCESS'), " +
            "('ROLE', 'HACKATHON_ADMIN', 'SUCCESS')"
        }).execute();
    } catch (err) {
        snowflake.createStatement({sqlText: 
            `INSERT INTO HACK_ADMIN.PUBLIC.cleanup_log (resource_type, resource_name, status, error_message) VALUES ` +
            `('ROLE', 'HACKATHON_ROLES', 'ERROR', '${err.message.substring(0, 500).replace(/'/g, "''")}')`
        }).execute();
    }
    
    return `CLEANUP COMPLETE!\n` +
           `Users restored: ${user_success} (errors: ${user_errors})\n` +
           `Databases dropped: ${db_success} (errors: ${db_errors})\n` +
           `Warehouses dropped: ${wh_success} (errors: ${wh_errors})\n\n` +
           `View details: SELECT * FROM HACK_ADMIN.PUBLIC.cleanup_log ORDER BY resource_type, resource_name;`;
$$;

-- ============================================
-- EXECUTION OPTIONS
-- ============================================

-- Option A: Only restore user defaults (keep databases/warehouses)
-- CALL restore_user_defaults();

-- Option B: Full cleanup (restore users + drop all resources)
-- CALL full_hackathon_cleanup();

-- ============================================
-- VIEW CLEANUP RESULTS
-- ============================================

-- View restore log (Option A)
 SELECT * FROM HACK_ADMIN.PUBLIC.restore_log ORDER BY username;

-- View cleanup log (Option B)
-- SELECT * FROM HACK_ADMIN.PUBLIC.cleanup_log ORDER BY resource_type, resource_name;

-- Verify user defaults are restored
SELECT 
    name as username,
    default_role,
    default_warehouse,
    default_namespace
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE name IN (SELECT UPPER(username) FROM HACK_ADMIN.PUBLIC.user_list);

-- Verify resources are dropped (for Option B)
-- SHOW DATABASES LIKE 'DB_HACK_%';
-- SHOW WAREHOUSES LIKE 'WH_HACK_%';
-- SHOW ROLES LIKE 'HACKATHON_%';
