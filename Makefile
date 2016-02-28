dbName = ods_check

help:            # list all targets
	@grep '^[^: ]*:' Makefile | sed -e 's/#:\s*//'

create:          # create database
	createdb $(dbName)

clean:           # drop schema
	echo "DROP SCHEMA ods_import CASCADE;" | psql $(dbName)

install: clean   # install schema
	psql $(dbName) -f schema.sql

import: $(ods)   # import ODS
	bin/import.sh $(dbName) $(shell pwd)/$(ods)

example: install # clean schema and import example.ods
	make import ods=example.ods
	echo "SELECT * FROM ods_import.ods_file_content;" | psql $(dbName)

