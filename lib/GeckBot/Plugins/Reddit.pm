package GeckBot::Plugins::Reddit;

use JSON::XS;
use HTTP::Tiny;
use Data::Dumper;

my $tracking_dir = 'var/reddit_check'; #reletive to $geckbot->{'plugin_base'};

#
#sub init {
#	my ( $sym, $self ) = @_;
#	print Dumper $self->{'reddit_config'};
#	foreach my $channel ( keys %{ $self->{'reddit_config'} } ) {
##		$self->log("Adding subprocess for checking /r/${subreddit} for $channel");
#
#		$self->forkit(
#			'run' => \&check_reddit,
#			'channel' => $channel,
#			'body' => $subreddit,
#		);
#	}
#
#}

my $firstrun = 1;

sub tick {
	my ( $self ) = @_;
	
	foreach my $channel ( keys %{ $self->{'reddit_config'} } ) {
		my $subreddit = $self->{'reddit_config'}->{$channel};
		$self->forkit(
			'run' => \&check_reddit,
			'channel' => $channel,
			'body' => $subreddit,
			'arguments' => [$channel, $firstrun],
		);
	}
	$firstrun = 0;
	return time + 120;
}

sub check_reddit {
	my ( $subreddit, $channel, $firstrun ) = @_;
	my @reddit_new = reddit_read($subreddit);
	my $tracking_data = load_tracking( $channel );

	my $last_created_time = exists $tracking_data->{$channel}->{'last_created_time'} ? $tracking_data->{$channel}->{'last_created_time'}  : 0;
	
	#print "Initial last_created_time: $last_created_time\n";

	@reddit_new = reddit_read($subreddit);
	my $this_checks_newest_time = $reddit_new[0]->{'data'}->{'created_utc'};
	
	#print "this_checks_newest_time: $this_checks_newest_time\n";
	if ( $last_created_time == $this_checks_newest_time ) {
		return;
	}
	
	foreach my $entry ( @reddit_new ) {
		my $data = $entry->{'data'};
		if ( $data->{'created_utc'} > $last_created_time ) {
			print "New r/${subreddit} post: " . $data->{'title'} . "\n" if !$firstrun;
			print "[ http://reddit.com/r/${subreddit}/" . $data->{'id'} . "/ ]\n" if !$firstrun;
		}
		else {
			last;
		}

	}

	$tracking_data->{$channel}->{'last_created_time'} = $this_checks_newest_time;
	save_tracking($channel, $tracking_data);

	#print "new last_created_time: " . $tracking_data->{$channel}->{'last_created_time'} . "\n\n\n";
	exit;
}

sub load_tracking {
	my ( $channel ) = @_;
	$channel =~ s/\#//g;
	my $tracking_file = "${tracking_dir}/${channel}";
	my $tracking_data = {};
	if ( -e $tracking_file ) {
		open my $tracking_fh, '<', $tracking_file;
		my $tracking_string = <$tracking_fh>;
		eval { 
			$tracking_data = JSON::XS::decode_json($tracking_string);
		};
		if ( $@ ) {
			#todo: file-based logging
		}
		close $tracking_fh;
	}

	return $tracking_data;
}

sub save_tracking {
	my ($channel, $tracking_data ) = @_;
	$channel =~ s/\#//g;
	my $tracking_file = "${tracking_dir}/${channel}";

	my $tracking_string = JSON::XS::encode_json($tracking_data);

	open my $tracking_fh, '>', $tracking_file;
	print $tracking_fh $tracking_string;
	close $tracking_fh;
}

sub reddit_read {
    my ( $subreddit ) = @_;

    my $http = HTTP::Tiny->new( 'agent' => 'Reddit Reader v' . $VERSION );
    my ( $parsed_response, $page_url, $next, $res );
    $page_url = "http://www.reddit.com/r/$subreddit/new.json";
    print "grabbing new page : $page_url\n" if $debug;

    $res = $http->get($page_url);
    if ( $res->{'status'} != 200 ) {
        return 'non-200 response recieved';
    }

    $parsed_response = JSON::XS::decode_json( $res->{'content'} );

    return @{ $parsed_response->{'data'}->{'children'} };
}

1;