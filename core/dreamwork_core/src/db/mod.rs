//! SQLite bootstrap + versioned migrations + [`schema_change_log`] (ADR 0005 DDL auditing).

mod migrate;

pub use migrate::{
    apply_adhoc_ddl, apply_core_migrations, checksum_sql, ensure_bootstrap_schema, MigrationError,
};
