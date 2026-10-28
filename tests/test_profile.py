from extract_load.profile_api import check_mapping, load_field_map, profile_records, resolve


def test_resolve_is_case_insensitive_and_ordered():
    assert resolve(["appointmentId", "id"], ["ID", "AppointmentID"]) == "AppointmentID"
    assert resolve(["x"], ["y"]) is None


def test_profile_counts_nulls_and_types():
    p = profile_records([{"a": 1, "b": None}, {"a": 2}])
    assert p["a"]["null_rate"] == 0.0
    assert p["b"]["null_rate"] == 1.0
    assert p["a"]["types"] == {"int": 2}


def test_field_map_in_dbt_project_is_well_formed():
    fm = load_field_map()
    assert {"appointments", "patients", "users", "roles"} <= set(fm)
    for entity, fields in fm.items():
        for name, spec in fields.items():
            assert spec["candidates"], f"{entity}.{name} has no candidates"
            assert spec.get("type", "string") in {
                "string", "int", "decimal", "boolean", "date", "timestamp"}


def test_roles_mapping_matches_provider_sample():
    # Provider's published /roles sample: id, projectName, roleName, isActive, createdOn
    rows, _ = check_mapping(
        load_field_map()["roles"], ["id", "projectName", "roleName", "isActive", "createdOn"]
    )
    assert all(hit for *_, hit in rows)
