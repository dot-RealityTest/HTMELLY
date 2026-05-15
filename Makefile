.PHONY: run refresh verify open reports

run:
	cd viewer && ./script/build_and_run.sh

verify:
	cd viewer && ./script/build_and_run.sh --verify

refresh:
	cd viewer && ./script/regenerate_reports.py

open:
	open "viewer/dist/HTTMELY.app"

reports:
	open reports/index.html
