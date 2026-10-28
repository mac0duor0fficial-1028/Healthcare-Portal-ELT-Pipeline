"""Profile the live API and check dbt's field_map against what the API really returns.

Run this FIRST (`make profile`). It writes docs/api_profile.md and prints, per entity:
  * every key actually present (type mix, null rate, distinct count, sample)
  * for each canonical field in dbt_project.yml -> which candidate key matched (or MISSING)
  * keys that no canonical field uses (candidates for new mappings)
Exit code 1 if any *required* field has no match, so it can gate CI/onboarding.
"""
from __future__ import annotations

import argparse
import logging
import sys
from collections import Counter, defaultdict
from pathlib import Path

import requests
import yaml

from extract_load import config
from extract_load.extract import fetch_json, normalize_records

DBT_PROJECT = Path(__file__).resolve().parents[1] / "dbt_project" / "dbt_project.yml"
OUT = Path(__file__).resolve().parents[1] / "docs" / "api_profile.md"


def load_field_map(path: Path = DBT_PROJECT) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))["vars"]["field_map"]


def profile_records(records: list[dict]) -> dict[str, dict]:
    stats: dict[str, dict] = defaultdict(
        lambda: {"types": Counter(), "nulls": 0, "values": set(), "sample": None}
    )
    for rec in records:
        for key, val in rec.items():
            s = stats[key]
            s["types"][type(val).__name__] += 1
            if val is None or val == "":
                s["nulls"] += 1
            else:
                if len(s["values"]) < 5000:
                    s["values"].add(str(val))
                if s["sample"] is None:
                    s["sample"] = str(val)[:60]
    n = len(records)
    out = {}
    for key, s in stats.items():
        present = sum(s["types"].values())
        out[key] = {
            "types": dict(s["types"]),
            "missing_from_records": n - present,
            "null_rate": round((s["nulls"] + n - present) / n, 3) if n else None,
            "distinct": len(s["values"]),
            "sample": s["sample"],
        }
    return out


def resolve(candidates: list[str], keys: list[str]) -> str | None:
    """Case-insensitive match, mirroring Snowflake GET_IGNORE_CASE in the dbt macro."""
    lowered = {k.lower(): k for k in keys}
    for cand in candidates:
        if cand.lower() in lowered:
            return lowered[cand.lower()]
    return None


def check_mapping(entity_map: dict, keys: list[str]) -> tuple[list[tuple], list[str]]:
    rows, used = [], set()
    for fname, spec in entity_map.items():
        hit = resolve(spec["candidates"], keys)
        if hit:
            used.add(hit.lower())
        rows.append((fname, spec.get("type", "string"), bool(spec.get("required")), hit))
    unused = [k for k in keys if k.lower() not in used]
    return rows, unused


def main(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    field_map = load_field_map()
    session = requests.Session()
    session.headers.update({"Accept": "application/json"})

    md = ["# API profile", "", f"Base URL: `{config.BASE_URL}`", ""]
    failed = False
    for endpoint in config.ENDPOINTS:
        entity = config.entity_name(endpoint)
        try:
            records = normalize_records(fetch_json(session, endpoint), endpoint)
        except Exception as exc:
            md += [f"## {endpoint}", "", f"**FETCH FAILED:** {exc}", ""]
            failed = True
            continue
        prof = profile_records(records)
        keys = list(prof)
        rows, unused = check_mapping(field_map.get(entity, {}), keys)

        md += [f"## {endpoint}  ({len(records)} rows)", ""]
        md += ["| key | types | null rate | distinct | sample |", "|---|---|---|---|---|"]
        for k, p in prof.items():
            md.append(
                f"| `{k}` | {p['types']} | {p['null_rate']} | {p['distinct']} | {p['sample']} |"
            )
        md += [
            "",
            "**field_map resolution**",
            "",
            "| canonical field | type | required | matched key |",
            "|---|---|---|---|",
        ]
        for fname, ftype, req, hit in rows:
            if hit:
                matched = f"`{hit}`"
            else:
                matched = "❌ MISSING" if req else "(not in API)"
                failed = failed or req
            md.append(f"| `{fname}` | {ftype} | {'yes' if req else ''} | {matched} |")
        if unused:
            md += ["", "Unmapped API keys (add to `field_map` if useful): "
                   + ", ".join(f"`{k}`" for k in unused)]
        md.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(md), encoding="utf-8")
    print("\n".join(md))
    print(f"\nWrote {OUT}")
    if failed:
        print("\nRequired fields unmapped -> edit vars.field_map in dbt_project/dbt_project.yml")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
