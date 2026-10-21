-- Post-initialization script to ensure permissions are properly set
-- This ensures deployer_user has all necessary permissions on kubechart database

-- Grant database privileges
GRANT ALL PRIVILEGES ON DATABASE kubechart TO deployer_user;

-- Connect to kubechart database and set permissions
\connect kubechart

-- Create extensions if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant schema privileges
GRANT ALL PRIVILEGES ON SCHEMA public TO deployer_user;

-- Grant all current table privileges
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO deployer_user;

-- Grant all current sequence privileges
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO deployer_user;

-- Grant all current function privileges
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO deployer_user;

-- Set default privileges for future objects created by postgres user
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO deployer_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO deployer_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO deployer_user;

-- Verify permissions
SELECT 'Permissions configured successfully' AS status;
