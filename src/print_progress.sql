exec dbms_application_info.set_action('progress: &1 / &2');
host echo -en "\r Progress: &1 / &2        "
