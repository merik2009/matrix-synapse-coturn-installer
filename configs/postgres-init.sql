-- PostgreSQL initialization script for Matrix Synapse

-- Create extensions if they don't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Ensure proper encoding
UPDATE pg_database SET datcollate='C', datctype='C' WHERE datname='synapse';

-- Grant all necessary permissions to synapse user
GRANT ALL PRIVILEGES ON DATABASE synapse TO synapse;
GRANT ALL PRIVILEGES ON SCHEMA public TO synapse;

-- Set timezone
SET timezone = 'UTC';
