use DBI;
use Redis;
use JSON;

sub 
{
    &main::log($main::LOG_DEBUG, "[hook] inside post processing hook");

    my $p = ${$_[0]};
    my $rp = ${$_[1]};
    my $code = $rp->code;
    my $username = $p->get_attr('User-Name');
    my $csid_raw = $p->get_attr('Called-Station-Id');
    my ($csid, $ssid) = defined $csid_raw ? split(/:/, $csid_raw, 2) : (undef, undef);

    # proceed if csid is defined and code is either Access-Accept or Access-Reject
    return unless defined $csid && defined $code && ($code eq 'Access-Accept' || $code eq 'Access-Reject');

    # update database
    my ($dbh, $sth);
    eval {
        if ($code eq 'Access-Accept')
        {
            if ($username && $csid) 
            {
                &main::log($main::LOG_DEBUG, "[hook] making changes to nas_session_mac_attrs for $username, $csid");
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
                &main::log($main::LOG_DEBUG, "[hook] made changes to nas_session_mac_attrs for $username, $csid");
            }
        }
    };
    if ($@) {
        &main::log($main::LOG_WARNING, "Failed to update database: $@");
        open(my $errlog, '>>', '/var/log/radiator/session_debug.log');
        print $errlog scalar(localtime) . " - POST PROCESSING HOOK ENCOUNTERED DB ERROR: $@\n";
        close($errlog);
    }

    &main::log($main::LOG_WARNING, "Stopping post processing hook before redis implementation");

    # update redis
    my $redis;
    eval {
        $redis = Redis->new(server => '192.168.61.23:6379', reconnect => 10, every => 10000);
        $redis->auth('ap0ll0z33P');
    };
    if ($@ || !$redis) {
        &main::log($main::LOG_WARNING, "Failed to connect to Redis: $@");
        return;
    }

    my $job = {
        action => $code eq 'Access-Accept' ? 'login successful' : 'login failed',
        called_station_id => $csid, 
        ssid => $ssid, 
        subscriber_id => $username, 
        timestamp => time, 
    };
    my $job_json = encode_json($job);
    
    eval {
        &main::log($main::LOG_DEBUG, "[json] radiator:jobs:login, $job_json");
        $redis->rpush('radiator.jobs.login', $job_json);
    };
    if ($@) {
        &main::log($main::LOG_WARNING, "Failed to push job to Redis: $@");
        open(my $errlog, '>>', '/var/log/radiator/session_debug.log');
        print $errlog scalar(localtime) . " - POST PROCESSING HOOK ENCOUNTERED REDIS ERROR: $@\n";
        close($errlog);
    }

    return;
}