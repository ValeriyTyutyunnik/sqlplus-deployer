declare
  v_cnt number := 0;
begin
  for rec in (
    select t.owner,
           t.object_name,
           t.object_type,
           max(length(owner)) over() len_owner,
           max(length(object_name)) over() len_name,
           max(length(object_type)) over() len_type,
           (select e.line||':'||e.position||'-'||e.text
              from dba_errors e
            where e.owner = t.owner
              and e.name = t.object_name
              and e.type = t.object_type
              and e.attribute = 'ERROR'
              and e.sequence = 1
              ) first_err
      from dba_objects t
     where 1=1
       -- and owner in () -- provide owner list
       and owner not in ('SYS','SYSTEM','OUTLN','DIP','DMSYS','TSMSYS','DBSNMP','WMSYS','EXFSYS','CTXSYS','XDB','ANONYMOUS',
                         'OLAPSYS','ORDSYS','ORDPLUGINS','MDSYS','MDDATA','SYSMAN','ORACLE_OCM','APPQOSSYS','PERFSTAT')
       and object_type in ('SYNONYM', 'TYPE', 'PACKAGE', 'FUNCTION', 'PROCEDURE', 'VIEW', 'PACKAGE BODY', 'TYPE BODY', 'TRIGGER')
       and status = 'INVALID'
  )
  loop

    v_cnt := v_cnt + 1;

    if v_cnt = 1 then
      dbms_output.put_line(rpad('-', rec.len_owner+rec.len_name+rec.len_type+70, '-'));
      dbms_output.put(rpad(' OWNER ', rec.len_owner+2, ' '));
      dbms_output.put(rpad('| OBJECT_NAME ', rec.len_name+4, ' '));
      dbms_output.put(rpad('| OBJECT_TYPE ', rec.len_type+4, ' '));
      dbms_output.put(rpad('| FIRST ERROR ', 70, ' '));
      dbms_output.new_line;
      dbms_output.put_line(rpad('-', rec.len_owner+rec.len_name+rec.len_type+70, '-'));
    end if;

    dbms_output.put(rpad(' ' ||  rec.owner, rec.len_owner+2,' '));
    dbms_output.put(rpad('| ' || rec.object_name, rec.len_name+4,' '));
    dbms_output.put(rpad('| ' || rec.object_type, rec.len_type+4,' '));
    dbms_output.put('| ' || rec.first_err);
    dbms_output.new_line;

  end loop;
  dbms_output.put_line('Total: ' || v_cnt);
end;
/
