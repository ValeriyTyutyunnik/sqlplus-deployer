/* Add commands to save current code from DB

After exec check file backup/OWNER.NAME.DATETIME..sql

Examples:
alter session set current_schema owner_schema
@src/get_source.sql 'owner_schema' 'package_name' 'package'
@src/get_source.sql 'owner_schema' 'package_name' 'package body'

-- если нужно спулить не в backup, а прямо в локальный репозиторий
define spool_to_git="true"
*/

