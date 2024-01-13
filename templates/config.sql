-- Параметры подключений:

-- если по TNS не подключается - ставь переменную окружения TNS_ADMIN с путем к файлу tnsnames.ora
define v_tns = 'main'
define v_user = ''
define v_pwd = ''
-- для сокрытия пароля, но не всякая консоль скроет ввод
--accept v_pwd CHAR PROMPT 'Password:  ' HIDE

-------------------------

-- Параметры частичной актуализации:

define git_susp_grants='false'
-- Если нужно актуализировать только определенный тип и/или схему.
define git_owner=''
define git_type=''
-- true: игнорировать git_last_ddl (true/false) (полная актуализация)
define ignore_last_ddl='false'

-------------------------
