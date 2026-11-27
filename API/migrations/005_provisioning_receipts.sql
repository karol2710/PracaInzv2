BEGIN;
CREATE TABLE client_provisioning_objects (
 job_id BIGINT NOT NULL REFERENCES client_provisioning_jobs(id) ON DELETE RESTRICT,
 api_version TEXT NOT NULL, kind TEXT NOT NULL, namespace_name TEXT NOT NULL,
 object_name TEXT NOT NULL, object_uid TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(job_id, api_version, kind, namespace_name, object_name)
);
COMMIT;
