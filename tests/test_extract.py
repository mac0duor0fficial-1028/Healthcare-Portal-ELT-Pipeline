from unittest.mock import MagicMock

import pytest

from extract_load import config
from extract_load.extract import ExtractError, fetch_json, normalize_records, run
from extract_load.snowflake_loader import SnowflakeLoader


def test_normalize_plain_list():
    assert normalize_records([{"id": 1}], "x") == [{"id": 1}]


def test_normalize_wrapped_list():
    assert normalize_records({"data": [{"id": 1}], "total": 1}, "x") == [{"id": 1}]


@pytest.mark.parametrize("payload", [{"unexpected": 1}, "text", 42, None])
def test_normalize_rejects_bad_shape(payload):
    with pytest.raises(ExtractError):
        normalize_records(payload, "x")


def test_normalize_rejects_non_objects():
    with pytest.raises(ExtractError):
        normalize_records([{"id": 1}, 5], "x")


def _response(status=200, body=None):
    r = MagicMock()
    r.status_code = status
    r.json.return_value = body
    r.raise_for_status.side_effect = None if status < 400 else RuntimeError("http")
    return r


def test_fetch_json_builds_url_and_returns_body():
    session = MagicMock()
    session.get.return_value = _response(200, [{"id": 1}])
    assert fetch_json(session, "patients") == [{"id": 1}]
    assert session.get.call_args.args[0] == f"{config.BASE_URL}/patients"


def test_run_refuses_empty_endpoint(monkeypatch):
    monkeypatch.setattr("extract_load.extract.fetch_json", lambda s, e: [])
    assert run(["patients"], skip_load=True) == 1


def test_run_allows_empty_when_flagged(monkeypatch):
    monkeypatch.setattr("extract_load.extract.fetch_json", lambda s, e: [])
    assert run(["patients"], skip_load=True, allow_empty=True) == 0


def test_run_does_not_load_if_any_endpoint_fails(monkeypatch):
    def fake(session, endpoint):
        if endpoint == "patients":
            return [{"id": 1}]
        raise ExtractError("boom")

    monkeypatch.setattr("extract_load.extract.fetch_json", fake)
    loader = MagicMock()
    monkeypatch.setattr(SnowflakeLoader, "from_env", classmethod(lambda cls: loader))
    assert run(["patients", "appointments"]) == 1
    loader.load_records.assert_not_called()


def test_run_snapshot_written(monkeypatch, tmp_path):
    monkeypatch.setattr("extract_load.extract.fetch_json", lambda s, e: [{"id": 1}])
    assert run(["roles"], skip_load=True, snapshot_dir=tmp_path) == 0
    assert len(list(tmp_path.glob("roles_*.json"))) == 1


def test_loader_rejects_sql_injection_in_identifiers():
    loader = SnowflakeLoader(MagicMock())
    with pytest.raises(ValueError):
        loader.load_records(
            table="RAW_X; DROP TABLE y", endpoint="patients", records=[{}],
            batch_id="abc", loaded_at="2026-01-01T00:00:00.000000+00:00",
        )
    with pytest.raises(ValueError):
        loader.load_records(
            table="RAW_X", endpoint="patients", records=[{}],
            batch_id="abc", loaded_at="2026-01-01'; --",
        )


def test_loader_copy_flow_and_count_check():
    conn = MagicMock()
    cur = conn.cursor.return_value
    cur.fetchone.return_value = (2,)
    SnowflakeLoader(conn).load_records(
        table="RAW_PATIENTS", endpoint="patients", records=[{"a": 1}, {"a": 2}],
        batch_id="abc123", loaded_at="2026-01-01T00:00:00.000000+00:00",
    )
    sqls = [c.args[0] for c in cur.execute.call_args_list]
    assert sqls[0].startswith("PUT 'file://")
    assert "COPY INTO RAW_PATIENTS" in sqls[1]
    assert any("INSERT INTO EXTRACT_LOG" in s for s in sqls)


def test_loader_detects_count_mismatch():
    conn = MagicMock()
    conn.cursor.return_value.fetchone.return_value = (1,)
    with pytest.raises(RuntimeError):
        SnowflakeLoader(conn).load_records(
            table="RAW_PATIENTS", endpoint="patients", records=[{}, {}],
            batch_id="abc123", loaded_at="2026-01-01T00:00:00.000000+00:00",
        )
