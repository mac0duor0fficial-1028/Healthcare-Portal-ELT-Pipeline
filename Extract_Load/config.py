"""Static configuration for the extract/load step."""
from __future__ import annotations

import os

BASE_URL = os.getenv(
    "API_BASE_URL", "https://testprojectapi.gerasim.in/api/DoctorAppointment"
).rstrip("/")

REQUEST_TIMEOUT_S = int(os.getenv("API_TIMEOUT_S", "30"))

# GET endpoint (relative to BASE_URL) -> RAW table in TELEHEALTH_RAW.API
# Only documented GET endpoints are used. POST/PUT are never called because the
# service is a shared practice API and writes would alter other people's data.
ENDPOINTS: dict[str, str] = {
    "roles": "RAW_ROLES",
    "users": "RAW_USERS",
    "locations": "RAW_LOCATIONS",
    "diseases": "RAW_DISEASES",
    "visiting-hours-schedules": "RAW_VISITING_HOURS_SCHEDULES",
    "patients": "RAW_PATIENTS",
    "appointments": "RAW_APPOINTMENTS",
}

# If a payload is an object wrapping the list, these keys are tried in order.
WRAPPER_KEYS = ("data", "items", "results", "result", "records", "value")

# Row counts that often indicate server-side truncation/pagination.
SUSPICIOUS_COUNTS = frozenset({10, 20, 25, 50, 100, 200, 250, 500, 1000, 5000, 10000})

SNOWFLAKE_RAW_DATABASE = os.getenv("SNOWFLAKE_RAW_DATABASE", "TELEHEALTH_RAW")
SNOWFLAKE_RAW_SCHEMA = os.getenv("SNOWFLAKE_RAW_SCHEMA", "API")
SNOWFLAKE_STAGE = os.getenv("SNOWFLAKE_STAGE", "STG_RAW_JSON")


def entity_name(endpoint: str) -> str:
    """'visiting-hours-schedules' -> 'visiting_hours_schedules' (dbt field_map key)."""
    return endpoint.replace("-", "_")
