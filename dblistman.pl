#!/usr/bin/perl -w
# dblistman
# Database List Manager: reads list subscribers from an SQL database and generates
# listserv subscription commands
# 2005-07-22 pbc: Created based on gatorlink-do-personnel-sync
# 2005-08-01 pbc: fixed problem with listname extraction from file names

use strict;
use DBI;
use File::Slurp;

my ($target, $dbh, $sql, @sql, $sth, @row, $rd, $rc);
my ($sql_server, $sql_username, $sql_password, $line, $temp);
my ($list_server, $list_owner, $list_owner_password);
my ($body, $subscriber_line, $subscribers);

open(AUTH, "mysql.rc");
#open(AUTH, "mysql-maintenance.rc");
while ($line = <AUTH>) {
    if (($temp) = ($line =~ /^mysql_server\t(.+)/)) {
        $sql_server = $1;
    }
    if (($temp) = ($line =~ /^mysql_username\t(.+)/)) {
        $sql_username = $1;
    }
    if (($temp) = ($line =~ /^mysql_password\t(.+)/)) {
        $sql_password = $1;
    }
}
close AUTH;

open(CONFIG, "dblistman.rc");
while ($line = <CONFIG>) {
    if (($temp) = ($line =~ /^list_server\t(.+)/)) {
        $list_server = $1;
    }
    if (($temp) = ($line =~ /^list_owner\t(.+)/)) {
        $list_owner = $1;
    }
    if (($temp) = ($line =~ /^list_owner_password\t(.+)/)) {
        $list_owner_password = $1;
    }
}
close CONFIG;

my ($opt, $output);
use vars qw($self $debug $listname $database $sqlfile $subscriberfile);
($self = $0) =~ s!.*/!!;        # get program name

# setup and filter the message
($opt) = parse_args();

sub usage {
        die <<EOF
usage: $self [flags]

options:
       -l listname
       -d database to query
       -q File with SQL statement that outputs 'emailaddress <Full Name>'
       -f File with subscribers in format 'emailaddress <Full Name>'
       -L extract listname from SQL or text filename
       -A unsubscribe all users in query from all lists on listserv
       -s generate subscribe commands
       -u unsubscribe all users from a list
       -U unsubscribe all users in query from a list
       -r generate review command
       -o run other sql commands in file specified by -q
       -t test command (default)
       -c commit request
       -v verbose output
       -h print this usage info

EOF
}

sub parse_args {
    use Getopt::Std;

    my ($optstring, %opt);

    $optstring = "l:d:q:f:LAsuUrotcvh";

    getopts($optstring, \%opt) or usage();

    if (! $opt{c}) {
	$opt{t} = 1;
    }

    if ($opt{l}) {
	$listname = $opt{l};
    }
    if ($opt{d}) {
	$database = $opt{d};
    }
    if ($opt{q}) {
	$sqlfile = $opt{q};
	if ($opt{L}) {
	    $listname = $opt{q};
	    $listname =~ s/.*\/([^\/]+)$/$1/;
	    $listname =~ s/^([^\.]+).*/$1/;
	}
    }
    if ($opt{f}) {
	$subscriberfile = $opt{f};
	if ($opt{L}) {
	    $listname = $opt{f};
	    $listname =~ s/.*\/([^\/]+)$/$1/;
	    $listname =~ s/^([^\.]+).*/$1/;
	}
    }

    # Shall we show debugging info?
    if ($opt{v}) {
        $debug = 1;
    } else {
        $debug = 0;
    }

    # show help if we have not been told what to do
    $opt{h} = 1 unless ($opt{s} || $opt{u}  || $opt{U} || $opt{r} || $opt{A});

    # we need to know a few things to subscribe
    if ($opt{s}) {
	if ( (($opt{l} || $opt{L}) && ($opt{d} && $opt{q})) ) {
	    debug("listname: $listname, database: $database, sqlfile: $sqlfile");
	} elsif ( (($opt{l} || $opt{L}) && $opt{f}) ) {
	    debug("listname: $listname subscriberfile: $subscriberfile");
	} else {
	    print STDERR "To subscribe, you must specify -l (or -L) and -d and -q (or -f) switches with appropriate values\n";
	    usage();
	}
    }

    # we need to know a few things to unsubscribe
    if ($opt{U}) {
	if ( (($opt{l} || $opt{L} || $opt{A}) && ($opt{d} && $opt{q})) ) {
	    debug("listname: $listname, database: $database, sqlfile: $sqlfile");
	} elsif ( (($opt{l} || $opt{L} || $opt{A}) && $opt{f}) ) {
	    debug("listname: $listname subscriberfile: $subscriberfile");
	} else {
	    print STDERR "To unsubscribe individuals, you must specify -l, -L, or -A as well as -d and -q (or -f) switches with appropriate values\n";
	    usage();
	}
    }

    # we need to know a few things to unsubscribe
    if ($opt{u}) {
	if ( ($opt{l} || $opt{L} || $opt{A} ) && ( $opt{l} || $opt{f} || $opt{q} ) ) {
	    debug("listname: $listname");
	} else {
	    print STDERR "To unsubscribe, you must specify -l, -L, or -A and -l, -q or -f switches with appropriate values\n";
	    usage();
	}
    }

    # we need to know a few things to review
    if ($opt{r}) {
	if (($opt{l} || $opt{L}) && ($opt{l} || $opt{q}|| $opt{f}) ) {
	    debug("listname: $listname");
	} else {
	    print STDERR "To review, you must specify -l or -L with either -f -q switches with appropriate values\n";
	    usage();
	}
    }

    if ($opt{o} && !$opt{q}) {
	print STDERR "-o requires the -q switch to specify a file of sql commands.\n";
	usage();
    } elsif ($opt{o} && $opt{q}) {
	debug("additional sql commands will be executed");
    }

    if ($opt{h}) {
        usage();
    }
    return (\%opt);
}

sub debug {
    print STDERR $self, ': ', @_, "\n" if ($debug);
}

sub my_exit {
    debug(@_);
    exit;
}

if ($opt->{s} || $opt->{U} || $opt->{A}) {

    # build header for message body
    if ($opt->{U}) {
	$body = "QUIET DELETE $listname DD=ddname PW=$list_owner_password\n";
    } elsif ($opt->{A}) {
	debug("deleting users from all lists");
	$body = "QUIET DELETE * DD=ddname PW=$list_owner_password\n";
    } elsif ($opt->{s}) {
	$body = "QUIET ADD $listname DD=ddname IMPORT PW=$list_owner_password\n";
    }
    $body .= "//ddname DD *\n";

    if ($opt->{f}) {
	open(SUBSCRIBER, $subscriberfile);
	while ($subscriber_line = <SUBSCRIBER>) {
	    $body .= $subscriber_line;
	    ++$subscribers;
	}
	close(SUBSCRIBER);
    } elsif ($opt->{d} && $opt->{q}) {

	# make sql connection
	debug("connection to $sql_server as $sql_username");
	$target = "DBI:mysql:$database:$sql_server";
	debug("target is $target");
	$dbh = DBI->connect($target, $sql_username, $sql_password) or die "Cannot connect to $target\n";

	# get Sql for list subscribers
	($sql, @sql) = (split(/;/, read_file($sqlfile)));

	debug($sql);
	$sth = $dbh->prepare($sql);
	$sth->execute;

	$subscribers = 0;
	while (($subscriber_line) = $sth->fetchrow_array) {
	    $body .= $subscriber_line . "\n";
	    ++$subscribers;
	    #debug("found subscriber: $subscriber_line");
	}

    } else {
	debug("I don't know what to do with this request.  It must be a bug.");
    }

    # build footer for message body
    $body .= "/*\n";

    # send the mail
    if ($subscribers > 0) {
	if ($opt->{U}) {
	    mail_listserver($list_owner, $list_server, "unsubscribe $listname", $body);
	} elsif ($opt->{A}) {
	    mail_listserver($list_owner, $list_server, "unsubscribe *", $body);
	} elsif ($opt->{s}) {
	    mail_listserver($list_owner, $list_server, "subscribe $listname", $body);
	}

	# Run other sql commands from sql file if any exist
	if ($opt->{o}) {
	    foreach $sql (@sql) {
		debug($sql);
		$sth = $dbh->prepare($sql);
		if ($opt->{t}) {

		} elsif ($opt->{c}) {
		    $sth->execute;
		}
	    }
	}
    } else {
	debug("Subscriber count is $subscribers.  There is no content for this request.  Doing nothing.");
    }

    if ($opt->{q}) {
	# Clean up our connections
	$dbh->disconnect();
    }
} elsif ($opt->{u}) {
    $body = "quiet del $listname *";
    mail_listserver($list_owner, $list_server, $body, "$body\n");
} elsif ($opt->{r}) {
    $body = "review $listname";
    mail_listserver($list_owner, $list_server, $body, "$body\n");
} else {
    debug("I have nothing to do.  Must be a bug");
}


sub mail_listserver {

    my ($list_owner, $list_server, $subject, $body) = @_;
    my ($top);

    use MIME::Entity;
    # Create the top-level, and set up the mail headers:
    $top = MIME::Entity->build(Type    =>"multipart/alternative",
			       From    => $list_owner,
			       To      => "listserv\@$list_server",
			       Subject => $subject);

    # Attach body
    $top->attach(Data        => $body,
		 Encoding    => "7bit");


    if ($opt->{t}) {
	$top->print(\*STDOUT);
    } elsif ($opt->{c}) {
	# Send it:
	open MAIL, "| /usr/lib/sendmail -t -oi -oem" or die "open: $!";
	$top->print(\*MAIL);
	close MAIL;
    }

}

