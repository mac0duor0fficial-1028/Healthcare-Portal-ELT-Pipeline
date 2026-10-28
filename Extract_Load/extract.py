"""Extract: pull every configured GET endpoint, then (optionally) load into Snowflake.

Design rules
------------
* Raw payloads are landed untouched (VARIANT). All cleaning happens in dbt (ELT).
* Everything is fetched *before* anything is loaded, so an API failure never leaves
  RAW half-updated.
* Each run is a full snapshot with a single batch_id; dbt reads the latest batch.
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path

import requests
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from extract_load import config

log = logging.getLogger("extract")


class ExtractError(Exception):
    """Non-retryable extraction problem (bad payload shape, empty response, ...)."""


class RetryableHTTPError(Exception):
    """HTTP 429/5xx - worth retrying."""


@retry(
    retry=retry_if_exception_type(
        (requests.ConnectionError, requests.Timeout, RetryableHTTPError)
    ),
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=2, max=30),
    reraise=True,
)
def fetch_json(session: requests.Session, endpoint: str) -> object:
    url = f"{config.BASE_URL}/{endpoint}"
    resp = session.get(url, timeout=config.REQUEST_TIMEOUT_S)
    if resp.status_code == 429 or resp.status_code >= 500:
        raise RetryableHTTPError(f"{url} -> HTTP {resp.status_code}")
    resp.raise_for_status()
    try:
        return resp.json()
    except ValueError as exc:
        raise ExtractError(f"{url}: response is not valid JSON") from exc


def normalize_records(payload: object, endpoint: str) -> list[dict]:
    """Return a list of JSON objects regardless of whether the API wraps the list."""
    records: list | None = None
    if isinstance(payload, list):
        records = payload
    elif isinstance(payload, dict):
        for key in config.WRAPPER_KEYS:
            if isinstance(payload.get(key), list):
                records = payload[key]
                break
    if records is None:
        raise ExtractError(f"{endpoint}: expected a JSON array (or wrapped array)")
    bad = [i for i, r in enumerate(records) if not isinstance(r, dict)]
    if bad:
        raise ExtractError(f"{endpoint}: {len(bad)} non-object records (first index {bad[0]})")
    return records


def save_snapshot(directory: Path, endpoint: str, batch_id: str, records: list[dict]) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{config.entity_name(endpoint)}_{batch_id}.json"
    path.write_text(json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8")
    return path


def run(
    endpoints: list[str],
    *,
    snapshot_dir: Path | None = None,
    skip_load: bool = False,
    allow_empty: bool = False,
) -> int:
    batch_id = uuid.uuid4().hex
    loaded_at = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.%f+00:00")
    log.info("batch_id=%s endpoints=%s", batch_id, endpoints)

    fetched: dict[str, list[dict]] = {}
    session = requests.Session()
    session.headers.update({"Accept": "application/json"})
    try:
        for endpoint in endpoints:
            records = normalize_records(fetch_json(session, endpoint), endpoint)
            if not records and not allow_empty:
                raise ExtractError(f"{endpoint}: 0 rows returned; refusing to load (--allow-empty)")
            if len(records) in config.SUSPICIOUS_COUNTS:
                log.warning(
                    "%s: %d rows is a round number - check for server-side paging/truncation",
                    endpoint,
                    len(records),
                )
            fetched[endpoint] = records
            log.info("fetched %-26s %6d rows", endpoint, len(records))
            if snapshot_dir:
                save_snapshot(snapshot_dir, endpoint, batch_id, records)
    except (requests.RequestException, ExtractError) as exc:
        log.error("extraction failed, nothing was loaded: %s", exc)
        return 1

    if skip_load:
        log.info("--skip-load set; done (no Snowflake writes)")
        return 0

    from extract_load.snowflake_loader import SnowflakeLoader

    try:
        with SnowflakeLoader.from_env() as loader:
            for endpoint, records in fetched.items():
                try:
                    loader.load_records(
                        table=config.ENDPOINTS[endpoint],
                        endpoint=endpoint,
                        records=records,
                        batch_id=batch_id,
                        loaded_at=loaded_at,
                    )
                    log.info("loaded  %-26s %6d rows", endpoint, len(records))
                except Exception as exc:
                    loader.log_extract(batch_id, endpoint, len(records), "FAILED", str(exc))
                    raise
    except Exception:
        log.exception("load failed")
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--endpoints",
        nargs="+",
        default=list(config.ENDPOINTS),
        choices=list(config.ENDPOINTS),
        help="subset of endpoints to pull (default: all)",
    )
    parser.add_argument("--snapshot-dir", type=Path, help="also write raw JSON files here")
    parser.add_argument("--skip-load", action="store_true", help="fetch only, no Snowflake")
    parser.add_argument("--allow-empty", action="store_true", help="permit 0-row endpoints")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    return run(
        args.endpoints,
        snapshot_dir=args.snapshot_dir,
        skip_load=args.skip_load,
        allow_empty=args.allow_empty,
    )


if __name__ == "__main__":
    sys.exit(main())
