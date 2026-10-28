DBT = cd dbt_project && dbt
TARGET ?= dev

.PHONY: install profile extract extract-dry deps validate build test docs lint test-py

install:
	pip install -r requirements-dev.txt

profile:            ## Profile live API payloads, write docs/api_profile.md
	python -m extract_load.profile_api

extract-dry:        ## Fetch API and save JSON snapshots locally (no Snowflake)
	python -m extract_load.extract --skip-load --snapshot-dir data/snapshots

extract:            ## Fetch API and load into Snowflake RAW
	python -m extract_load.extract

deps:
	$(DBT) deps

validate:           ## Fail if a required field mapping matches nothing in RAW
	$(DBT) run-operation assert_field_coverage --target $(TARGET)

build:              ## Models + tests + unit tests in DAG order
	$(DBT) build --target $(TARGET)

test:
	$(DBT) test --target $(TARGET)

docs:
	$(DBT) docs generate --target $(TARGET) && $(DBT) docs serve

lint:
	ruff check . && sqlfluff lint dbt_project/models dbt_project/tests

test-py:
	pytest -q
