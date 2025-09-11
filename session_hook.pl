sub {
    &main::log($main::LOG_DEBUG, "handler access-request has been called");
    my $p = ${$_[0]};
    my $rp = ${$_[1]};
    my $code   = $p->code;
    my $username = $p->get_attr('User-Name');
    my $csid_raw = $p->get_attr('Called-Station-Id');
    my ($csid) = $csid_raw =~ /^([0-9a-fA-F]{12})/;
    unless ($username && $csid) { # checks if username and csid are defined and not empty
        open(my $rejlog, '>>', '/var/log/radiator/session_debug.log');
        print $rejlog scalar(localtime) . " - username and/or csid cannot be identified - rejecting $username\n";
        close($rejlog);
                
        $rp->set_code('Access-Reject');
        $rp->add_attr('Reply-Message', 'Access denied due to unidentified username/csid.');
        $p->{Client}->replyTo($p);

        return;
    }
    my ($dbh, $sth);

    eval {
        open(my $log, '>>', '/var/log/radiator/session_debug.log');
        print $log scalar(localtime) . " - user $username attempting to authenticate from csid $csid_raw)\n";
        close($log);
        
        $dbh = DBI->connect("dbi:Pg:dbname=radius;host=192.168.61.22;port=5433", "radiator", "ap0ll0z33P", { RaiseError => 1, AutoCommit => 1 });
        $sth = $dbh->prepare(q{
            SELECT 1 FROM allowed_nas_mac_address WHERE called_station_id = ?
        });
        $sth->execute($csid);
        my $is_allowed = $sth->fetchrow_array;
        $sth->finish;
        $dbh->disconnect;

        unless ($is_allowed) { # checks if csid is in allowed_nas_mac_address
            open(my $rejlog, '>>', '/var/log/radiator/session_debug.log');
            print $rejlog scalar(localtime) . " - csid $csid not in list of allowed nas mac address - rejecting $username\n";
            close($rejlog);
            
            $rp->set_code('Access-Reject');
            $rp->add_attr('Reply-Message', 'Access denied due to unauthorized csid.');
            $p->{Client}->replyTo($p);

            return;
        }

        open(my $log2, '>>', '/var/log/radiator/session_debug.log');
        print $log2 scalar(localtime) . " - found csid $csid in list of allowed nas mac address - accepting $username\n";
        close($log2);
    };
    if ($@) {# if error is found during DB operations, log it and reject
        open(my $errlog, '>>', '/var/log/radiator/session_debug.log');
        print $errlog scalar(localtime) . " - PRE-SESSION HOOK ENCOUNTERED DB ERROR: $@\n";
        close($errlog);
            
        $rp->set_code('Access-Reject');
        $rp->add_attr('Reply-Message', 'Access denied due to a database error during authentication.');
        $p->{Client}->replyTo($p);
    }

    return;
}
