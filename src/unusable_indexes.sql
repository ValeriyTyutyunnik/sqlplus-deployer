declare
  v_cnt number := 0;
begin
  for rec in (
    select owner,
           index_name,
           null as partition_name,
           null as subpartition_name,
           status,
           'alter index '||owner||'.'||index_name||' rebuild' as cmd
      from all_indexes ip
     where 1=1
       -- and owner in () --rovide owner list
       and owner not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
           'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
       and status ='UNUSABLE'
    union all
    select index_owner as owner,
           index_name,
           partition_name,
           null as subpartition_name,
           status,
           'alter index '||index_owner||'.'||index_name||' rebuild partition '||partition_name as cmd
      from all_ind_partitions ip
     where 1=1
       -- and index_owner in () --rovide owner list
       and index_owner not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
           'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
       and status != 'USABLE'
    union all
    select index_owner as owner,
           index_name,
           partition_name,
           subpartition_name,
           status,
           'alter index '||index_owner||'.'||index_name||' rebuild subpartition '||subpartition_name as cmd
      from all_ind_subpartitions
     where (index_owner, index_name) IN  (select owner, index_name
                                            from all_part_indexes
                                           where 1=1
                                             -- and owner in () -- provide owner list
                                             and owner not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB',
                                                 'ANONYMOUS','OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
                                         )
       and status != 'USABLE'
    )
  loop
    v_cnt := v_cnt + 1;
    if v_cnt = 1 then
      dbms_output.put_line('Unusable indexes list:');
    end if;
    if '&1' = 'rebuild_unusable' then
      dbms_output.put_line(rec.cmd);
      execute immediate rec.cmd;
    else
      dbms_output.put_line('-- '||rec.owner||'.'||rec.index_name||
                           case when rec.partition_name is not null then ' partition: '||rec.partition_name end ||
                           case when rec.subpartition_name is not null then ' subpartition: '||rec.subpartition_name end
                           );
      dbms_output.put_line(rec.cmd||';');
    end if;
  end loop;

  if v_cnt = 0 then
    dbms_output.put_line('No unusable indexes!');
  elsif '&1' = 'rebuild_unusable' then
    dbms_output.put_line('Unusable indexes fixed :' || v_cnt);
  else
    dbms_output.put_line('Unusable indexes count :' || v_cnt);
  end if;
end;
/
