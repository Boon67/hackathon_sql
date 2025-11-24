-- ============================================
-- HACKATHON ENVIRONMENT SETUP
-- ============================================
-- Creates isolated databases and warehouses for hackathon participants
-- Grants Cortex AI permissions and sets user defaults

-- Initial setup
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE DATABASE HACK_ADMIN;
USE DATABASE HACK_ADMIN;
USE WAREHOUSE COMPUTE_WH;

-- ============================================
-- CONFIGURATION: Add usernames here
-- ============================================
CREATE OR REPLACE TABLE user_list (username VARCHAR);
INSERT INTO user_list VALUES ('tboon'); -- Add more users as needed

-- ============================================
-- BACKUP USER DEFAULTS
-- ============================================
CREATE OR REPLACE TABLE user_defaults_backup AS
SELECT 
    name as username,
    default_role,
    default_warehouse,
    default_namespace,
    CURRENT_TIMESTAMP() as backup_timestamp
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE name IN (SELECT UPPER(username) FROM user_list);

-- ============================================
-- CREATE ROLES
-- ============================================
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS HACKATHON_ADMIN;
CREATE ROLE IF NOT EXISTS HACKATHON_PARTICIPANT;

GRANT ROLE HACKATHON_PARTICIPANT TO ROLE HACKATHON_ADMIN;
GRANT ROLE HACKATHON_ADMIN TO ROLE ACCOUNTADMIN;

-- Grant admin privileges
USE ROLE ACCOUNTADMIN;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE HACKATHON_ADMIN;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE HACKATHON_ADMIN;

-- Grant Cortex AI permissions to participant role
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE HACKATHON_PARTICIPANT;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE HACKATHON_PARTICIPANT;

-- ============================================
-- GENERATE SETUP COMMANDS
-- ============================================
CREATE OR REPLACE TABLE setup_commands AS
WITH user_resources AS (
    SELECT 
        UPPER(username) as username,
        'DB_HACK_' || UPPER(username) as db_name,
        'WH_HACK_' || UPPER(username) as wh_name
    FROM user_list
),
command_array AS (
    SELECT 
        username, db_name, wh_name,
        ARRAY_CONSTRUCT(
            -- Create warehouse
            'CREATE WAREHOUSE IF NOT EXISTS ' || wh_name || 
            ' WITH WAREHOUSE_SIZE = ''XSMALL'' AUTO_SUSPEND = 300 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;',
            
            -- Create database and schema
            'CREATE DATABASE IF NOT EXISTS ' || db_name || ';',
            'CREATE SCHEMA IF NOT EXISTS ' || db_name || '.PUBLIC;',
            
            -- Grant warehouse ownership to admin, usage to participant
            'GRANT OWNERSHIP ON WAREHOUSE ' || wh_name || ' TO ROLE HACKATHON_ADMIN;',
            'GRANT USAGE, OPERATE ON WAREHOUSE ' || wh_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            
            -- Grant database ownership to admin, full access to participant
            'GRANT OWNERSHIP ON DATABASE ' || db_name || ' TO ROLE HACKATHON_ADMIN;',
            'GRANT ALL PRIVILEGES ON DATABASE ' || db_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            'GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE ' || db_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            'GRANT ALL PRIVILEGES ON FUTURE SCHEMAS IN DATABASE ' || db_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            'GRANT ALL PRIVILEGES ON ALL TABLES IN DATABASE ' || db_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            'GRANT ALL PRIVILEGES ON FUTURE TABLES IN DATABASE ' || db_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            'GRANT ALL PRIVILEGES ON ALL VIEWS IN DATABASE ' || db_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            'GRANT ALL PRIVILEGES ON FUTURE VIEWS IN DATABASE ' || db_name || ' TO ROLE HACKATHON_PARTICIPANT;',
            'GRANT CREATE STREAMLIT ON SCHEMA ' || db_name || '.PUBLIC TO ROLE HACKATHON_PARTICIPANT;',
            
            -- Grant participant role to user
            'GRANT ROLE HACKATHON_PARTICIPANT TO USER ' || username || ';',
            
            -- Set user defaults
            'ALTER USER ' || username || ' SET ' ||
            'DEFAULT_ROLE = ''HACKATHON_PARTICIPANT'', ' ||
            'DEFAULT_WAREHOUSE = ''' || wh_name || ''', ' ||
            'DEFAULT_NAMESPACE = ''' || db_name || '.PUBLIC'';'
        ) as commands
    FROM user_resources
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY username) as execution_order,
    username, db_name, wh_name,
    value as sql_command
FROM command_array, LATERAL FLATTEN(input => commands);

-- ============================================
-- EXECUTION PROCEDURE
-- ============================================
CREATE OR REPLACE PROCEDURE run_hackathon_setup()
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var total = 0, success = 0, errors = 0;
    
    try {
        snowflake.createStatement({sqlText: "USE ROLE ACCOUNTADMIN"}).execute();
        snowflake.createStatement({sqlText: "USE DATABASE HACK_ADMIN"}).execute();
        snowflake.createStatement({sqlText: 
            "CREATE OR REPLACE TABLE HACK_ADMIN.PUBLIC.execution_log " +
            "(execution_order NUMBER, status VARCHAR, sql_command VARCHAR, error_message VARCHAR, " +
            "executed_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP())"
        }).execute();
    } catch (err) {
        return "FATAL ERROR: " + err.message;
    }
    
    var commands = snowflake.createStatement({
        sqlText: "SELECT execution_order, sql_command FROM HACK_ADMIN.PUBLIC.setup_commands ORDER BY execution_order"
    }).execute();
    
    while (commands.next()) {
        total++;
        var order = commands.getColumnValue(1);
        var sql = commands.getColumnValue(2);
        var status = 'SUCCESS', error_msg = null;
        
        try {
            snowflake.createStatement({sqlText: sql}).execute();
            success++;
        } catch (err) {
            status = 'ERROR';
            error_msg = err.message;
            errors++;
        }
        
        snowflake.createStatement({sqlText: 
            `INSERT INTO HACK_ADMIN.PUBLIC.execution_log (execution_order, status, sql_command, error_message) VALUES (
                ${order}, '${status}', 
                '${sql.substring(0, 500).replace(/'/g, "''")}',
                ${error_msg ? "'" + error_msg.substring(0, 500).replace(/'/g, "''") + "'" : "NULL"}
            )`
        }).execute();
    }
    
    return `SETUP COMPLETE!\nTotal: ${total} | Success: ${success} | Errors: ${errors}\n\n` +
           `View details: SELECT * FROM HACK_ADMIN.PUBLIC.execution_log ORDER BY execution_order;`;
$$;

-- ============================================
-- EXECUTE SETUP
-- ============================================
CALL run_hackathon_setup();

-- ============================================
-- VIEW RESULTS
-- ============================================
-- Show any errors
SELECT * FROM HACK_ADMIN.PUBLIC.execution_log WHERE status = 'ERROR' ORDER BY execution_order;

-- Verify user configuration
SELECT 
    ul.username,
    ur.db_name as database_created,
    ur.wh_name as warehouse_created,
    u.default_role,
    u.default_warehouse,
    u.default_namespace
FROM user_list ul
LEFT JOIN (SELECT DISTINCT username, db_name, wh_name FROM HACK_ADMIN.PUBLIC.setup_commands) ur ON UPPER(ul.username) = ur.username
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON UPPER(ul.username) = u.name
ORDER BY ul.username;

-- Show backed up defaults
SELECT * FROM HACK_ADMIN.PUBLIC.user_defaults_backup ORDER BY username;

show users like 'tboon'
