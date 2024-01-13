declare
  v_cnt number := 0;
begin
  -- компиляция синонимов другой схемы не работает не под sys или до 11.2.0.3 (и то с определенным патчем)
  -- поэтому пересоздаем инвалиды вручную
  if user != 'SYS' and not (   dbms_db_version.version > 11
                            or (dbms_db_version.version = 11 and dbms_db_version.release >= 2)) then
    for rec in ( select 'CREATE OR REPLACE '||
                        case when s.owner = 'PUBLIC' then 'PUBLIC ' end ||
                        'SYNONYM ' ||
                        case when s.owner != 'PUBLIC' then s.owner||'.' end ||
                        case when s.synonym_name!=upper(s.synonym_name) then '"'||s.synonym_name||'"' else s.synonym_name end ||
                        ' for '|| table_owner||'.'||
                        case when s.table_name!=upper(s.table_name) then '"'||s.table_name||'"' else s.table_name end ||
                        case when db_link is not null then '@'||db_link end as cmd
                   from dba_objects t,
                        dba_synonyms s
                  where 1=1
                    --and t.owner in () -- provide owner list
                    and t.owner not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
                        'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
                    and s.table_owner not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
                        'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
                    and t.owner != user
                    and t.object_type = 'SYNONYM'
                    and s.owner = t.owner
                    and s.synonym_name = t.object_name
                    and status = 'INVALID'
                    )
    loop
      v_cnt := v_cnt + 1;
      dbms_output.put_line(rec.cmd);
      begin
        execute immediate rec.cmd;
      exception when others then
        dbms_output.put_line(sqlerrm(sqlcode));
      end;
    end loop;
  end if;

  for rec in (
  with invalids as (select t.owner, t.object_name, t.object_type, rownum rn
                      from dba_objects t
                     where 1=1
                     --and t.owner in () -- provide owner list
                       and owner not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
                        'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
                       and object_type in ('SYNONYM', 'TYPE', 'PACKAGE', 'FUNCTION', 'PROCEDURE', 'VIEW', 'PACKAGE BODY', 'TYPE BODY', 'TRIGGER')
                       and status = 'INVALID'
  ) select t.owner,
           t.object_name,
           t.object_type,
           case when t.object_type = 'SYNONYM' and t.owner = 'PUBLIC'
             then 'ALTER PUBLIC SYNONYM ' ||
              case when t.object_name!=upper(t.object_name) then '"'||t.object_name||'"' else t.object_name end || ' COMPILE'
           else 'ALTER ' || REPLACE(object_type,' BODY','') || ' ' || owner || '.' ||
              case when t.object_name!=upper(t.object_name) then '"'||t.object_name||'"' else t.object_name end ||
             DECODE(object_type,'PACKAGE BODY',' COMPILE BODY','TYPE BODY', ' COMPILE BODY', ' COMPILE')
           end as cmd
      from invalids t
  order by case
             when object_type='SYNONYM' then 1
             -- types used from other types
             when object_type='TYPE' and exists (select 1
                                                   from invalids i,
                                                        dba_dependencies d
                                                  where d.referenced_type = t.object_type
                                                    and d.referenced_name = t.object_name
                                                    and i.object_type = d.type
                                                    and i.rn != t.rn
                                                    and i.owner = d.owner
                                                    and i.object_name = d.name
                                                    and d.type = 'TYPE') then 2
             when object_type='TYPE' then 3
             -- view used by other objects
             when object_type='VIEW' and exists (select 1
                                                   from invalids i,
                                                        dba_dependencies d
                                                  where d.referenced_type = t.object_type
                                                    and d.referenced_name = t.object_name
                                                    and i.object_type = d.type
                                                    and i.rn != t.rn
                                                    and i.owner = d.owner
                                                    and i.object_name = d.name
                                                    and d.type in ('VIEW', 'FUNCTION', 'PROCEDURE', 'PACKAGE')) then 4
             -- specs used by other pkg spec
             when object_type='PACKAGE' and exists (select 1
                                                      from invalids i,
                                                           dba_dependencies d
                                                     where d.referenced_type = t.object_type
                                                       and d.referenced_name = t.object_name
                                                       and i.object_type = d.type
                                                       and i.rn != t.rn
                                                       and i.owner = d.owner
                                                       and i.object_name = d.name
                                                       and d.type = t.object_type) then 5
             when object_type='PACKAGE' then 6
             -- function used by other functions
             when object_type='FUNCTION' and exists (select 1
                                                       from invalids i,
                                                            dba_dependencies d
                                                      where d.referenced_type = t.object_type
                                                        and d.referenced_name = t.object_name
                                                        and i.object_type = d.type
                                                        and i.rn != t.rn
                                                        and i.owner = d.owner
                                                        and i.object_name = d.name
                                                        and d.type = t.object_type) then 7
             when object_type='FUNCTION' then 8
             -- procedures used by other procedures
             when object_type='PROCEDURE' and exists (select 1
                                                        from invalids i,
                                                             dba_dependencies d
                                                       where d.referenced_type = t.object_type
                                                         and d.referenced_name = t.object_name
                                                         and i.object_type = d.type
                                                         and i.rn != t.rn
                                                         and i.owner = d.owner
                                                         and i.object_name = d.name
                                                         and d.type = t.object_type) then 9
             when object_type='PROCEDURE' then 10
             when object_type='VIEW' then 11
             when object_type='PACKAGE BODY' then 12
             when object_type='TYPE BODY' then 13
             when object_type='TRIGGER' then 14
             else 100 end asc
  )
  loop

    v_cnt := v_cnt + 1;
    dbms_output.put_line(rec.cmd);
    begin
      execute immediate rec.cmd;
    exception when others then
      dbms_output.put_line(sqlerrm(sqlcode));
    end;

  end loop;

  dbms_output.put_line('Total: ' || v_cnt);

end;
/
