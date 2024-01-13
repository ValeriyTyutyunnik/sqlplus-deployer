/*----------------------------------------------------------
 В этом скрипте менять ничего не нужно.
 Файлы для редактирования:
 1. config.sql - параметры коннектов
 2. global_vars.sql - всякие переменные
 3. backup.sql для указания чего забэкапить
 4. task_to_deploy.sql для выполнения всяких dll и наката скриптов из гита

Скрипт ниже разделен на секции.
В каждой секции (или при выполнении task_to_deploy.sql, backup.sql) параметры SQLPlus могут меняться.
Поэтому при старте каждой секции параметры нужно сбрасывать вызовом @src/reset_main_settings.sql
----------------------------------------------------------*/
set echo off
set define on
set verify off
set feedback off
set line 32767
set pagesize 0
set trimspool on
set sqlprompt ''
set sqlnumber off
set serveroutput off
set heading off
/*-----------------------------------------------
---------------- INIT section -------------------
-----------------------------------------------*/

whenever sqlerror exit sql.sqlcode;
whenever oserror exit;

@config.sql
@global_vars.sql

prompt connecting...
connect &v_user/&v_pwd@&v_tns
undefine v_pwd
alter session set current_schema = &v_user;
timing start total

exec dbms_application_info.set_module('Deployer', 'Init');

-- Разбираем какие секции этого скрипта нужно закомитить. В шапке следующей секции обязательно должен быть конец комментария */
variable v_deploy_mode varchar2(64)
variable v_git_path varchar2(250)
variable v_git_last_ddl varchar2(40)
begin
  :v_deploy_mode := '&1';
  :v_git_path := '&path_main';
  :v_git_last_ddl := '&git_last_ddl_main';
  if lower('&ignore_last_ddl')='true' then
    :v_git_last_ddl := null;
  end if;
end;
/

column backup new_value if_backup noprint
column deploy new_value if_deploy noprint
column compile new_value if_compile noprint
column show_invalids new_value if_show_invalids noprint
column show_unusable new_value if_show_unusable noprint
column rebuild_unusable new_value if_rebuild_unusable noprint
column git_gen new_value if_git_gen noprint
column git_run new_value if_git_run noprint

select
  case when :v_deploy_mode='backup'
    then 'src/null.sql' else 'src/comment.sql' end as backup,
  case when :v_deploy_mode='deploy'
    then 'src/null.sql' else 'src/comment.sql' end as deploy,
  case when :v_deploy_mode in ('deploy', 'compile')
    then 'src/null.sql' else 'src/comment.sql' end as compile,
  case when :v_deploy_mode in ('deploy', 'show_invalids', 'compile')
    then 'src/null.sql' else 'src/comment.sql' end as show_invalids,
  case when :v_deploy_mode in ('deploy', 'show_invalids')
    then 'src/null.sql' else 'src/comment.sql' end as show_unusable,
  case when :v_deploy_mode in ('rebuild_unusable')
    then 'src/null.sql' else 'src/comment.sql' end as rebuild_unusable,
  case when :v_deploy_mode in ('git_upd_gen', 'git_upd')
    then 'src/null.sql' else 'src/comment.sql' end as git_gen,
  case when :v_deploy_mode in ('git_upd_run', 'git_upd')
    then 'src/null.sql' else 'src/comment.sql' end as git_run
from dual;
/*-----------------------------------------------
---------------- BACKUP section -----------------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_backup

define spool_to_git = "false"
exec dbms_application_info.set_action('Backup sources');
whenever sqlerror exit sql.sqlcode;
whenever oserror exit;

prompt Get backup sources..

@backup.sql

undefine spool_to_git
/*-----------------------------------------------
---------------- DEPLOY section -----------------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_deploy

exec dbms_application_info.set_action('Deploy');
column d new_value file_name noprint
select 'deploy_'||to_char(sysdate, 'yyyymmdd-hh24-mi-ss') d from dual;
spool logs/&file_name..log

prompt
prompt Invalids before deploy:
@src/print_invalids.sql

timing start deploy
prompt
prompt deploy begin..

set feedback on
set define off

@task_to_deploy.sql

prompt
prompt deploy ends
timing stop deploy
/*-----------------------------------------------
----------- COMPILE INVALIDS section ------------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_compile

exec dbms_application_info.set_action('Compile invalids');
timing start compile_invalids
prompt
prompt Compiling invalids:

@src/compile_invalids.sql

prompt
timing stop compile_invalids
/*-----------------------------------------------
------------- SHOW INVALIDS section -------------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_show_invalids

exec dbms_application_info.set_action('Show invalids');
prompt
prompt Invalids list now:
@src/print_invalids.sql
/*-----------------------------------------------
------------- SHOW UNUSABLE INDEXES section -------------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_show_unusable

exec dbms_application_info.set_action('Show unusable indexes');
prompt
@src/unusable_indexes.sql 'show_unusable'
/*-----------------------------------------------
------------- REBUILD UNUSABLE INDEXES section -------------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_rebuild_unusable
timing start rebuild_unusable

exec dbms_application_info.set_action('Rebuild unusable indexes');
prompt
@src/unusable_indexes.sql 'rebuild_unusable'
timing stop rebuild_unusable
/*-----------------------------------------------
---------- Git update prepare section -----------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_git_gen
whenever sqlerror exit sql.sqlcode;
whenever oserror exit;

exec dbms_application_info.set_action('Prepare git-update script');
prompt Get sources list..

set termout off
@src/git_update_prepare.sql
set termout on

prompt
prompt Check file make_git_great_again.sql

/*-----------------------------------------------
-------------- Git update section ---------------
-----------------------------------------------*/
@src/reset_main_settings.sql
@&if_git_run

exec dbms_application_info.set_module('Deployer.git-update', 'init');
define spool_to_git = "true"
whenever sqlerror exit sql.sqlcode;
whenever oserror exit;

prompt Update git..

set termout off
@make_git_great_again.sql
set termout on

undefine spool_to_git
/*-----------------------------------------------
------------------ END section ------------------
-----------------------------------------------*/
prompt
timing stop total
exec dbms_application_info.set_action('Done');

@&if_deploy
spool off

/*------------------- EXIT --------------------*/
exit
