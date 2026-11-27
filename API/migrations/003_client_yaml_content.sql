ALTER TABLE client_yaml_files
    ALTER COLUMN storage_path DROP NOT NULL;

ALTER TABLE client_yaml_files
    ADD COLUMN IF NOT EXISTS content BYTEA;

ALTER TABLE client_yaml_files
    ADD COLUMN IF NOT EXISTS uploaded_by VARCHAR(100);