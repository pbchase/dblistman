select concat(user_email, " <", user_firstname, " ", user_lastname, ">") as subscriber
from redcap_user_information
where datediff(now(), user_lastactivity) < 90 
and user_suspended_time is NULL 
order by lower(user_lastname) asc;
