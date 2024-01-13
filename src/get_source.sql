variable v_owner varchar2(128 char)
variable v_name varchar2(128 char)
variable v_type varchar2(128 char)
variable v_spool_to_git varchar2(20)
begin
  :v_owner := upper('&1');
  :v_name := upper('&2');
  :v_type := upper('&3');
  :v_spool_to_git := lower('&spool_to_git');
end;
/

-- сначала чекнем что такой объект есть
declare
 l_owner varchar2(128 char) := :v_owner;
 l_name varchar2(128 char) := :v_name;
 l_type varchar2(128 char) := :v_type;
 l_dummy number;
begin
  if l_owner is null then
    raise_application_error(-20001, 'Parameter #1 "owner" is null');
  elsif l_name is null then
    raise_application_error(-20001, 'Parameter #2 "name" is null');
  elsif l_type is null then
    raise_application_error(-20001, 'Parameter #3 "type" is null');
  elsif l_type not in ('TYPE', 'TYPE BODY', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER',
                       'FUNCTION', 'PROCEDURE', 'VIEW', 'GRANT', 'GRANTS',
                       'SEQUENCE', 'SYNONYM', 'MVIEW', 'MATERIALIZED VIEW') then
    raise_application_error(-20001, 'Unsupported type ' || l_type);
  end if;
  if l_type = 'MVIEW' then
    l_type := 'MATERIALIZED VIEW';
  end if;

  if l_type in ('GRANT', 'GRANTS') then
    select 1 into l_dummy
      from dba_tab_privs
     where owner = l_owner
       and upper(table_name) = l_name
       and rownum = 1;
  elsif l_type in ('SYNONYM') then
    select 1 into l_dummy
      from dba_synonyms
     where table_owner = l_owner
       and upper(table_name) = l_name
       and rownum = 1;
  else
    select 1 into l_dummy
      from dba_objects
     where upper(object_name) = l_name
       and object_type = l_type
       and owner = l_owner;
  end if;

exception
  when no_data_found then
    raise_application_error(-20001, l_type ||' ' || l_owner || '.' || l_name || ' not found!');
end;
/

-- определим куда спулить
column file_name new_value file_name noprint
select case when :v_spool_to_git = 'true'
        -- актуализация кода - спулим прямо в репозиторий
         then :v_git_path || :v_owner || '/' || case :v_type
                                               when 'PACKAGE' then 'PACKAGES'
                                               when 'PACKAGE BODY' then 'PACKAGES'
                                               when 'FUNCTION' then 'FUNCTIONS'
                                               when 'PROCEDURE' then 'PROCEDURES'
                                               when 'TYPE' then 'TYPES'
                                               when 'TYPE BODY' then 'TYPES'
                                               when 'TRIGGER' then 'TRIGGERS'
                                               when 'VIEW' then 'VIEWS'
                                               when 'GRANT' then 'GRANTS'
                                               when 'GRANTS' then 'GRANTS'
                                               when 'SEQUENCE' then 'SEQUENCES'
                                               when 'SYNONYM' then 'SYNONYMS'
                                               when 'MATERIALIZED VIEW' then 'MVIEWS'
                                               when 'MVIEW' then 'MVIEWS'
                                               else 'OTHERS' end ||
              '/' || :v_name || '.' || case when :v_type like '% BODY' then 'BODY.' end
       else 'backup/'|| :v_owner ||'.' || :v_name ||'.' || case when :v_type like '% BODY' then 'BODY.' end
      end || 'sql' as file_name
from dual;

spool &file_name


-- Вытащим сорсы
declare
 l_owner varchar2(128 char) := :v_owner;
 l_name varchar2(128 char) := :v_name;
 l_type varchar2(128 char) := :v_type;
 l_found boolean := false;
 l_text varchar2(32767);
 l_dummy number;
begin
  if l_type in ('TYPE', 'TYPE BODY', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'FUNCTION', 'PROCEDURE') then

    -- если в коде есть амперсанд
    begin
      select 1
        into l_dummy
        from dba_source
       where owner = l_owner
         and name = l_name
         and type = l_type
         and text like '%'||chr(38)||'%'
         and rownum = 1;

      dbms_output.put_line('set define off');
      dbms_output.put_line('');
    exception
      when no_data_found then null;
    end;

    for rec in (select case when line = 1 then 'create or replace ' || regexp_replace(text, '(\s){1} +', '\1')
                         else text
                       end as text
                  from dba_source
                 where owner = l_owner
                   and name = l_name
                   and type = l_type
                 order by line asc)
    loop
      if not l_found then l_found := true; end if;
      dbms_output.put_line(replace(replace(rec.text, chr(13)), chr(10)));
    end loop;

  elsif l_type = 'VIEW' then
    declare
      v_source long;
      l_lenght number;
    begin
      select text_length
        into l_lenght
        from dba_views
       where owner = l_owner
         and view_name = l_name;
      l_found := true;
      dbms_output.put_line('create or replace view ' || l_owner || '.' || l_name);
      dbms_output.put_line('(');
      for rec2 in (select lower(column_name) as column_name,
                          column_id,
                          max(column_id) over() as count_cols
                     from dba_tab_cols
                    where owner = l_owner
                      and table_name = l_name
                  order by column_id asc)
      loop
        if rec2.column_id < rec2.count_cols then
          dbms_output.put_line('  ' || rec2.column_name || ',');
        else
          dbms_output.put_line('  ' || rec2.column_name);
        end if;
      end loop;
      dbms_output.put_line(')');
      dbms_output.put_line('AS');
      if l_lenght <= 32767 then
        select text
          into v_source
          from dba_views
         where owner = l_owner
           and view_name = l_name;
        -- long to varchar
        l_text := substr(v_source, 1, l_lenght);
        -- sqlplus не переваривает пустые строки во вьюхах - убираем их
        l_text := regexp_replace(l_text, chr(10)||'(\s*'||chr(10)||')+', chr(10));
        l_text := regexp_replace(l_text, chr(13)||chr(10)||'(\s*'||chr(13)||chr(10)||')+', chr(13)||chr(10));
        l_text := rtrim(l_text, chr(10));
        l_text := rtrim(l_text, chr(13));
        dbms_output.put_line(l_text);

      -- возьня с длинным long
      else
        declare
          l_clob   clob;
          l_sql    varchar2(1000) := 'select text from dba_views where owner = :v_owner and view_name = :v_name';
          l_cur    binary_integer;
          l_piece  varchar2(32767);
          l_plen   integer := 32767;
          l_tlen   integer := 0;

          l_offset integer := 1;
          l_pos    integer;
          l_length integer;
          l_amount integer;
        begin
          l_cur := dbms_sql.open_cursor;
          dbms_lob.createtemporary(l_clob, true);
          dbms_sql.parse(l_cur, l_sql, dbms_sql.native);
          dbms_sql.bind_variable(l_cur, ':v_owner', l_owner);
          dbms_sql.bind_variable(l_cur, ':v_name', l_name);
          dbms_sql.define_column_long(l_cur, 1);
          l_dummy := dbms_sql.execute_and_fetch(l_cur);
          loop
            dbms_sql.column_value_long(l_cur, 1, 32767, l_tlen, l_piece, l_plen);
           -- sqlplus не переваривает пустые строки во вьюхах - убираем их.
           -- Тут может между кусками что-то остаться, надо проверять
            l_piece := regexp_replace(l_piece, chr(10)||'(\s*'||chr(10)||')+', chr(10));
            l_piece := regexp_replace(l_piece, chr(13)||chr(10)||'(\s*'||chr(13)||chr(10)||')+', chr(13)||chr(10));
            l_piece := rtrim(l_piece, chr(10));
            l_piece := rtrim(l_piece, chr(13));
            dbms_lob.writeappend(l_clob, length(l_piece), l_piece);
            l_tlen := l_tlen + 32767;
            exit when l_plen < 32767;
          end loop;
          dbms_sql.close_cursor(l_cur);

          -- построчный вывод лоба
          l_length := dbms_lob.getlength(l_clob);
          loop
            exit when l_offset > l_length;
            l_pos := dbms_lob.instr(l_clob, chr(10), l_offset);
            if l_pos = 0 then
              l_amount := l_length - l_offset + 1;
            else
              l_amount := l_pos - l_offset;
            end if;
            dbms_output.put_line(dbms_lob.substr(l_clob, l_amount, l_offset));
            l_offset := l_offset + l_amount + 1;
          end loop;
          dbms_lob.freetemporary(l_clob);
        exception when others then
          if dbms_sql.is_open(l_cur) then dbms_sql.close_cursor(l_cur); end if;
          begin dbms_lob.freetemporary(l_clob); exception when others then null; end;
          raise;
        end;
      end if;

    exception
      when no_data_found then
        l_found := false;
    end;

  elsif l_type in ('MATERIALIZED VIEW', 'MVIEW') then
    declare
      v_source long;
      l_lenght number;
      l_tbs    varchar2(128 char);
      l_build_mode varchar2(30 char);
      l_refresh_mode varchar2(30 char);
      l_refresh_method varchar2(30 char);
    begin
      select query_len, build_mode, refresh_method, refresh_mode
        into l_lenght, l_build_mode, l_refresh_method, l_refresh_mode
        from dba_mviews
       where owner = l_owner
         and mview_name = l_name;
      l_found := true;

      dbms_output.put_line('drop materialized view ' || l_owner || '.' || l_name || ';');
      dbms_output.put_line('create materialized view ' || l_owner || '.' || l_name);
      dbms_output.put_line('(');
      for rec2 in (select lower(column_name) as column_name,
                          column_id,
                          max(column_id) over() as count_cols
                     from dba_tab_cols
                    where owner = l_owner
                      and table_name = l_name
                  order by column_id asc)
      loop
        if rec2.column_id < rec2.count_cols then
          dbms_output.put_line('  ' || rec2.column_name || ',');
        else
          dbms_output.put_line('  ' || rec2.column_name);
        end if;
      end loop;
      dbms_output.put_line(')');

      begin
        select tablespace_name
          into l_tbs
          from dba_tables
         where owner = l_owner
           and table_name = l_name;
      exception
        when no_data_found then l_tbs := null;
      end;
      if l_tbs is not null then
        dbms_output.put_line('TABLESPACE ' || l_tbs);
      end if;
      dbms_output.put_line('BUILD ' || l_build_mode );
      dbms_output.put_line('REFRESH ' || l_refresh_method || ' ON ' || l_refresh_mode);
      dbms_output.put_line('AS');
      if l_lenght <= 32767 then
        select query
          into v_source
          from dba_mviews
         where owner = l_owner
           and mview_name = l_name;
        -- long to varchar
        l_text := substr(v_source, 1, l_lenght);
        -- sqlplus не переваривает пустые строки во вьюхах - убираем их
        l_text := regexp_replace(l_text, chr(10)||'(\s*'||chr(10)||')+', chr(10));
        l_text := regexp_replace(l_text, chr(13)||chr(10)||'(\s*'||chr(13)||chr(10)||')+', chr(13)||chr(10));
        l_text := rtrim(l_text, chr(10));
        l_text := rtrim(l_text, chr(13));
        dbms_output.put_line(l_text);

      -- возьня с длинным long
      else
        declare
          l_clob   clob;
          l_sql    varchar2(1000) := 'select query from dba_mviews where owner = :v_owner and mview_name = :v_name';
          l_cur    binary_integer;
          l_piece  varchar2(32767);
          l_plen   integer := 32767;
          l_tlen   integer := 0;
          l_offset integer := 1;
          l_pos    integer;
          l_length integer;
          l_amount integer;
        begin
          l_cur := dbms_sql.open_cursor;
          dbms_lob.createtemporary(l_clob, true);
          dbms_sql.parse(l_cur, l_sql, dbms_sql.native);
          dbms_sql.bind_variable(l_cur, ':v_owner', l_owner);
          dbms_sql.bind_variable(l_cur, ':v_name', l_name);
          dbms_sql.define_column_long(l_cur, 1);
          l_dummy := dbms_sql.execute_and_fetch(l_cur);
          loop
            dbms_sql.column_value_long(l_cur, 1, 32767, l_tlen, l_piece, l_plen);
           -- sqlplus не переваривает пустые строки во вьюхах - убираем их.
           -- Тут может между кусками что-то остаться, надо проверять
            l_piece := regexp_replace(l_piece, chr(10)||'(\s*'||chr(10)||')+', chr(10));
            l_piece := regexp_replace(l_piece, chr(13)||chr(10)||'(\s*'||chr(13)||chr(10)||')+', chr(13)||chr(10));
            l_piece := rtrim(l_piece, chr(10));
            l_piece := rtrim(l_piece, chr(13));
            dbms_lob.writeappend(l_clob, length(l_piece), l_piece);
            l_tlen := l_tlen + 32767;
            exit when l_plen < 32767;
          end loop;
          dbms_sql.close_cursor(l_cur);

          -- построчный вывод лоба
          l_length := dbms_lob.getlength(l_clob);
          loop
            exit when l_offset > l_length;
            l_pos := dbms_lob.instr(l_clob, chr(10), l_offset);
            if l_pos = 0 then
              l_amount := l_length - l_offset + 1;
            else
              l_amount := l_pos - l_offset;
            end if;
            dbms_output.put_line(dbms_lob.substr(l_clob, l_amount, l_offset));
            l_offset := l_offset + l_amount + 1;
          end loop;
          dbms_lob.freetemporary(l_clob);
        exception when others then
          if dbms_sql.is_open(l_cur) then dbms_sql.close_cursor(l_cur); end if;
          begin dbms_lob.freetemporary(l_clob); exception when others then null; end;
          raise;
        end;
      end if;
      dbms_output.put_line('/');
      dbms_output.put_line('');

      for rec in (select comments
                    from dba_mview_comments
                   where owner = l_owner
                     and mview_name = l_name)
      loop
        dbms_output.put_line('COMMENT ON MATERIALIZED VIEW ' || l_owner || '.' || l_name || ' IS '''|| rec.comments|| ''';');
      end loop;
      dbms_output.put_line('');

      -- indx
      for rec in (select owner,
                        index_name,
                        tablespace_name,
                        case when uniqueness='UNIQUE' then 'UNIQUE ' else null end as uniq
                    from dba_indexes
                   where table_owner = l_owner
                     and table_name = l_name
                     and table_type = 'TABLE'
                     and index_type = 'NORMAL')
      loop
        dbms_output.put_line('CREATE ' || rec.uniq || 'INDEX ' || rec.owner || '.' || rec.index_name || ' ON ' || l_owner || '.' || l_name);
        dbms_output.put('(');
        for rec2 in (select column_name,
                            column_position,
                            max(column_position) over() as count_cols
                       from dba_ind_columns
                      where index_owner = rec.owner
                        and index_name = rec.index_name
                        and table_owner = l_owner
                        and table_name = l_name
                     order by column_position asc)
        loop
          if rec2.column_position < rec2.count_cols then
            dbms_output.put(rec2.column_name || ',');
          else
            dbms_output.put(rec2.column_name||')');
            dbms_output.new_line;
          end if;
        end loop;
        dbms_output.put_line('TABLESPACE ' || rec.tablespace_name);
        dbms_output.put_line('/');
      end loop;
      dbms_output.put_line('');

      -- если есть гранты
      begin
        select 1
          into l_dummy
          from dba_tab_privs
         where owner = l_owner
           and upper(table_name) = l_name
           and rownum = 1;
        dbms_output.put_line('@'||:v_git_path||l_owner||'/GRANTS/' || l_name || '.sql');
      exception
        when no_data_found then null;
      end;
      dbms_output.put_line('');

    exception
      when no_data_found then
        l_found := false;
    end;
  elsif l_type in ('GRANT', 'GRANTS') then

    for rec in (select distinct grantee,
                       owner,
                       case when upper(table_name) != table_name then '"'||table_name||'"' else table_name end as name,
                       privilege,
                       grantable
                  from dba_tab_privs
                 where owner = l_owner
                   and upper(table_name) = l_name
                order by grantee, case when privilege='SELECT' then 1
                                       when privilege='INSERT' then 2
                                       when privilege='UPDATE' then 3
                                       when privilege='DELETE' then 4
                                       when privilege='EXECUTE' then 5
                                       when privilege='REFERENCES' then 6
                                       when privilege='ALTER' then 7
                                       when privilege='QUERY REWRITE' then 8
                                       when privilege='INDEX' then 9
                                       when privilege='ON COMMIT REFRESH' then 10
                                       when privilege='FLASHBACK' then 11
                                       when privilege='DEBUG' then 12
                                       else ora_hash(privilege, 200)+20 end, grantable)
    loop
      dbms_output.put_line('GRANT ' || rec.privilege || ' ON ' || rec.owner ||'.'|| rec.name ||
                           ' TO ' || rec.grantee || case when rec.grantable='YES' then ' WITH GRANT OPTION' end);
      dbms_output.put_line('/');
    end loop;

  elsif l_type = 'SEQUENCE' then
    for rec in (select min_value, max_value, increment_by, cycle_flag, order_flag, cache_size
                  from dba_sequences
                 where sequence_owner = l_owner
                   and sequence_name = l_name)
    loop
      l_found := true;
      l_text := 'CREATE SEQUENCE ' || l_owner || '.' || l_name;
      if rec.min_value != 1 then
        l_text := l_text || ' START WITH ' || rec.min_value;
      end if;
      if rec.max_value != 999999999999999999999999999 then
        l_text := l_text || ' MAXVALUE ' || rec.max_value;
      end if;
      if rec.increment_by != 1 then
        l_text := l_text || ' INCREMENT BY ' || rec.increment_by;
      end if;
      if rec.cycle_flag = 'Y' then
        l_text := l_text || ' CYCLE';
      end if;
      if rec.cache_size = 0 then
        l_text := l_text || ' NOCACHE';
      else
        l_text := l_text || ' CACHE ' || rec.cache_size;
      end if;
      if rec.order_flag = 'Y' then
        l_text := l_text || ' ORDER';
      end if;
      dbms_output.put_line(l_text);
    end loop;

  elsif l_type = 'SYNONYM' then
    for rec in (select case when upper(synonym_name) != synonym_name then '"'||synonym_name||'"' else synonym_name end as synonym_name,
                       table_owner,
                       owner,
                       case when upper(table_name) != table_name then '"'||table_name||'"' else table_name end as table_name,
                       db_link
                  from dba_synonyms
                 where table_owner = l_owner
                   and upper(table_name) = l_name
                 order by owner )
    loop
      l_text := 'CREATE OR REPLACE ';
      if rec.owner = 'PUBLIC' then
        l_text := l_text || 'PUBLIC SYNONYM ';
      else
        l_text := l_text || 'SYNONYM ' || rec.owner ||'.';
      end if;
      l_text := l_text || rec.synonym_name || ' FOR ' || rec.table_owner || '.' || rec.table_name;
      if rec.db_link is not null then
        l_text := l_text || '@' || rec.db_link;
      end if;
        dbms_output.put_line(l_text);
        dbms_output.put_line('/');
    end loop;
  end if;

  if l_found then
    if l_type in ('MVIEW', 'MATERIALIZED VIEW') then
      return;
    end if;
    dbms_output.put_line('/');
    if l_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW', 'TYPE', 'TYPE BODY') then
      dbms_output.put_line('');
      dbms_output.put_line('show errors');
    end if;
  elsif l_type not in ('SYNONYM', 'GRANT', 'GRANTS') then
    raise_application_error(-20001, l_type ||' ' || l_owner || '.' || l_name || ' not found!');
  end if;
end;
/

spool off
