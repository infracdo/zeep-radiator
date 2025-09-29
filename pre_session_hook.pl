use DBI;
use Redis;
use JSON;

sub {
    &main::log($main::LOG_DEBUG, "[hook] inside post processing hook");

    my $p = ${$_[0]};
    my $rp = ${$_[1]};
    my $reqcode = $p->code;
    my $username = $p->get_attr('User-Name');
    my $csid_raw = $p->get_attr('Called-Station-Id');
    my ($csid, $ssid) = defined $csid_raw ? split(/:/, $csid_raw, 2) : (undef, undef);
    &main::log($main::LOG_DEBUG, "[pre auth hook] reply code $rpcode ");

    return unless defined $csid && defined $reqcode && $reqcode eq 'Accounting-Request';

    my ($dbh, $sth, @current_values, $session_id);
    eval {
        if ($reqcode eq 'Accounting-Request') {
            $session_id = $p->get_attr('Acct-Session-Id');
            $dbh = DBI->connect("dbi:Pg:dbname=radius;host=192.168.61.22;port=5433", "radiator", "ap0ll0z33P", { RaiseError => 1, AutoCommit => 1 });
            $sth = $dbh->prepare(q{
                SELECT acctinputoctets, acctoutputoctets, acctsessiontime FROM accounting WHERE acctsessionid=?
            });
            $sth->execute($session_id);
            @current_values = $self->getOneRow($sth);
            $sth->finish;
            $dbh->disconnect;
        }
    };
    if ($@) {
        &main::log($main::LOG_WARNING, "Database update error: $@");
        open(my $errlog, '>>', '/var/log/radiator/session_debug.log');
        print $errlog scalar(localtime) . " - DB ERROR: $@\n";
        close($errlog);
    }

    # Connect to Redis
    my $redis;
    eval {
        $redis = Redis->new(
            server        => '192.168.61.23:6379',
            reconnect     => 10,
            every         => 10000,
            cnx_timeout   => 5,
            read_timeout  => 2,
            write_timeout => 2
        );
        $redis->auth('ap0ll0z33P');
    };
    if ($@ || !$redis) {
        &main::log($main::LOG_WARNING, "Failed to connect to Redis: $@");
        return;
    }

    my ($rkey, $job);
    if ($reqcode eq 'Accounting-Request') {
        my $status_type        = $p->get_attr('Acct-Status-Type');
        my $calling_station_id = $p->get_attr('Calling-Station-Id');
        my $session_time       = int($p->get_attr('Acct-Session-Time') // 0);
        my $input_octets       = int($p->get_attr('Acct-Input-Octets') // 0);
        my $output_octets      = int($p->get_attr('Acct-Output-Octets') // 0);
        my $framed_ip_addr     = $p->get_attr('Framed-IP-Address');
        my $nas_ip_addr        = $p->get_attr('NAS-IP-Address');

        $rkey = 'radiator:jobs:accounting';
        $job = {
            status_type        => $status_type,
            called_station_id  => $csid,
            ssid               => $ssid,
            calling_station_id => $calling_station_id,
            subscriber_id      => $username,
            session_id         => $session_id,
            session_time       => $session_time,
            input_octets       => $input_octets,
            output_octets      => $output_octets,
            framed_ip_addr     => $framed_ip_addr,
            nas_ip_addr        => $nas_ip_addr,
            timestamp          => time,
        };

        eval {
            $redis->multi;

            if (@current_values) {
                my $increasedinput  = $input_octets  - int($current_values[0] // 0);
                my $increasedoutput = $output_octets - int($current_values[1] // 0);
                my $increasedtime   = $session_time  - int($current_values[2] // 0);
                my $increasedoctets = $increasedinput + $increasedoutput;
                my $increasedkb     = int($increasedoctets / 1000);

                &main::log($main::LOG_DEBUG, "[Redis] Queuing data usage updates for $username");

                $redis->decrby("datalimit:$username", $increasedkb);
                $redis->incrby("usage:$username", $increasedkb);
                $redis->incrby("time:$username", $increasedtime);
                $redis->incrby("usage:$csid", $increasedkb);
                $redis->incrby("time:$csid", $increasedtime);
            }

            my $rvalue = encode_json($job);
            $redis->rpush($rkey, $rvalue);

            my $res = $redis->exec;
            if (!$res) {
                &main::log($main::LOG_WARNING, "[Redis] EXEC failed or returned nothing");
            }
        };
        if ($@) {
            &main::log($main::LOG_WARNING, "Failed Redis transaction: $@");
            open(my $errlog, '>>', '/var/log/radiator/session_debug.log');
            print $errlog scalar(localtime) . " - REDIS ERROR: $@\n";
            close($errlog);
        }
    }

    return;
}
