# dblistman

[![DOI](https://zenodo.org/badge/78542503.svg)](https://doi.org/10.5281/zenodo.16271143)

`dblistman.pl` is a perl script for managing Listserv subscribers via email using SQL queries and data files as data sources. 

## Description

`dblistman.pl` simplifies data-driven management of Listserv subscribers. It uses the Listserv email interface to subscribe and unsubscribe list members or review a list. It uses data files and SQL query results as data sources for subscription and unsubscription requests. 

When unsubscribing, it can unsubscribe all members from a list, every person in a query result from a single list, or unsubscribe every person in a query result from all lists on the Listserv host.

## Requirements

`dblistman.pl` requires these modules/services:

- Perl packages Getopt, MIME, strict, DBI and File.
- Credentials to a Listserve list management account.
- A `sendmail` binary in the PATH.
- Credentials to a MySQL server if using a query.
- A POSIX host

## Installation

Clone the git repository from https://github.com/pbchase/dblistman or unzip the release zip file from https://github.com/pbchase/dblistman/releases. Follow the configuration instructions to configure it.

## Configuration

To configure the script, create a `dblistman.rc` with credentials to the Listerve interface. The file contents will look much like this:

```
list_server, lists.example.org
list_owner, jane_doe@example.org
list_owner_password, my-secret
```

If you plan to use queries to get the membership input data, you'll need a `mysql.rc` much like this one:

```
mysql_server, mysql.example.org
mysql_username, my_db_user
mysql_password, another-secret-password
```

## Usage

### Review
In its most basic form, `dblistman.pl` can enumerate the list members by emailing the list membership to the list_owner listed in `dblistman.rc`:

```sh
./dblistman.pl -c -r -l department-list-l
```

### Unsubscribe
Unsubscribe all members from a list with the command below. This is a common prelude to repopulating a list.

```sh
./dblistman.pl -c -u -l department-list-l
```

### Subscribe from a file
To subscribe new or existing members using a file of names and email addresses, construct a file, `department-list-l.txt`, like this:

```
jane@example.org Jane Doe
john@example.org John Q Public
benjamin@capitol.gov Benjamin Franklin
```

Then use it to subscribe everyone in the file to the list. The -L option uses the basename of the file name as the list name.

```sh
./dblistman.pl -c -s -f department-list-l.txt -L
```

### Subscribe from a database query
To subscribe new or existing members from the output of a query, construct a file, `department-list-l.sql`, like this query of the `redcap_user_information` table of a REDCap host.

```
select concat(user_email, " <", user_firstname, " ", user_lastname, ">") as subscriber
from redcap_user_information
where datediff(now(), user_lastactivity) < 90 
and user_suspended_time is NULL 
order by lower(user_lastname) asc;
```

The query should return a single output column with email address, a space and the subscribers name enclosed in "<>".

Then use the query to subscribe everyone in the query result to the list. The -L option uses the basename of the file name as the list name.

```bash
./dblistman.pl -c -s -d ctsi_redcap -q department-list-l.sql -L
```

### Combining commands

It's simple enough to combine `dblistman.pl` commands in one script. Place the commands in the right sequence and use a 5 second delay between them to assure they arrive in the proper order.

```bash
#!/bin/bash
./dblistman.pl -c -u -l department-list-l
sleep 5
./dblistman.pl -c -s -d redcap -q department-list-l.sql -L
```

### Test mode vs. Commit mode
The `-c` option used in each of the above commands is telling `dblistman.pl` to _commit_--to send the commands. The _default_ mode is `-t`--to test what the code would do. If we run the [Subscribe from a file](./#subscribe-from-a-file) example above the test switch, the command looks like this

```sh
./dblistman.pl -t -s -f department-list-l.txt -L
```

While the planned email output is echoed to the screen:

```
Content-Type: multipart/alternative; boundary="----------=_1752834735-13172-0"
Content-Transfer-Encoding: binary
MIME-Version: 1.0
X-Mailer: MIME-tools 5.509 (Entity 5.509)
From: jane_doe@example.org
To: listserv@lists.example.org
Subject: subscribe department-list-l

This is a multi-part message in MIME format...

------------=_1752834735-13172-0
Content-Type: text/plain
Content-Disposition: inline
Content-Transfer-Encoding: 7bit

QUIET ADD department-list-l DD=ddname IMPORT PW=my-secret
//ddname DD *
jane@example.org Jane Doe
john@example.org John Q Public
benjamin@capitol.gov Benjamin Franklin
/*

------------=_1752834735-13172-0--
```
