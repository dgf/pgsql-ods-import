CREATE SCHEMA ods_import;
SET search_path TO ods_import;

CREATE TABLE ods_file (
  id serial PRIMARY KEY,
  name text NOT NULL,
  created_at timestamp DEFAULT now()
);

CREATE TABLE ods_table (
  id serial PRIMARY KEY,
  name text NOT NULL,
  headers text[],
  file_id int REFERENCES ods_file(id)
);

CREATE TABLE ods_row (
  id serial PRIMARY KEY,
  columns text[],
  table_id int REFERENCES ods_table(id)
);

CREATE VIEW ods_file_content AS (
  SELECT
    f.name AS file_name
  , t.name AS table_name
  , r.columns
  FROM ods_file f
  JOIN ods_table t ON t.file_id = f.id
  JOIN ods_row r ON r.table_id = t.id
);

CREATE FUNCTION xpath_attribute_value(document xml, element text, attribute text, namespaces text[])
  RETURNS text AS $$
  DECLARE x xml[];
  BEGIN
    SELECT xpath('//' || element || '/@' || attribute, document, namespaces) INTO x;
    IF cardinality(x) = 0 OR x[1] IS NULL THEN
      RAISE 'element "%" without "%" attribute: %', element, attribute, document;
    END IF;
    RETURN x[1];
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION xpath_attribute_exist(document xml, element text, attribute text, namespaces text[])
  RETURNS boolean AS $$
  DECLARE x xml[];
  BEGIN
    SELECT xpath('//' || element || '/@' || attribute, document, namespaces) INTO x;
    IF cardinality(x) = 0 OR x[1] IS NULL THEN
      RETURN false;
    ELSE
      RETURN true;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION xpath_element_count(document xml, element text, namespaces text[])
  RETURNS int AS $$
  DECLARE x xml[];
  BEGIN
    SELECT xpath('//' || element, document, namespaces) INTO x;
    RETURN cardinality(x);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION xpath_element_text(document xml, element text, namespaces text[])
  RETURNS text AS $$
  DECLARE x xml[]; t text;
  BEGIN
    SELECT xpath('//' || element || '//text()', document, namespaces) INTO x;
    IF cardinality(x) = 1 THEN
      RETURN x[1];
    ELSIF cardinality(x) = 0 THEN
      RETURN null;
    ELSE -- return the first text
      FOREACH t IN ARRAY x
      LOOP
        IF char_length(trim(t)) > 0 THEN
          RETURN t;
        END IF;
      END LOOP;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION xml_decode(INOUT value text) AS $$
  BEGIN
    value := replace(value, '&gt;', '>');
    value := replace(value, '&lt;', '<');
    value := replace(value, '&amp;', '&');
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_ods_row_columns(headers int, row_xml xml, namespaces text[])
  RETURNS text[] AS $$
  DECLARE
    columns xml[];
    column_xml xml;
    column_number int := 1;
    column_value text;
    row_columns text[] := '{}';
    repeat_count int;
    repeat_number int;
  BEGIN
    SELECT xpath('//table:table-cell', row_xml, namespaces) INTO columns;
    FOREACH column_xml IN ARRAY columns
    LOOP
      EXIT WHEN column_number > headers;

      column_value := xml_decode(xpath_element_text(column_xml, 'text:p', namespaces));
      row_columns := row_columns || column_value;
      column_number := column_number + 1;

      IF xpath_attribute_exist(column_xml, 'table:table-cell', 'table:number-columns-repeated', namespaces) THEN
        repeat_count := xpath_attribute_value(column_xml, 'table:table-cell', 'table:number-columns-repeated', namespaces);
        FOR repeat_number IN 2..repeat_count
        LOOP
          EXIT WHEN column_number > headers;

          column_number := column_number + 1;
          row_columns := row_columns || column_value;
        END LOOP;
      END IF;
    END LOOP;
    RETURN row_columns;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION import_ods_table(ods_id int, table_xml xml, namespaces text[])
  RETURNS int AS $$
  DECLARE
    t ods_table;
    table_name text;
    table_rows xml[];
    row_xml xml;
    header_columns xml[];
    header_xml xml;
    header_name text;
    table_headers text[];
    header_count int;
    empty_row text[];
    row_number int;
    row_columns text[];
  BEGIN
    table_name := xpath_attribute_value(table_xml, 'table:table', 'table:name', namespaces);
    SELECT xpath('//table:table-row', table_xml, namespaces) INTO table_rows;

    -- read header columns
    row_xml := table_rows[1];
    SELECT xpath('//table:table-cell', row_xml, namespaces) INTO header_columns;
    FOREACH header_xml IN ARRAY header_columns
    LOOP
      header_name := xml_decode(xpath_element_text(header_xml, 'text:p', namespaces));
      IF header_name IS NULL THEN
        EXIT;
      ELSE
        table_headers := table_headers || header_name;
      END IF;
    END LOOP;

    -- create table entry
    header_count = cardinality(table_headers);
    empty_row := array_fill(NULL::text, ARRAY[header_count]);
    INSERT INTO ods_table (file_id, name, headers) VALUES (ods_id, table_name, table_headers) RETURNING * INTO t;

    -- import content rows
    FOR row_number IN 2..cardinality(table_rows)
    LOOP
      row_xml := table_rows[row_number];
      EXIT WHEN xpath_attribute_exist(row_xml, 'table:table-row', 'table:number-rows-repeated', namespaces);

      row_columns := get_ods_row_columns(cardinality(table_headers), row_xml, namespaces);
      EXIT WHEN row_columns = empty_row;

      INSERT INTO ods_row (table_id, columns) VALUES (t.id, row_columns);
    END LOOP;

    RETURN t.id;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION import_ods_xml(ods_name text, content xml)
  RETURNS int AS $$
  DECLARE
    f ods_file;
    tables xml[];
    table_xml xml;
    namespaces text[] = ARRAY[
      ARRAY['office', 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'],
      ARRAY['table', 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'],
      ARRAY['text', 'urn:oasis:names:tc:opendocument:xmlns:text:1.0']];
  BEGIN
    INSERT INTO ods_file(name) VALUES (ods_name) RETURNING * INTO f;
    SELECT xpath('//office:document-content/office:body/office:spreadsheet/table:table', content, namespaces) INTO tables;
    FOREACH table_xml IN ARRAY tables
    LOOP
      PERFORM import_ods_table(f.id, table_xml, namespaces);
    END LOOP;
    RETURN f.id;
  END;
$$ LANGUAGE plpgsql;

