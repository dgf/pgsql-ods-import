# PostgreSQL OpenDocument 1.0 Spreadsheet Import Function

## Requirements

    apt-get install unzip zip

## Usage

create schema with tables and functions

    psql dbname -f schema.sql

import ODS file

    bin/import.sh dbname example.ods

review imported ODS tables

    echo "SELECT columns FROM ods_import.ods_file_content;" | psql dbname

                                                             columns
    -------------------------------------------------------------------------------------------------------------------------
     {1,2016-02-27,"text one"}
     {2,2016-02-27,"another text"}
     {3,2016-02-27,"third one"}
     {"Local PostgreSQL Documentation",file:///usr/share/doc/postgresql-doc-9.4/html/index.html}
     {"Local PostgreSQL Extension Directory",file:///usr/share/postgresql/9.4/extension}
     {"OpenDocument 1.0 Specification",http://www.oasis-open.org/committees/download.php/19274/OpenDocument-v1.0ed2-cs1.pdf}

## Development

    make

    help:            # list all targets
    create:          # create database
    clean:           # drop schema
    install: clean   # install schema
    import: $(ods)   # import ODS
    example: install # clean schema and import example.ods

