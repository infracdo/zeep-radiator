package Radius::AuthZeep;
@ISA = qw(Radius::AuthGeneric Radius::SqlDb);
use Radius::AuthGeneric;
use Radius::SqlDb;
use DBI;
use strict;

%Radius::AuthZeep::ConfigKeywords = 
('AccountingTable'        => 
 ['string', 'name of the table that will be used to store accounting records. Defaults to "ACCOUNTING". If AccountingTable is defined to be an empty string, all accounting requests will be accepted and acknowledged, but no accounting data will be stored. You must also define at least one AcctColumnDef before accounting data will be stored.', 1],
 'AuthSelect'             => 
 ['string', 'SQL select statement that will be used to find and fetch the password and possibly check items and reply items for the user who is attempting to log in. You can use the special formatting characters. %0 is replaced with the quoted and escaped user name. The first column returned is expected to be the password; the second is the check items (if any) and the third is the reply items (if any) (you can change this expectation with the AuthColumnDef parameter). ', 1],
 'AuthSelectParam'        => 
 ['stringarray', 'This optional parameter enables the use of bound variables (where supported by the SQL server) and query caching. If you specify one or more AuthSelectParam parameters, they will be used in order to replace parameters named with a question mark (\`?\') in AuthSelect, and the query will be cached for future reuse by the SQL server. Only the first QueryCacheSize queries will be cached.', 1],
 'PostAuthSelectHook'     => 
 ['hook', 'Perl function that will be run during the authentication process. The hook will be called after the AuthSelect results have been received, and before Radiator has processed the attributes it is interested in.', 2],
 'EncryptedPassword'      => 
 ['flag', 'This parameter should be set if and only if your AuthSelect statement will return a bare Unix encrypted password, and you are not using AuthColumnDef. Encrypted passwords cannot be used with CHAP or MSCHAP authentication. If the encrypted password column for a user is NULL in the database, then any password will be accepted for that user.', 1],
 'AcctSQLStatement'       => 
 ['stringarray', 'This parameter allows you to execute arbitrary SQL statements each time an accounting request is received. You might want to do it to handle processing in addition to the normal inserts defined by AcctColumnDef, or you might want to construct a much more complicated SQL statement than AcctColumnDef can handle. You only need this if the accounting definitions provided by AcctColumnDef are not powerful enough. %0 is replaced by the quoted and escaped user name.', 1],
 'AuthSQLStatement'       => 
 ['stringarray', 'This parameter allows you to execute arbitrary SQL statements each time an authentication request is received, but before authentication is done.  %0 is replaced by the quoted and escaped user name', 1],
 'AuthColumnDef'          => 
 ['stringhash', 'This optional parameter allows you to change the way Radiator interprets the result of the AuthSelect statement. If you don\'t specify any AuthColumnDef parameters, Radiator will assume that the first column returned is the password; the second is the check items (if any) and the third is the reply items (if any). If you specify any AuthColumnDef parameters, Radiator will use the column definitions you provide.<p>You can specify any number of AuthColumnDef parameters, one for each interesting field returned by AuthSelect. The general format is: <p><pre><code>AuthColumnDef n, attributename, type[, formatted]</code></pre>', 1],
 'AcctColumnDef'          => 
 ['stringarray', 'AcctColumnDef is used to define which attributes in accounting requests are to be inserted into AccountingTable, and it also specifies which column they are to be inserted into, and optionally the data type of that column. The general form is <p><pre><code>Column,Attribute[,Type][,Format]</code></pre>', 1],
 'AcctInsertQuery'        => 
 ['string', 'This optional parameter allows you to customise the exact form of the insert query used to insert accounting data.', 1],
 'NullPasswordMatchesAny' => 
 ['flag', 'Normally, a NULL password in the SQL table will match any submitted password. By disabling this option, NULL passwords will not match any submitted password, causing every authentication request for that user to be REJECTED.', 1],
 'GroupMembershipQuery'   => 
 ['string', 'This optional parameter defines an SQL query which will be used to determine which user group a user is a member of, in order to implement the Group check item. Special characters are supported. ', 1],
 'GroupMembershipQueryParam'        => 
 ['stringarray', 'This optional parameter enables the use of bound variables (where supported by the SQL server) and query caching in the GroupMembershipQuery. If you specify one or more GroupMembershipQueryParam parameters, they will be used in order to replace parameters named with a question mark (\`?\') in GroupMembershipQuery, and the query will be cached for future reuse by the SQL server. Only the first QueryCacheSize queries will be cached.', 1],
 'AcctTotalSinceQuery'    => 
 ['string', 'This optional parameter defines an SQL query which will be used to determine the total of session times from a certain time until now for a given user. Special characters are supported. ', 1],
 'AcctTotalQuery'         => 
 ['string', 'This optional parameter defines an SQL query which will be used to determine the total of session times from a certain time until now for a given user. Special characters are supported. %0 is replaced by the user name being checked. %1 is replaced by the Unix epoch time in seconds in the start time of the query. It is expected to return a single field containing the total session time in seconds', 1],
 'AcctTotalOctetsSinceQuery' =>
 ['string', 'This optional parameter defines an SQL query which will be used to determine the total of octets from a certain time until now for a given user. Special characters are supported. %0 is replaced by the user name being checked. %1 is replaced by the Unix epoch time in seconds of the start time of the query. It is expected to return a single field containing the total octets.', 1],
 'AcctTotalOctetsQuery' =>
 ['string', 'This optional parameter defines an SQL query which will be used to determine the total of octets for a given user. Special characters are supported. %0 is replaced by the user name being checked. It is expected to return a single field containing the total octets.', 1],
 'AcctTotalGigawordsSinceQuery' =>
 ['string', 'This optional parameter defines an SQL query which will be used to determine the total of gigawords from a certain time until now for a given user. Special characters are supported. %0 is replaced by the user name being checked. %1 is replaced by the Unix epoch time in seconds of the start time of the query. It is expected to return a single field containing the total gigawords.', 1],
 'AcctTotalGigawordsQuery' =>
 ['string', 'This optional parameter defines an SQL query which will be used to determine the total of gigawords for a given user. Special characters are supported. %0 is replaced by the user name being checked. It is expected to return a single field containing the total gigawords.', 1],

 'CreateEAPFastPACQuery'         => 
 ['string', 'This optional parameter defines an SQL query which will be used to create and save an EAP-FAST PAC to the database', 1],
 'GetEAPFastPACQuery'         => 
 ['string', 'This optional parameter defines an SQL query which will be used to retrieve an EAP-FAST PAC from the database', 1],
 );

# RCS version number of this module
$Radius::AuthZeep::VERSION = '$Revision$';

#####################################################################
# Do per-instance configuration check
# This is called by Configurable just before activate
sub check_config
{
    my ($self) = @_;

    $self->Radius::AuthGeneric::check_config();
    $self->Radius::SqlDb::check_config();
    return;
}

#####################################################################
sub activate
{
    my ($self) = @_;

    $self->Radius::AuthGeneric::activate;
    $self->Radius::SqlDb::activate;

    return;
}

#####################################################################
# Do per-instance default initialization
# This is called by Configurable during Configurable::new before
# the config file is parsed. Its a good place initalze 
# instance variables
# that might get overridden when the config file is parsed.
sub initialize
{
    my ($self) = @_;

    $self->Radius::AuthGeneric::initialize;
    $self->Radius::SqlDb::initialize;

    $self->{AccountingTable} = 'accounting';
    $self->{AuthSelect} = 'select password from subscribers where username=%0';
    $self->{NasSelect} = 'select 1 from allowed_nas_mac_address where called_station_id=%0';
    $self->{SessionSelect} = 'select acctinputoctets, acctoutputoctets, acctsessiontime, called_station_id from accounting where acctsessionid=%0';
    $self->{QueryDataLimits} = 'select session_limit, remaining_session_time, bytes_limit, remaining_bytes from subscribers where username=%0';
    $self->{AcctInsertQuery} = 'insert into %0 (%1) values (%2)';
    $self->{AcctUpdateQuery} = 'update %0 set %1 where acctsessionid=%2';
    $self->{ApAcctUpdateQuery} = 'update ap_accounting set totalinputoctets=totalinputoctets + (%0), totaloutputoctets=totaloutputoctets + (%1), totalsessiontime=totalsessiontime + (%2), last_updated=now() where called_station_id=%3';
    $self->{NullPasswordMatchesAny} = 1;

    return;
}

#####################################################################
# Verifies if csid has permission to access
# and rejects access if not permitted.
# Returns 1 to reject, 0 to allow access.
# This function is called during every access request
sub is_not_allowed_nas # rejects user if nas is not allowed
{
    my ($self, $p) = @_;
    my ($called_station_id) = split /:/, $p->getAttrByNum($Radius::Radius::CALLED_STATION_ID);
    return 1 unless $called_station_id; # if csid not found, reject user
    my $qcalled_station_id = $self->quote($called_station_id); # store quoted called_station_id to variable for use later in function
    my $q = &Radius::Util::format_special($self->{NasSelect}, $p, $self, $qcalled_station_id);
    my $sth = $self->prepareAndExecute($q);
    return 1 unless $sth; # if null, reject user
    my @row = $self->getOneRow($sth);
    $sth->finish();
    return 1 if (!$row[0]); # if not found, reject user
    return 0;
}

#####################################################################
# Verifies if user has reached assigned limit 
# and rejects access if reached.
# Returns 0 to reject, 1 to allow access.
# This function is called during every access request
sub is_user_limits_reached # rejects user if limit reached
{
    my ($self, $p) = @_;
    my $qusername_nq = $p->getUserName(); # store unquoted username to variable for use later in function
    # return 0 if ( $qusername_nq eq 'anonymous'); # allow anonymous users
    return 1 if (!defined($qusername_nq) || $qusername_nq eq ''); # reject empty users
    my $qusername = $self->quote($qusername_nq); # store quoted username to variable for use later in function
    my $q = &Radius::Util::format_special($self->{QueryDataLimits}, $p, $self, $qusername); # store user details to variable for use later in function
    my $sth = $self->prepareAndExecute($q);
    return 1 unless $sth; # if not found, reject user
	my @row = $self->getOneRow($sth); # session_limit, remaining_session_time, bytes_limit, remaining_bytes
	$sth->finish();
    my $dataleft = $row[1];
    $self->log($main::LOG_DEBUG, "[ZEEP] user $qusername_nq remaining data left: $dataleft ", $p);

    my $limittype = 2; # 1 if time based, 2 if data based // TODO REVISIT: replace static with dynamic value from DB
    my $timeleft = 100; # // TODO REVISIT: replace static with dynamic value from DB
    
    if ($limittype eq 1 ) 
    {
        return 1 if ($timeleft <= 0 );
    } elsif ($limittype eq 2 ) {
        return 1 if ($dataleft <= 0 );
    }

    return 0;
}

#####################################################################
# Retrieves current session values from accounting table
# Returns acctinputoctets, acctoutputoctets, acctsessiontime, called_station_id of current user session
# This function is called during every alive/stop accounting request
sub get_current_values 
{
    my ($self, $p, $qacctsessionid) = @_;
    my $q = &Radius::Util::format_special($self->{SessionSelect}, $p, $self, $qacctsessionid);
    my $sth = $self->prepareAndExecute($q);
    return undef unless $sth; # if query execution fails, return null
    my @row = $self->getOneRow($sth);
    $sth->finish();
    return @row ? @row : undef; # return values if array is not empty
}

#####################################################################
# Handle a request
# This function is called for each packet. $p points to a Radius::
# packet
# REVISIT:should we fork before handling. There might be long timeouts?
sub handle_request
{
    my ($self, $p, $dummy, $extra_checks) = @_;

    $self->log($main::LOG_DEBUG, "Handling with $self->{log_class_identifier}", $p);
    return ($main::IGNORE, "Ignored due to IgnoreAuthentication")
	if $self->{IgnoreAuthentication} 
           && $p->code eq 'Access-Request';
    return ($main::IGNORE, "Ignored due to IgnoreAccounting")
	if $self->{IgnoreAccounting} 
           && $p->code eq 'Accounting-Request';

    if ($p->code eq 'Access-Request' || $self->{AuthenticateAccounting})
    {
		# If AuthSQLStatement is set, parse the strings and execute them
		if (defined $self->{AuthSQLStatement})
		{
			my $user_name = $p->getUserName();
			$user_name = $self->quote($user_name);
			map {$self->do(Radius::Util::format_special($_, $p, $self, $user_name))} @{$self->{AuthSQLStatement}};
		}

		# Short circuit for no authentication
		return ($main::REJECT, 'Authentication disabled')
			if $self->{AuthSelect} eq '';

		return ($main::REJECT_IMMEDIATE, 'CSID is not allowed')
			if  $self->is_not_allowed_nas($p);

		return ($main::REJECT_IMMEDIATE, 'User limits reached')
			if  $self->is_user_limits_reached($p);

		# The default behaviour in AuthGeneric is fine for this
		return $self->SUPER::handle_request($p, $p->{rp}, $extra_checks);
    }
    elsif ($p->code eq 'Accounting-Request')
    {
		# Short circuits for no accounting
		return ($main::ACCEPT, 'Accounting not stored')
			if (!defined $self->{AcctColumnDef} 
			|| $self->{AccountingTable} eq '')
			&& !defined $self->{AcctSQLStatement};

		my $status_type = $p->getAttrByNum($Radius::Radius::ACCT_STATUS_TYPE);
		# If we have a HandleAcctStatusTypes and this type is not mentioned
		# Acknowledge it, but dont do anything else with it
		return ($main::ACCEPT, 'Accepted due to HandleAcctStatusTypes')
			if defined $self->{HandleAcctStatusTypes}
			&& !exists $self->{HandleAcctStatusTypes}{$status_type};

		# REVISIT: remove support for AccountingStartsOnly
		# AccountingStopsOnly, and AccountingAlivesOnly in the future.
		# If AccountingStartsOnly is set, only process Starts
		# Acknowledge and drop anything else
		return ($main::ACCEPT, 'Accepted due to AccountingStartsOnly')
			if $self->{AccountingStartsOnly}
			&& $status_type ne 'Start';
		
		# If AccountingStopsOnly is set, only process Stops
		# Acknowledge and drop anything else
		return ($main::ACCEPT, 'Accepted due to AccountingStopsOnly')
			if $self->{AccountingStopsOnly}
			&& $status_type ne 'Stop';

		# If AccountingAlivesOnly is set, only process Alives
		# Acknowledge and drop anything else
		return ($main::ACCEPT, 'Accepted due to AccountingAlivesOnly')
			if $self->{AccountingAlivesOnly}
			&& $status_type ne 'Alive';

		return $self->handle_accounting($p);
    }
    else
    {
	# Send a generic reply on our behalf
	return ($main::ACCEPT, 'Not a relevant request type');
    }
}

#####################################################################
# Find a the named user by looking in the database, and constructing
# User object if we found the named user
# $name is the user name we want
# $p is the current request we are handling
sub findUser
{
    my ($self, $name, $p) = @_;

    # (Re)-connect to the database if necessary, 
    return (undef, 1) unless $self->reconnect;

    my ($original_user_name, $sth);

    if (!$self->{AuthSelectParam})
    {
        # We have to change User-Name in the request so we can 
        # use %n etc in AuthSelect.
        # Make sure all odd characers are escaped. We use the native SQL quote
        # function, but then strip the leading and trailing quotes
        # One day soon, %n will not get this special handling any more
        my $qname = $self->quote($name);
        my $qsname = $qname;
        $qsname =~ s/^'//;
        $qsname =~ s/'$//;

        $original_user_name = $p->getUserName;
        $p->changeUserName($qsname);

        my $q = &Radius::Util::format_special
	    ($self->{AuthSelect}, $p, $self, $qname);
	
        # BUG ALERT: Should we strip placeholders before prepare?
        $sth = $self->prepareAndExecute($q);
        if (!$sth)
        {
            # Change the name back to what it was
			$p->changeUserName($original_user_name);
			return undef;
        }
    }
    else
    {
        # Bind variables can handle all odd characters so there is no need to
        # escape any characters
        my @bind_values = ();
        map { push(@bind_values, Radius::Util::format_special($_, $p, $self, $name)); }  @{$self->{AuthSelectParam}};
        $sth = $self->prepareAndExecute($self->{AuthSelect}, @bind_values);
        if (!$sth)
        {
			return undef;
        }
    }
    
    my $user;
    if (my @row = $self->getOneRow($sth))
    {
		$user = Radius::User->new($name);

		# Perhaps run a hook to do other things with the SELECT data
		$self->runHook('PostAuthSelectHook', $p, $self, $name, $p, $user, \@row);

		# If the config has defined how to handle the columns
		# in the AuthSelect statement with AuthColumnDef, use
		# that to extract check and reply items from
		if (defined $self->{AuthColumnDef})
		{
			$self->getAuthColumns($user, $p, @row);
		}
		else
		{
			# Use the default assumption about returned cols:
			# first is password, second is check items, third
			# is reply items
			my $password = shift @row;
		
			# Add a *-Password check item unless the correct password
			# was NULL in the database, This means that if 
			# the password column for a user is NULL,
			# then any password is accepted for that user.
			$user->get_check->add_attr
			(defined $self->{EncryptedPassword} ? 
			'Encrypted-Password' : 'User-Password', $password)
			unless (!defined $password && $self->{NullPasswordMatchesAny});
			
			$user->get_check->parse(shift @row);
			$user->get_reply->parse(shift @row);
		}
    }

    if (!$self->{AuthSelectParam})
    {
        $p->changeUserName($original_user_name);
    }

    return $user;
}

#####################################################################
# Handle an accounting request
# RUNS AcctSQLStatement FIRST before STORING accounting details AcctColumnDef 
sub handle_accounting
{
    my ($self, $p) = @_;

    # If AcctSQLStatement is set, parse the strings and execute them
    # Contributed by Nicholas Barrington <nbarrington@smart.net.au>
    my $acct_failed;

    if (defined $self->{AcctSQLStatement})
    {
		my $user_name = $p->getUserName();
		$user_name = $self->quote($user_name);
		map {$acct_failed += 1 unless $self->do(&Radius::Util::format_special($_, $p, $self, $user_name))} @{$self->{AcctSQLStatement}};
    }

    # If AcctColumnDef is set, do this
    # MODIFIES TABLE RECORDS BASED ON ACCOUNTING STATUS TYPE
    if (defined $self->{AcctColumnDef})
    {		
		my $table = &Radius::Util::format_special
			($self->{AccountingTable}, $p, $self);

		# conduct sql query based on account status type
		my $status_type = $p->getAttrByNum($Radius::Radius::ACCT_STATUS_TYPE); # stores either start/alive/stop
		my $qacctsessionid = $self->quote($p->getAttrByNum($Radius::Radius::ACCT_SESSION_ID));
		my $q;
		my $sth;
		my @row;
		# INSERT new record into accounting table
		if ($status_type eq 'Start') { 
			# INSERT ENTRY INTO ACCOUNTING TABLE
			my ($cols, $vals) = $self->getExtraCols($p);
			$q = &Radius::Util::format_special
			($self->{AcctInsertQuery}, $p, $self, $table, $cols, $vals);
		}	
		# UPDATE current record in accounting table, increment values in ap_accounting
		elsif ($status_type eq 'Alive' || $status_type eq 'Stop') 
		{ 
			# RETRIEVE CURRENT VALUES FROM ACCOUNTING TABLE
			my @current_values = $self->get_current_values($q, $qacctsessionid);

			# UPDATE IF VALUES WERE RETRIEVED
			if (@current_values)
			{
				# DETERMINE HOW MUCH IS INCREMENTED PER VALUE 
				my $increasedinput = $p->getAttrByNum($Radius::Radius::ACCT_INPUT_OCTETS) - $current_values[0];
				my $increasedoutput = $p->getAttrByNum($Radius::Radius::ACCT_OUTPUT_OCTETS) - $current_values[1];
				my $increasedtime = $p->getAttrByNum($Radius::Radius::ACCT_SESSION_TIME) - $current_values[2];

				# SANITIZE NEGATIVE VALUES 
				if ($increasedinput < 0) { $increasedinput = 0; }
				if ($increasedoutput < 0) { $increasedoutput = 0; }
				if ($increasedtime < 0) { $increasedtime = 0; }

				# UPDATE VALUES IN AP_ACCOUNTING TABLE IF AT LEAST ONE VALUE HAS INCREASED
				if ($increasedinput > 0 || $increasedoutput > 0 || $increasedtime > 0) 
				{
					my ($ap_mac) = split /:/, $p->getAttrByNum($Radius::Radius::CALLED_STATION_ID);
					my $qap_mac = $self->quote($ap_mac);
					$q = &Radius::Util::format_special
					($self->{ApAcctUpdateQuery}, $p, $self, $increasedinput, $increasedoutput, $increasedtime, $qap_mac);
					$self->do($q);
				}
			} 

			# UPDATE ENTRY ACCOUNTING TABLE
			my $colsvals = $self->getColsVals($p);
			$q = &Radius::Util::format_special
			($self->{AcctUpdateQuery}, $p, $self, $table, $colsvals, $qacctsessionid);
		}
		# Execute the insert, and if it fails, log the accounting
		# record to a file
		if (!$self->do($q))
		{
			if (!$self->connected())
			{
			# Connection failed, serious error
				if ($self->{AcctFailedLogFileName})
				{
					# Anonymous subroutine hides the details from logAccounting
					my $format_hook;
					$format_hook = sub { $self->runHook('AcctLogFileFormatHook', $p, $p); }
						if $self->{AcctLogFileFormatHook};

					&Radius::Util::logAccounting
					($p, undef, 
					$self->{AcctFailedLogFileName}, 
					$self->{AcctLogFileFormat},
					$format_hook);
				}
				return ($main::IGNORE, 'Database failure');
			}
			$acct_failed += 1;
		}
    }
    if ($self->{AcctFailedLogFileName} && $acct_failed)
    {
		# Anonymous subroutine hides the details from logAccounting
		my $format_hook;
		$format_hook = sub { $self->runHook('AcctLogFileFormatHook', $p, $p); }
			if $self->{AcctLogFileFormatHook};

		&Radius::Util::logAccounting
			($p, undef, 
			$self->{AcctFailedLogFileName}, 
			$self->{AcctLogFileFormat},
			$format_hook);
    }

    return ($main::ACCEPT, 'Accounting-Request accepted');
}

#####################################################################
# Work out the extra cols and values to be inserted, according to
# AcctColumnDef
# Add each column defined by AcctColumnDef
# Idea courtesy Phil Freed ptf@cybertours.com
# Column definitions with the same column and multiple (non-null) 
# values will be only inserted once
# The _last_ column definition with a non-null value will win
sub getExtraCols
{
    my ($self, $p) = @_;

    my ($value, %cols);
    foreach my $ref (@{$self->{AcctColumnDef}})
    {
		my ($col, $attr, $type, $format) = split(/\s*,\s*/, $ref, 4);
		
		if ($type eq 'formatted' || $type eq 'literal')
		{
			# Use the second field as a format_special string
			$value = &Radius::Util::format_special($attr, $p, $self);
			next unless $value ne '';
		}
		else
		{
			$value = $p->get_attr($attr);
			next unless defined $value; # Dont insert non-existent attrs
		}

		# See what type of attribute it is
		if ($type eq 'integer')
		{
			$value = $p->{Dict}->valNameToNum($attr, $value);
		}
		elsif ($type eq 'integer-date')
		{
			# Convert a unix epoch date into an SQL date
			# Format with the format string, else with with the default SQL 
			# datetime format

			$format = $self->{DateFormat} unless defined $format;
			$value = &Radius::Util::strftime($format, $value);
			$value = $self->quote($value);
			$format = undef; # dont do sprintf formatting too
		}
		elsif ($type eq 'formatted-date')
		{
			# Use Date::Format to format an SQL date
			# Deprecated
			if (!eval{require Date::Format})
			{
				$self->log($main::LOG_ERR, "Could not load Date::Format for formatted-date: $@");
				next;
			}

			# Convert a unix epoch date into an SQL date
			$value = &Date::Format::time2str($format, $value);
			$format = undef; # dont do sprintf formatting too
		}
		elsif ($type eq 'literal')
		{
			# Formatting has already been done above. This is just to
			# avoid quotes
		}
		elsif ($type eq 'inet_aton')
		{
			# Patch by Benoit Grange <b.grange@libertysurf.fr>
			# and Jerome Fleury <jerome.fleury@freesbee.net>
			# Convert an IPv4 address to an unsigned integer (32 bits)
			# Can be used with MySQL 3.23 INET_ATON() and INET_NTOA() functions
			my $ip = 0;
			map { $ip = $ip*256+$_; } split('\.', $value);
			$value = sprintf ("%u", $ip);
			$format = undef; # dont do sprintf formatting too
		}
		# Could define other data types here
		else
		{
			# Its a simple string
			# Tidy up any embedded quotes, maybe use NULL
			$value = $self->quote($value);
		}
		# Maybe there is some special formatting?
		$value = sprintf($format, $value) if defined $format;

		if (uc($col) eq 'TIME_STAMP') { # create START_TIME column with same value as TIME_STAMP
			$cols{'START_TIME'} = $value;
		}
		# This implicitly removes duplicate column names
		$cols{$col} = $value;
    }
    my @ks = sort keys %cols;
    return (join(',', @ks), join(',', @cols{@ks}));
}

#####################################################################
# Work out the extra cols and values to be inserted, according to
# AcctColumnDef
# Add each column defined by AcctColumnDef
# Idea courtesy Phil Freed ptf@cybertours.com
# Column definitions with the same column and multiple (non-null) 
# values will be only inserted once
# The _last_ column definition with a non-null value will win
sub getColsVals
{
    my ($self, $p) = @_;

    my ($value, %cols);
    foreach my $ref (@{$self->{AcctColumnDef}})
    {
		my ($col, $attr, $type, $format) = split(/\s*,\s*/, $ref, 4);
		
		if ($type eq 'formatted' || $type eq 'literal')
		{
			# Use the second field as a format_special string
			$value = &Radius::Util::format_special($attr, $p, $self);
			next unless $value ne '';
		}
		else
		{
			$value = $p->get_attr($attr);
			next unless defined $value; # Dont insert non-existent attrs
		}

		# See what type of attribute it is
		if ($type eq 'integer')
		{
			$value = $p->{Dict}->valNameToNum($attr, $value);
		}
		elsif ($type eq 'integer-date')
		{
			# Convert a unix epoch date into an SQL date
			# Format with the format string, else with with the default SQL 
			# datetime format

			$format = $self->{DateFormat} unless defined $format;
			$value = &Radius::Util::strftime($format, $value);
			$value = $self->quote($value);
			$format = undef; # dont do sprintf formatting too
		}
		elsif ($type eq 'formatted-date')
		{
			# Use Date::Format to format an SQL date
			# Deprecated
			if (!eval{require Date::Format})
			{
				$self->log($main::LOG_ERR, "Could not load Date::Format for formatted-date: $@");
				next;
			}

			# Convert a unix epoch date into an SQL date
			$value = &Date::Format::time2str($format, $value);
			$format = undef; # dont do sprintf formatting too
		}
		elsif ($type eq 'literal')
		{
			# Formatting has already been done above. This is just to
			# avoid quotes
		}
		elsif ($type eq 'inet_aton')
		{
			# Patch by Benoit Grange <b.grange@libertysurf.fr>
			# and Jerome Fleury <jerome.fleury@freesbee.net>
			# Convert an IPv4 address to an unsigned integer (32 bits)
			# Can be used with MySQL 3.23 INET_ATON() and INET_NTOA() functions
			my $ip = 0;
			map { $ip = $ip*256+$_; } split('\.', $value);
			$value = sprintf ("%u", $ip);
			$format = undef; # dont do sprintf formatting too
		}
		# Could define other data types here
		else
		{
			# Its a simple string
			# Tidy up any embedded quotes, maybe use NULL
			$value = $self->quote($value);
		}
		# Maybe there is some special formatting?
		$value = sprintf($format, $value) if defined $format;

		# Store as "col = value"
        $cols{$col} = "$col = $value";
    }
    # Return the joined SQL-style assignment string
    my @assignments = sort values %cols;
    return join(', ', @assignments);
}

#####################################################################
# Work out the check and reply items returned
# from using AuthColumnDef
# @cols is an array of field values, that should correspond to
# AuthColumnDef definitions
sub getAuthColumns
{
    my ($self, $user, $p, @cols) = @_;

    # Decode the cols returned by AuthSelect using
    # the column definitions in AuthColumnDef
    # Contributed by Lars Marowsky-Bree (lmb@teuto.net)
    foreach my $colnr (sort {$a <=> $b} keys %{$self->{AuthColumnDef}})
    {
	my ($attrib, $type, $formatting) = split (/,\s*/, $self->{AuthColumnDef}{$colnr});
	$type = lc($type); # lower-casify
	$formatting = lc($formatting); # lower-casify
#	print "trying $colnr, 	$attrib, $type, '$formatting'\n";
	# A "NULL" entry in the database will never be 
	# added to the check items,
	# ie for an entry which is NULL, every attribute 
	# will match.
	# A "NULL" entry will also not be added to the 
	# reply items list.
	# Also protect against empty and all NULLs that can be got from
	# a NULL nvarchar on MS-SQL via ODBC
	next if !defined($cols[$colnr]) 
	    || $cols[$colnr] eq ''
	    || $cols[$colnr] =~ /^\000+$/;

	# Maybe do special char processing on the value from the database
	$cols[$colnr] = &Radius::Util::format_special($cols[$colnr], $p)
	    if ($formatting eq 'formatted');

	if ($attrib eq "GENERIC") 
	{
	    # Column is a list of attr=value pairs
	    if ($type eq 'check') 
	    {
			$user->get_check->parse($cols[$colnr]);
	    } 
	    elsif ($type eq 'reply') 
	    {
			$user->get_reply->parse($cols[$colnr]);
	    }
	    elsif ($type eq 'request') 
	    {
			$p->parse(join ',', $cols[$colnr]);
	    }
	    # Other types here?
	} 
	else 
	{
	    # $attrib is an attribute name, and the 
	    # value is the string to match
	    if ($type eq "check") 
	    {
			$user->get_check->add_attr($attrib, $cols[$colnr]);
	    } 
	    elsif ($type eq "reply") 
	    {
			$user->get_reply->add_attr($attrib, $cols[$colnr]);
	    }
	    elsif ($type eq "request") 
	    {
			$p->add_attr($attrib, $cols[$colnr]);
	    }
	}
    }

    return;
}

# Converts check item name to SQL query name for getLimitValue.
my %querynames =
    (
     'Max-All-Session'       => 'AcctTotalQuery',
     'Max-Hourly-Session'    => 'AcctTotalSinceQuery',
     'Max-Daily-Session'     => 'AcctTotalSinceQuery',
     'Max-Monthly-Session'   => 'AcctTotalSinceQuery',
     'Max-All-Octets'        => 'AcctTotalOctetsQuery',
     'Max-All-Gigawords'     => 'AcctTotalGigawordsQuery',
     'Max-Hourly-Octets'     => 'AcctTotalOctetsSinceQuery',
     'Max-Hourly-Gigawords'  => 'AcctTotalGigawordsSinceQuery',
     'Max-Daily-Octets'      => 'AcctTotalOctetsSinceQuery',
     'Max-Daily-Gigawords'   => 'AcctTotalGigawordsSinceQuery',
     'Max-Monthly-Octets'    => 'AcctTotalOctetsSinceQuery',
     'Max-Monthly-Gigawords' => 'AcctTotalGigawordsSinceQuery',
    );

#####################################################################
# Override AuthGeneric getLimitValue so we can handle prepaid
# limits etc
sub getLimitValue
{
    my ($self, $username, $check_name, $p) = @_;

    my $qusername = $self->quote($username);
    my ($queryname, $resettime);
    my @resettime = localtime(time);
    if (   $check_name eq 'Max-All-Session'
	|| $check_name eq 'Max-All-Octets'
	|| $check_name eq 'Max-All-Gigawords')
    {
		# These are not time limited, do nothing here
    }
    elsif (   $check_name eq 'Max-Hourly-Session'
	   || $check_name eq 'Max-Hourly-Octets'
	   || $check_name eq 'Max-Hourly-Gigawords')
    {
		$resettime[0] = $resettime[1] = 0; # sec, min
    }
    elsif (   $check_name eq 'Max-Daily-Session'
	   || $check_name eq 'Max-Daily-Octets'
	   || $check_name eq 'Max-Daily-Gigawords')
    {
		$resettime[0] = $resettime[1] = $resettime[2] = 0; # sec, min, hour
    }
    elsif (   $check_name eq 'Max-Monthly-Session'
	   || $check_name eq 'Max-Monthly-Octets'
	   || $check_name eq 'Max-Monthly-Gigawords')
    {
		$resettime[0] = $resettime[1] = $resettime[2] = 0; # sec, min, hour
		$resettime[3] = 1; #day
    }
    else
    {
		return; # Tell the caller we dont understand this one
    }

    # Map the check name to the correct query
    $queryname = $querynames{$check_name};

    # Dont know how to get the query
    return unless defined $self->{$queryname};

    $resettime = Time::Local::timelocal(@resettime);
    my $q = &Radius::Util::format_special
	($self->{$queryname}, $p, $self, $qusername, $resettime);
    my $sth = $self->prepareAndExecute($q);
    return unless $sth;
    my @row = $self->getOneRow($sth);
    $self->log($main::LOG_DEBUG, "$queryname result $row[0]", $p);
    return $row[0] + 0;
}

#####################################################################
# Determine if user is in a given group
# Overrides AuthGeneric 
sub userIsInGroup
{
    my ($self, $user, $group, $p) = @_;

    return unless defined $self->{GroupMembershipQuery};
    my $qusername = $self->quote($user);
    my $qgroupname = $self->quote($group);
    my $q = &Radius::Util::format_special($self->{GroupMembershipQuery}, $p, 
					  $self, $qusername, $qgroupname);
    my @bind_values;
    map { push(@bind_values, Radius::Util::format_special($_, $p, $self, $user, $group)); } @{$self->{GroupMembershipQueryParam}};

    my $sth = $self->prepareAndExecute($q, @bind_values);
    return unless $sth;

    my @row = $sth->fetchrow();
    $sth->finish();
    return unless @row;
    return $row[0] eq $group;
}

#####################################################################
# Create a new EAP-FAST PAC and return its OPAQUE
# The structure will autodelete after the lifetime expires.
# lifetime is the lifetime of the PAC in seconds
# This may be overridden by subclasses
# This default implementation creates and caches PACs in memory
# Return a hash of the PAC data
sub create_eapfast_pac
{
    my ($self, $p) = @_;

    return unless $self->reconnect;
    return $self->SUPER::create_eapfast_pac()
	unless defined($self->{CreateEAPFastPACQuery});
    my $pac_opaque = &Radius::Util::random_string(32);
    my $hex_pac_opaque = unpack('H*', $pac_opaque);
    my $pac_lifetime = time() + $self->{EAPFAST_PAC_Lifetime};
    my $pac_key = &Radius::Util::random_string(32);
    my $hex_pac_key = unpack('H*', $pac_key);
    my $q = &Radius::Util::format_special($self->{CreateEAPFastPACQuery}, $p, 
					  $self, $hex_pac_opaque, $pac_lifetime, $hex_pac_key);
    my $sth = $self->prepareAndExecute($q);
    return unless $sth;

    return {pac_opaque   => $pac_opaque,
	    pac_lifetime => $pac_lifetime,
	    pac_key      => $pac_key};
}

#####################################################################
# Find a previously created EAP-FAST PAC given its OPAQUE.
# The returned hash contains the pac_lifetime and the pac_key, if available
# This may be overridden by subclasses
sub get_eapfast_pac
{
    my ($self, $pac_opaque, $p) = @_;

    return unless $self->reconnect;
    return $self->SUPER::create_eapfast_pac()
	unless defined($self->{GetEAPFastPACQuery});

    my $hex_pac_opaque = unpack('H*', $pac_opaque);
    my $q = &Radius::Util::format_special($self->{GetEAPFastPACQuery}, undef, $self, $hex_pac_opaque, time());
    my $sth = $self->prepareAndExecute($q);

    my @row = $sth->fetchrow();
    return unless @row;
    return {pac_opaque   => $pac_opaque,
	    pac_lifetime => $row[0],
	    pac_key      => pack('H*', $row[1])};
}


1;
