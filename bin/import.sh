#!/bin/sh
db=$1
file=$2
if [ ! -f "${file}" ]; then
  echo "file '${file}' not found"
elif [ ! -r "${file}" ]; then
  echo "file '${file} not readable"
else
  echo "import ${file}"
  xml=$(unzip -p ${file} content.xml)
  echo " \
         SET search_path TO ods_import;
         SELECT import_ods_xml('$(basename ${file})'::text, '${xml}'::xml) \
       " | psql ${db}
fi

