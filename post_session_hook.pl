sub {
    my $p = ${$_[0]};
    my $rp = ${$_[1]};
    my $result = ${$_[2]};
    my $code   = $p->code;
    my $username = $p->get_attr('User-Name');
    my $csid_raw = $p->get_attr('Called-Station-Id');
    my ($csid) = $csid_raw =~ /^([0-9a-fA-F]{12})/;
    my ($dbh, $sth, $remaining_bytes);

    if ($result == $main::ACCEPT)
    {
        eval {
            if ($code eq 'Access-Request') {
                $dbh = DBI->connect("dbi:Pg:dbname=radius;host=192.168.61.22;port=5433", "radiator", "ap0ll0z33P", { RaiseError => 1, AutoCommit => 1 });
                $sth = $dbh->prepare(q{
                    INSERT INTO nas_session_mac_attrs (username, called_station_id, updated_at)
                    VALUES (?, ?, NOW())
                    ON CONFLICT (username)
                    DO UPDATE SET called_station_id = EXCLUDED.called_station_id, updated_at = NOW()
                });
                $sth->execute($username, $csid);
                $sth->finish;
                $dbh->disconnect;

                open(my $log1, '>>', '/var/log/radiator/session_debug.log');
                print $log1 scalar(localtime) . " - logged user $username and csid $csid to nas_session_mac_attrs table\n";
                close($log1);
            } elsif ($code eq 'Accounting-Request') {

                $dbh = DBI->connect("dbi:Pg:dbname=radius;host=192.168.61.22;port=5433", "radiator", "ap0ll0z33P", { RaiseError => 1, AutoCommit => 1 });
                $sth = $dbh->prepare(q{
                    SELECT remaining_bytes FROM subscriber WHERE username = ?
                });
                $sth->execute($username);
                $remaining_bytes = $sth->fetchrow_array;
                $remaining_bytes = 0 unless defined $remaining_bytes;
                $sth->finish;
                $dbh->disconnect;

                open(my $log2, '>>', '/var/log/radiator/session_debug.log');
                print $log2 scalar(localtime) . " - remaining bytes for $username: $remaining_bytes (CSID: $csid)\n";
                close($log2);
                
                if ($remaining_bytes <= 0)
                {
                    open(my $rejlog, '>>', '/var/log/radiator/session_debug.log');
                    print $rejlog scalar(localtime) . " - user has no remaining bytes left - rejecting $username\n";
                    close($rejlog);
                    &main::log($main::LOG_DEBUG, "Access denied due to insufficient remaining bytes.");
                    ${$_[2]} = $main::REJECT;
                }
            } 
        };
        if ($@) {
            open(my $errlog, '>>', '/var/log/radiator/session_debug.log');
            print $errlog scalar(localtime) . " - POST-SESSION HOOK ENCOUNTERED DB ERROR: $@\n";
            close($errlog);
        }
    }

    return;
}
