"""Land raw JSON records in Snowflake using PUT + COPY INTO (bulk, not row-by-row)."""
from __future__ import annotations

import json
import logging
import os
import re
import tempfile
from pathlib import Path

from extract_load import config

log = logging.getLogger("loader")

_IDENT = re.compile(r"^[A-Za-z0-9_]+$")
_TS = re.compile(r"^[0-9T:.+\-]+$")


def _require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _safe_ident(value: str, what: str) -> str:
    if not _IDENT.fullmatch(value):
        raise ValueError(f"Unsafe {what}: {value!r}")
    return value


class SnowflakeLoader:
    def __init__(self, connection, stage: str = config.SNOWFLAKE_STAGE):
        self.conn = connection
        self.stage = _safe_ident(stage, "stage")

    @classmethod
    def from_env(cls) -> SnowflakeLoader:
        import snowflake.connector  # imported lazily so unit tests need no driver

        kwargs = {
            "account": _require_env("SNOWFLAKE_ACCOUNT"),
            "user": _require_env("SNOWFLAKE_LOADER_USER"),
            "private_key_file": _require_env("SNOWFLAKE_LOADER_PRIVATE_KEY_PATH"),
            "role": os.getenv("SNOWFLAKE_LOADER_ROLE", "LOADER"),
            "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "WH_ELT"),
            "database": config.SNOWFLAKE_RAW_DATABASE,
            "schema": config.SNOWFLAKE_RAW_SCHEMA,
            "session_parameters": {"TIMEZONE": "UTC"},
        }
        passphrase = os.getenv("SNOWFLAKE_LOADER_PRIVATE_KEY_PASSPHRASE")
        if passphrase:
            kwargs["private_key_file_pwd"] = passphrase
        return cls(snowflake.connector.connect(**kwargs))

    def __enter__(self) -> SnowflakeLoader:
        return self

    def __exit__(self, *exc) -> None:
        self.conn.close()

    # ------------------------------------------------------------------
    def load_records(
        self,
        *,
        table: str,
        endpoint: str,
        records: list[dict],
        batch_id: str,
        loaded_at: str,
    ) -> None:
        table = _safe_ident(table, "table")
        slug = _safe_ident(config.entity_name(endpoint), "endpoint")
        batch_id = _safe_ident(batch_id, "batch_id")
        if not _TS.fullmatch(loaded_at):
            raise ValueError(f"Unsafe timestamp: {loaded_at!r}")

        stage_dir = f"@{self.stage}/{batch_id}/{slug}"
        cur = self.conn.cursor()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / f"{slug}.ndjson"
                with path.open("w", encoding="utf-8") as fh:
                    for rec in records:
                        fh.write(json.dumps(rec, separators=(",", ":"), ensure_ascii=True) + "\n")
                cur.execute(
                    f"PUT 'file://{path.as_posix()}' {stage_dir}/ "
                    "AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
                )
            # Values interpolated below are validated against strict regexes above.
            cur.execute(
                f"""
                COPY INTO {table} (payload, _batch_id, _loaded_at, _source_endpoint)
                FROM (
                    SELECT $1, '{batch_id}', '{loaded_at}'::TIMESTAMP_TZ, '{endpoint}'
                    FROM {stage_dir}/
                )
                FILE_FORMAT = (TYPE = JSON)
                ON_ERROR = ABORT_STATEMENT
                PURGE = TRUE
                """
            )
            cur.execute(
                f"SELECT COUNT(*) FROM {table} WHERE _batch_id = %s AND _source_endpoint = %s",
                (batch_id, endpoint),
            )
            (loaded,) = cur.fetchone()
            if loaded != len(records):
                raise RuntimeError(
                    f"{endpoint}: loaded {loaded} rows but extracted {len(records)}"
                )
        finally:
            cur.close()
        self.log_extract(batch_id, endpoint, len(records), "SUCCESS", None)

    def log_extract(
        self, batch_id: str, endpoint: str, row_count: int, status: str, message: str | None
    ) -> None:
        """Best-effort audit row; used by dbt to reconcile staged vs extracted counts."""
        try:
            cur = self.conn.cursor()
            try:
                cur.execute(
                    "INSERT INTO EXTRACT_LOG (batch_id, endpoint, row_count, status, message, "
                    "loaded_at) VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP())",
                    (batch_id, endpoint, row_count, status, (message or "")[:2000]),
                )
            finally:
                cur.close()
        except Exception:  # never mask the original error
            log.exception("could not write EXTRACT_LOG row")
