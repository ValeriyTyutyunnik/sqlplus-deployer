variable v_owner varchar2(128)
variable v_type varchar2(128)
variable v_susp_grants varchar2(20)
variable v_last_ddl varchar2(30)
begin
  :v_owner := upper('&git_owner');
  :v_type := upper('&git_type');
  if :v_type = 'MVIEW' then
    :v_type := 'MATERIALIZED VIEW';
  end if;
  :v_susp_grants := nvl(lower('&git_susp_grants'), 'false');
  if :v_git_last_ddl is not null and :v_type is null and :v_owner is null then
    :v_last_ddl := :v_git_last_ddl;
  end if;
end;
/

spool make_git_great_again.sql

begin
  dbms_output.put_line('/* AUTO GENERATED SCRIPT. EDIT IF NEEDED BEFORE EXECUTE */');
  dbms_output.put_line('');
end;
/
-- сначала нужно досоздать недостающие каталоги
declare
  v_owner varchar2(128 char) := :v_owner;
  v_type varchar2(128 char) := :v_type;
  v_susp_grants varchar2(20) := :v_susp_grants;
  v_last_ddl date := case when :v_last_ddl is not null then to_date(:v_last_ddl, 'dd.mm.yyyy') else null end;
  v_cnt     number := 0;
  v_text varchar2(1000 char);
begin
  dbms_application_info.set_action('progress 1/2: executing');
  dbms_output.put_line('host echo "Progress: checking folders.."');
  for rec in (with owners as (select username as owner
                                from dba_users
                               where (v_owner is not null and username = v_owner)
                                   or (v_owner is null --and username in () --provide owners list
                                       and username not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
                                           'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
                                       )
                              )
              select t.owner,
                     t.object_type,
                     case t.object_type
                        when 'PACKAGE' then 'PACKAGES'
                        when 'FUNCTION' then 'FUNCTIONS'
                        when 'PROCEDURE' then 'PROCEDURES'
                        when 'TYPE' then 'TYPES'
                        when 'TRIGGER' then 'TRIGGERS'
                        when 'VIEW' then 'VIEWS'
                        when 'GRANT' then 'GRANTS'
                        when 'SEQUENCE' then 'SEQUENCES'
                        when 'SYNONYM' then 'SYNONYMS'
                        when 'MATERIALIZED VIEW' then 'MVIEWS'
                        else 'OTHERS'
                     end as type_folder,
                     count(*) over() total
                from (select distinct o.owner,
                             o.object_type
                        from dba_objects o,
                             owners ow
                       where o.owner = ow.owner
                         and (  (v_type is null and o.object_type in ('TYPE', 'PACKAGE', 'TRIGGER', 'FUNCTION', 'PROCEDURE', 'VIEW', 'SEQUENCE', 'MATERIALIZED VIEW'))
                             or (v_type is not null and v_type != 'SYNONYM' and o.object_type = v_type ))
                         and o.generated = 'N'
                         and o.temporary = 'N'
                         and o.secondary = 'N'
                         and o.subobject_name is null
                         and o.last_ddl_time >= nvl(v_last_ddl, o.last_ddl_time)
                         and o.object_name not like '%TEST%'
                         and o.object_name not like 'TMP/_%' escape '/'
                         and o.object_name not like '%/_TMP/_%' escape '/'
                         and o.object_name not like '%/_TST' escape '/'
                         and o.object_name not like '%/_TMP' escape '/'
                         and o.object_name not like 'SYS/_PLSQL/_%' escape '/'
                         -- wrapped не тащим
                         and not exists (select 1
                                           from dba_source s
                                          where s.owner = o.owner
                                            and s.type = o.object_type
                                            and s.name = o.object_name
                                            and s.line = 1
                                            and instr(lower(s.text), 'wrapped') > 0)
                         union all
                         select distinct table_owner as owner, 'SYNONYM' as object_type
                           from dba_synonyms s,
                                owners ow
                          where s.table_owner = ow.owner
                           and nvl(v_type, 'SYNONYM') = 'SYNONYM'
                           and ( v_last_ddl is null
                                 or exists (select 1
                                              from dba_objects o
                                             where o.owner = s.owner
                                               and o.object_name = s.synonym_name
                                               and o.last_ddl_time >= v_last_ddl ))
                           and s.table_name not like '%TEST%'
                           and s.table_name not like 'TMP/_%' escape '/'
                           and s.table_name not like '%/_TMP/_%' escape '/'
                           and s.table_name not like '%/_TST' escape '/'
                           and s.table_name not like '%/_TMP' escape '/'
                           and s.table_name not like 'SYS/_PLSQL/_%' escape '/'
                         union all
                         select distinct p.owner, 'GRANT'
                           from dba_tab_privs p,
                                owners ow
                          where p.owner = ow.owner
                            and nvl(v_type, 'GRANT') = 'GRANT'
                            and ( v_last_ddl is null
                                 or exists (select 1
                                              from dba_objects o
                                             where o.owner = p.owner
                                               and o.object_name = p.table_name
                                               and o.last_ddl_time >= v_last_ddl ))
                            and v_susp_grants = 'false'
                            and p.table_name not like '%TEST%'
                            and p.table_name not like 'TMP/_%' escape '/'
                            and p.table_name not like '%/_TMP/_%' escape '/'
                            and p.table_name not like '%/_TST' escape '/'
                            and p.table_name not like '%/_TMP' escape '/'
                            and p.table_name not like 'SYS/_PLSQL/_%' escape '/'
                         ) t
                         order by owner, type_folder)
  loop
    if rec.type_folder = 'OTHERS' then
      raise_application_error(-20001, 'Folder for type ' || rec.object_type || ' undefined');
    end if;
    v_cnt := v_cnt+1;
    if v_text is null then
      v_text := 'host mkdir -vp';
    end if;
    v_text := v_text || ' ' || :v_git_path || rec.owner || '/' || rec.type_folder;

    if mod(v_cnt, 4)=0 then
      dbms_output.put_line(v_text);
      v_text := null;
    end if;
  end loop;
  dbms_application_info.set_action('progress 1/2: done');
  dbms_output.put_line(v_text);
  dbms_output.put_line('');
end;
/

-- теперь заспулим команды для актуализации
declare
  v_owner varchar2(128 char) := :v_owner;
  v_type varchar2(128 char) := :v_type;
  v_susp_grants varchar2(20) := :v_susp_grants;
  v_last_ddl date := case when :v_last_ddl is not null then to_date(:v_last_ddl, 'dd.mm.yyyy') else null end;
  v_cnt number := 0;
  v_len number;
begin
  dbms_application_info.set_action('progress 2/2: executing');
  dbms_output.put_line('host echo "Progress: getting sources.."');
  for rec in (with owners as (select username as owner
                                from dba_users
                               where (v_owner is not null and username = v_owner)
                                   or (v_owner is null --and username in () --provide owners list
                                       and username not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
                                           'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
                                       )
                              )
              select t.owner,
                     t.name,
                     t.object_type,
                     count(*) over() total
                from (select o.owner,
                             o.object_name as name,
                             o.object_type
                        from dba_objects o,
                             owners ow
                       where o.owner = ow.owner
                         and (  (v_type is null and o.object_type in ('TYPE', 'PACKAGE', 'TRIGGER', 'FUNCTION', 'PROCEDURE',
                                                                      'VIEW', 'SEQUENCE', 'PACKAGE BODY', 'TYPE BODY', 'MATERIALIZED VIEW'))
                             or (v_type is not null and v_type != 'SYNONYM' and o.object_type = v_type ))
                         and o.generated = 'N'
                         and o.temporary = 'N'
                         and o.secondary = 'N'
                         and o.subobject_name is null
                         and o.last_ddl_time >= nvl(v_last_ddl, o.last_ddl_time)
                         -- wrapped не тащим
                         and not exists (select 1
                                           from dba_source s
                                          where s.owner = o.owner
                                            and s.type = o.object_type
                                            and s.name = o.object_name
                                            and s.line = 1
                                            and instr(lower(s.text), 'wrapped') > 0)
                         union all
                         select distinct table_owner as owner, table_name as name, 'SYNONYM' as object_type
                           from dba_synonyms s,
                                owners ow
                          where s.table_owner = ow.owner
                           and nvl(v_type, 'SYNONYM') = 'SYNONYM'
                           and ( v_last_ddl is null
                                 or exists (select 1
                                              from dba_objects o
                                             where o.owner = s.owner
                                               and o.object_name = s.synonym_name
                                               and o.last_ddl_time >= v_last_ddl ))
                         union all
                         select distinct p.owner, p.table_name as name, 'GRANT' as object_type
                           from dba_tab_privs p,
                                owners ow
                          where p.owner = ow.owner
                            and nvl(v_type, 'GRANT') = 'GRANT'
                            and ( v_last_ddl is null
                                 or exists (select 1
                                              from dba_objects o
                                             where o.owner = p.owner
                                               and o.object_name = p.table_name
                                               and o.last_ddl_time >= v_last_ddl ))
                            and v_susp_grants = 'false'
                         ) t
                         where t.name not like '%TEST%'
                           and t.name not like 'TMP/_%' escape '/'
                           and t.name not like '%/_TMP/_%' escape '/'
                           and t.name not like '%/_TST' escape '/'
                           and t.name not like '%/_TMP' escape '/'
                           and t.name not like 'SYS/_PLSQL/_%' escape '/'
                         order by owner, name, object_type)
  loop
    if v_len is null then
      v_len := length(to_char(rec.total))*3;
    end if;
    v_cnt := v_cnt + 1;
    if v_cnt = 1 or mod(v_cnt, 5) = 0 then
      dbms_output.put_line('@src/print_progress.sql ' || v_cnt || ' ' || rec.total);
    end if;
    dbms_output.put_line('@src/get_source.sql ''' || rec.owner || ''' ''' || rec.name || ''' ''' || rec.object_type || '''');
  end loop;
  dbms_output.put_line('host echo -e "\rProgress: ' || rpad('done', v_len) ||'"');
  dbms_application_info.set_action('finishing');
end;
/

spool off
