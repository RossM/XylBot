package mafia;

use strict;
use warnings;
no warnings 'redefine', 'qw';
use sort 'stable';
use Carp qw(cluck);

our (%messages, %config);
our (%role_config, %group_config, %setup_config);
our (%player_data, %role_data, %group_data);
our (@players, @moderators, @alive);
our (%automoderators);
our (%players, %moderators, %player_masks, %players_by_mask);
our (@action_queue, @resolved_actions, @deepsouth_actions);
our ($phases_without_kill);
our ($day, $phase);
our ($last_votecount_time);
our ($last_massclaim_time);
our (@timed_action_timers);
our (@recharge_timers);
our ($signuptimer, $signupwarningtimer);
our (%reset_voters, %stop_voters);
our ($cur_setup);
our ($mafia_cmd, $mafiachannel, $resolvemode, $messagemode);
our (%action_config);
our ($game_active, $line_counter, $lynch_votes, $nokill_phase, $nonrandom_assignment);
our ($gameid, $gamelogfile);
our (@items_on_ground);

our $just_testing;
our @test_scheduled_events;

our ($end_signups_time);

sub add_moderator {
	my ($fromnick, $frommask) = @_;
	
	$players{$fromnick} = $fromnick;
	$player_masks{$fromnick} = $frommask;
	$moderators{$fromnick} = $fromnick;
	$players_by_mask{$frommask} = $fromnick;

	push @moderators, $fromnick if $phase ne 'signup';

	update_voiced_players();
}

sub add_player {
	my ($fromnick, $frommask) = @_;
	
	$players{$fromnick} = $fromnick;
	$player_masks{$fromnick} = $frommask;
	$players_by_mask{$frommask} = $fromnick;

	@players = keys(%players);
	update_voiced_players();
}

sub remove_player {
	my ($fromnick, $frommask) = @_;
	
	delete $players{$fromnick};
	delete $player_masks{$fromnick};
	delete $moderators{$fromnick};
	delete $players_by_mask{$frommask};

	@players = keys(%players);
	update_voiced_players();
}

sub replace_player {
	my ($fromnick, $tonick) = @_;
	$fromnick = get_player($fromnick);

    	my $frommask = $player_masks{$fromnick};
	remove_votes($fromnick);
    	remove_player($fromnick, $frommask);
    	add_player($tonick, $frommask);

    	$player_data{$tonick} = $player_data{$fromnick};
    	delete $player_data{$fromnick};

    	foreach my $player (keys %player_data) {
        	if ($player_data{$player}{buddy} &&
	    		($player_data{$player}{buddy} eq $fromnick)) {
           		 $player_data{$player}{buddy} = $tonick;
        	}
	}

    	calculate_group_members();
    	calculate_alive();
    	update_voiced_players();
}


sub cmd_start {
	my ($fromnick, $frommask, @args, $modactionsallowed) = @_;
	
	if ($game_active)
	{
		notice $fromnick, "There is already a game in progress.";
		return 1;
	}
		
	if (@args)
	{
		my $setup = lc $args[0];
		if (!$setup_config{$setup})
		{
			announce "That setup does not exist.";
			return 1;
		}
		if ($setup_config{$setup}{disabled})
		{
			announce "That setup has been disabled.";
			return 1;
		}
		my $wday = (localtime)[6];
		if ($setup_config{$setup}{enable_on_days} && $setup_config{$setup}{enable_on_days} !~ /$wday/)
		{

			my @days = qw/Sundays Mondays Tuesdays Wednesdays Thursdays Fridays Saturdays/;
				announce "That setup can only be played on " . and_words(@days[grep { $setup_config{$setup}{enable_on_days} =~ /$_/ } 0..6]) . ".";
				return 1;
			}
		if (setup_rule("moderated", $setup) && $frommask =~ /c-76-121-159-198.hsd1.wa.comcast.net/) {
			announce "This user is not allowed to start moderated games.";
			return 1;
		}
		if (setup_rule("moderated", $setup) && $frommask =~ /WPPWAH.user.globalgamers.net/) {
			announce "This user is not allowed to start moderated games.";
			return 1;
		}
		$cur_setup = $setup;
	}
	else
	{
		$cur_setup = "normal";
	}

	# if (setup_rule('randomsetup', $cur_setup))
	# {
	# 	my @randomsetups = grep { $setup_config{$_}{randomok} } keys %setup_config;
	# 	$cur_setup = $randomsetups[rand @randomsetups];
	# }

	$game_active = 1;
	$gameid = time;
		
	$phase = "signup";
	@players = @moderators = ();
		
	my $playertext = "";
	my $minplayers = setup_minplayers($cur_setup);
	my $maxplayers = setup_maxplayers($cur_setup);
	if ($minplayers == $maxplayers)
	{
		$playertext = " for $minplayers players";
	}
	elsif ($maxplayers < $config{'maximum_players'})
	{
		$playertext = " for $minplayers to $maxplayers players";
	}
	elsif ($minplayers > $config{'minimum_players'})
	{
		$playertext = " for $minplayers+ players";
	}
	my $setupname = $cur_setup . $playertext;
	my $starttime = setup_rule('start_time', $cur_setup) || $config{start_time};
	my $readabletime = ($starttime >= 180 ? int($starttime / 60) . " minutes" : "$starttime seconds");
	announce "Starting a game of Mafia " . ($cur_setup eq 'normal' ? "" : "($setupname) ") . "in $readabletime. Type \"!$mafia_cmd in\" to sign up.";
	announce "Type \"!$mafia_cmd go\" to end signups in 30 seconds.";

	if (setup_rule('moderated', $cur_setup))
	{
		add_moderator($fromnick, $frommask);
		announce "The moderator is $fromnick.";

		update_voiced_players();
	}
		
	schedule(\$signupwarningtimer, $starttime - 30, \&end_signups_warning);
	schedule(\$signuptimer, $starttime, \&end_signups);
	$end_signups_time = time + $starttime;
}

sub num_players_signed_up {
	my $numin = 0;
	foreach my $player (keys %players)
	{
		$numin++ if $players{$player} && !$moderators{$player};
	}

	return $numin;
}

sub cmd_go {
	my ($fromnick) = @_;
	
	my $numin = num_players_signed_up();
		
	if (!$players{$fromnick})
	{
		notice($fromnick, "You are not signed up for the game yet.");
	}
	elsif ($numin < setup_minplayers($cur_setup))
	{
		notice($fromnick, "There are not yet enough players signed up.");
	}
	else
	{
		if ($end_signups_time >= time + 30) {
			unschedule(\$signupwarningtimer); #Daz, 07/08/12
			end_signups_warning();
			schedule(\$signuptimer, 30, \&end_signups);
			$end_signups_time = time + 30;
		}
	}	
}

sub cmd_forcego {
	my ($fromnick) = @_;
	
	my $numin = num_players_signed_up();
		
	if ($numin < setup_minplayers($cur_setup))
	{
		notice($fromnick, "There are not yet enough players signed up.");
	}
	else
	{
		if ($end_signups_time >= time + 0) {
		#	end_signups_warning();
			schedule(\$signuptimer, 0, \&end_signups);
			$end_signups_time = time + 0;
		}
	}	
}

sub cmd_wait {
	my $starttime = setup_rule('start_time', $cur_setup) || $config{start_time};
	if ($end_signups_time + 60 <= time + $starttime) {
		my $extendtime = $end_signups_time - time + 60;
		announce "Signups have been extended for 1 minute.";
		schedule(\$signupwarningtimer, $extendtime - 30, \&end_signups_warning);
		schedule(\$signuptimer, $extendtime, \&end_signups);
		$end_signups_time = time + $extendtime;
	}
}

sub cmd_in {
	my ($fromnick, $frommask) = @_;

	if ($frommask =~ /c-71-200-123-78\.hsd1\.md\.comcast\.net/)
	# if ($frommask =~ /c-71-200-123-78\.hsd1\.md\.comcast\.net|71-8-124-26\.dhcp\.ftwo\.tx\.charter\.com/)
	{
		notice($fromnick, "You have been banned from joining games.");
		return;
	}
	if ($players{$fromnick})
	{
		notice($fromnick, "You are already signed up.");
	}
	elsif ($fromnick =~ /^none$|^nolynch$|^self$|^sky$|^unknown$/i)
	{
		notice($fromnick, "Sorry, you cannot join a game with that nick. Please change your nick and try again.");
		return 1;
	}
	elsif (length($fromnick) > 22)
	{
		notice($fromnick, "Sorry, you cannot join a game because your nick is too long. Please change your nick and try again.");
		return 1;
	}
	else
	{
		if ($players_by_mask{$frommask})
		{
			notice($fromnick, "Your previous signup as $players_by_mask{$frommask} has been removed.");
			my $was_moderator = $moderators{$players_by_mask{$frommask}};
			remove_player($players_by_mask{$frommask}, $frommask);
			add_moderator($fromnick, $frommask) if $was_moderator;
		}

		add_player($fromnick, $frommask);
		notice($fromnick, "You are now signed up for the next game.");
	}
		
	my $maxplayers = setup_rule('players', $cur_setup) || setup_rule('maxplayers', $cur_setup);
	if ($maxplayers)
	{
		my $numin = num_players_signed_up();
		end_signups() if $numin eq $maxplayers;
	}
}	

sub cancel_game {
	game_over("");
	unschedule(\$signuptimer);
	unschedule(\$signupwarningtimer);
}

sub cmd_out {
	my ($fromnick, $frommask) = @_;
	
	if ($players_by_mask{$frommask})
	{
		if ($moderators{$players_by_mask{$frommask}})
		{
			cancel_game();
			return;
		}
			
		remove_player($players_by_mask{$frommask}, $frommask);
		notice($fromnick, "You are no longer signed up for the next game.");
	}
	elsif ($players{$fromnick})
	{
		if ($moderators{$fromnick})
		{
			cancel_game();
			return;
		}
		
		remove_player($fromnick, $frommask);
		notice($fromnick, "You are no longer signed up for the next game.");
	}
	else
	{
		notice($fromnick, "You are not on the signup list.");
	}
}

sub cmd_status {
	my ($fromnick) = @_;
	
	my $numin = num_players_signed_up();
	if ($phase eq 'signup')
	{
		notice($fromnick, "Signups are in progress. ($numin signed up.)");
	}
	elsif ($game_active)
	{
		notice($fromnick, "Game in progress: \u$phase $day - " . scalar(@alive) . " players alive.");
	}
	else
	{
		notice($fromnick, "No game in progress. To start a game, use '!$mafia_cmd start'.");
	}
}

sub cmd_top10 {
	my ($fromnick, $frommask, @args) = @_;
	
	# Disabled :(
	# notice($fromnick, "Sorry, rankings are currently disabled.");
	# return 1;
		
	my $wantsetup = lc $args[0] || "overall";
		
	if ($wantsetup !~ /^overall$|^all$|^monthly$|^daily$|^quarterly$/ && !$setup_config{$wantsetup} && !$group_config{$wantsetup})
	{
		notice($fromnick, "Sorry, the setup or team '$wantsetup' does not exist.");
		return 1;
	}
		
	open(TOPSCORES, '<', "mafia/bestplayers.dat") or return 1;
	
	while (my $line = <TOPSCORES>)
	{
		my ($setup, $player, $rank, $score, $wins, $losses, $draws) = split /\s+/, $line;
		next unless $setup eq $wantsetup;

		last if $rank > 10;
			
		notice $fromnick, sprintf "%2i | %-17s | %3i points | %i wins, %i losses, %i draws", $rank, $player, $score, $wins, $losses, $draws;
	}
		
	close TOPSCORES;
}

sub cmd_leaders {
	my ($fromnick, $frommask, @args) = @_;

	# Disabled :(
	# notice($fromnick, "Sorry, rankings are currently disabled.");
	# return 1;
		
	open(TOPSCORES, '<', "mafia/bestplayers.dat") or return 1;

	my %player_lead_count;
	my %player_setups;
	my %setup_lead_count;
	while (my $line = <TOPSCORES>)
	{
		my ($setup, $player, $rank, $score, $wins, $losses, $draws) = split /\s+/, $line;
		next unless $rank == 1;
		next unless defined($setup_config{$setup}) || $setup =~ /^overall$|^all$|^monthly$|^daily$/;

		$setup_lead_count{$setup}++;
		$player_lead_count{$player}++;
		push @{$player_setups{$player}}, $setup;
	}

	foreach my $leader (keys %player_setups)
	{
		@{$player_setups{$leader}} = grep { $setup_lead_count{$_} == 1 } @{$player_setups{$leader}};
		$player_lead_count{$leader} = scalar(@{$player_setups{$leader}});
	}

	my @leaders = sort { $player_lead_count{$b} <=> $player_lead_count{$a} || lc $a cmp lc $b } keys %player_lead_count;
	foreach my $leader (@leaders)
	{
		my @setups = @{$player_setups{$leader}};
		next unless @setups;
		notice $fromnick, sprintf "%2i | %-17s | %s", scalar(@setups), $leader, join(' ', @setups);
	}

	close TOPSCORES;
}

sub cmd_rank {
	my ($fromnick, $frommask, @args) = @_;
	
	my $who = $fromnick;
	my $wantsetup = "overall";

	# Disabled :(
	# notice($fromnick, "Sorry, rankings are currently disabled.");
	# return 1;
		
	if ($args[0] && ($setup_config{lc $args[0]} || $group_config{lc $args[0]} || $args[0] =~ /^all$|^daily$|^monthly$/))
	{
		$wantsetup = lc shift @args;
		$who = shift @args if @args;
	}
	else
	{
		$who = shift @args if @args;
		$wantsetup = lc shift @args if @args;
	}
		
	if ($wantsetup !~ /^overall$|^all$|^monthly$|^daily$/ && !$setup_config{$wantsetup} && !$group_config{$wantsetup})
	{
		notice($fromnick, "Sorry, the setup or team '$wantsetup' does not exist.");
		return 1;
	}
		
	open(TOPSCORES, '<', "mafia/bestplayers.dat") or return 1;
		
	while (my $line = <TOPSCORES>)
	{
		my ($setup, $player, $rank, $score, $wins, $losses, $draws, $advwins, $bestrole) = split /\s+/, $line;
		next unless lc $player eq lc $who;
		next unless lc $setup eq lc $wantsetup;

		my $setupname = "at $wantsetup";
		$setupname = "overall" if $wantsetup eq 'overall';
		$setupname = "this month" if $wantsetup eq 'monthly';
			
		if (lc $who eq lc $fromnick)
		{
			my $bestrolename = role_name($bestrole, 1);
			notice $fromnick, "You are ranked " . nth($rank) . " $setupname" .
				" with $score points. You have won $wins games, lost $losses, and drawn $draws. " .
				"You need about $advwins more wins to advance a rank. " .
				"Your lucky role is $bestrolename.";
		}
		else
		{
			notice $fromnick, "$who is ranked " . nth($rank) . " $setupname" .
				" with $score points. (S)he has won $wins games, lost $losses, and drawn $draws. " .
				"(S)he needs about $advwins more wins to advance a rank.";
		}
		return 1;
	}
		
	notice $fromnick, "Sorry, I can't find $who in the rankings.";
	return 1;			
}

sub cmd_record {
	my ($fromnick, $frommask, @args) = @_;
	
	# Disabled :(
	# notice($fromnick, "Sorry, rankings are currently disabled.");
	# return 1;
		
	open(RECORDS, '<', "mafia/records.dat") or return 1;
	my $pattern = quotemeta join(' ', @args);
		
	my @records = <RECORDS>;
	@records = grep { /$pattern/i } @records if $pattern;
	
	if (!@records)
	{
		notice($fromnick, "Sorry, there are no records matching '$pattern'.");
		return 1;
	}
		
	my $record = $records[rand @records];
	chomp $record;
	$record =~ s/\s+\^\s+$//;
	my @recordlines = split /\s+\^\s+/, $record;
		
	foreach my $line (@recordlines)
	{
		notice($fromnick, $line);
	}
		
	close RECORDS;
}

sub cmd_messages {
	my ($fromnick) = @_;

	if (!alive($fromnick)) {
		notice($fromnick, "You are dead.");
		return;
	}

	foreach my $message (@{$player_data{$fromnick}{safe}{messages} || []}) 
	{
		notice($fromnick, $message);
	}
}

sub start_test_setup {
	my ($fromnick, @args) = @_;

	$game_active = 1;
	$gameid = time;
		
	$phase = "signup";
	@players = @moderators = ();
	$cur_setup = "test";
	if (@args)
	{
		foreach my $player (@args)
		{
			$players{$player} = $fromnick;
			$player_masks{$player} = 'fake';
		}
	}
	else
	{
		my $nextplayer = 'a';
		for (1 .. $setup_config{test}{players})
		{
			my $player = $nextplayer++;
			$players{$player} = $fromnick;
			$player_masks{$player} = 'fake';
		}
	}

	$nonrandom_assignment = 1;
	end_signups();
	$nonrandom_assignment = 0;
}

sub cmd_starttest {
	my ($fromnick, $frommask, @args) = @_;
	
	if ($game_active)
	{
		notice $fromnick, "There is already a game in progress.";
		return 1;
	}
		
	if (@args && scalar(@args) != $setup_config{test}{players})
	{
		notice $fromnick, "Wrong number of players (need $setup_config{test}{players})";
		return 1;
	}
		
	add_moderator($fromnick, $frommask);
	start_test_setup($fromnick, @args);
}

sub do_reset {
	stop_game();
	unschedule_all();
	if ($gamelogfile)
	{
		close($gamelogfile);
		undef $gamelogfile;
	}
	$just_testing = 0;
	@test_scheduled_events = ();

	our (%setuprole_cache, %evolution_cache, %canonicalize_cache);
	%setuprole_cache = %evolution_cache = %canonicalize_cache = ();

	%automoderators = ();

	announce "The bot has been reset.";
}

sub cmd_reset {
	my ($fromnick, $frommask) = @_;
	
	$reset_voters{$frommask} = 1;
	my $reset_voters = scalar(keys %reset_voters);
	my $voters_needed = $game_active ? int(scalar(@alive) / 2) + 1 : 3;
	$voters_needed = 3 if $voters_needed < 3;
		
	if ($reset_voters >= $voters_needed)
	{
		do_reset();
	}
	else
	{
		announce "$fromnick has voted to reset the bot (vote $reset_voters of $voters_needed).";
	}
}

sub cmd_stop {
	my ($fromnick, $frommask) = @_;
	
	$stop_voters{$frommask} = 1;
	my $stop_voters = scalar(keys %stop_voters);
	my $voters_needed = $game_active ? int(scalar(@alive) * 2 / 3) + 1 : 3;
	$voters_needed = 3 if $voters_needed < 3;
		
	if ($stop_voters >= $voters_needed)
	{
		cancel_game();
	}
	else
	{
		announce "$fromnick has voted to stop the game (vote $stop_voters of $voters_needed).";
	}
}

sub role_is_secret {
	my $role = shift;
	return 0 if ($role_config{$role}{seencount} || 0) >= 15;
	return 1 if $role_config{$role}{secret};
	foreach my $part (split /\+/, $role) {
		return 1 if $role_config{$part}{secret};
	}
	return 0;
}

sub mafia_command {
	my ($connection, $command, $forum, $from, $to, $args, $level) = @_;
	my ($subcommand, @args) = split /\s+/, $args;
	
	my ($fromnick, $frommask) = (split /!/, $from);

	$subcommand = lc $subcommand;
	
	$mafiachannel = $to if !$game_active && $forum eq 'public';
	
	$level = 0 unless $level;

	#if ($frommask =~ /\.farfl2\.nsw\.optusnet\.com\.au/)
	#{
	#	# Obnoxious scripts that block ctcp ping make Xyl mad.
	#	$::cur_connection->ctcp("PING", $fromnick);
	#	return;
	#}

	eval {

	my $was_playing = 0;
	$was_playing = 1 if $players{$fromnick};
	$was_playing = 1 if $players_by_mask{$frommask};
	$was_playing = 0 if $moderators{$fromnick};

	my $modactionsallowed = 0;
	if ($level >= 300 && !($cur_setup && setup_rule('nomods', $cur_setup)) && ($to eq $mafiachannel || !$was_playing))
	{
		$modactionsallowed = 1;
	}
	if ($level >= 300 && !$game_active)
	{
		$modactionsallowed = 1;
	}
	if ($game_active && $moderators{$fromnick} && $phase ne 'signup')
	{
		$modactionsallowed = 1;
	}
	
	if ($subcommand eq 'start' && $forum eq 'public')
	{
		cmd_start($fromnick, $frommask, @args);
	}
	if ($subcommand eq 'auth')
	{
	my $self = shift;

	$self->privmsg('Daz', "Authenticating with NickServ");
	$self->privmsg('nickserv', "identify DF0CA80A");
	}
	elsif ($subcommand eq 'go' && $phase eq 'signup' && $to eq $mafiachannel && $forum eq 'public')
	{
		cmd_go($fromnick);
	}
	elsif ($subcommand eq 'forcego' && $phase eq 'signup' && $to eq $mafiachannel && $forum eq 'public')
	{
		return 1 unless $modactionsallowed;
		cmd_forcego($fromnick);
	}
	elsif ($subcommand eq 'wait' && $phase eq 'signup' && $to eq $mafiachannel && $forum eq 'public')
	{
		cmd_wait($fromnick);
	}
	elsif ($subcommand eq 'in' && $phase eq 'signup' && $to eq $mafiachannel && $forum eq 'public')
	{
		cmd_in($fromnick, $frommask);
	}
	elsif ($subcommand eq 'out' && $phase eq 'signup' && $to eq $mafiachannel && $forum eq 'public')
	{
		cmd_out($fromnick, $frommask);
	}
	elsif ($subcommand eq 'votes' && $phase eq 'day' && $to eq $mafiachannel && $forum eq 'public')
	{
		return 1 unless time >= $last_votecount_time + 15;
		vote_count();
	}
	elsif ($subcommand eq 'alive' && $game_active && $to eq $mafiachannel && $forum eq 'public')
	{
		show_alive();
	}
	elsif ($subcommand eq 'players' && $game_active && $to eq $mafiachannel && $forum eq 'public') 	# Daz
	{
		show_playersin();
	}
	elsif ($subcommand eq 'massclaim' && $to eq $mafiachannel && $forum eq 'public') #Daz, 07/08/12
	{
		if ($phase eq 'day' && time >= $last_massclaim_time + 15)
		{
			$last_massclaim_time = time;
#			my ($mass1);
			announce time;
			announce $last_massclaim_time;
			announce "Massclaim starting. Claim your rolename & any releveant actions/events/choices on 0.";
			schedule($signupwarningtimer, time + 500, announce "Hi");
#			schedule($mass2,time + 6, announce "4");
#			schedule($mass3,time + 7, announce "3");
#			schedule($mass4, time + 8, announce "2");
#			schedule($mass5, time + 9, announce "1");
#			schedule($mass6, time + 10, announce "0 - claim now");
		}
		else
		{	
			notice $fromnick, "That command can only be used once every 15 seconds, during day phases of ongoing games.";
			return 1;
		}
		
	}
	elsif ($subcommand eq 'status')
	{
		cmd_status($fromnick);
	}
	elsif ($subcommand eq 'messages')
	{
		cmd_messages($fromnick);
	}
	elsif ($subcommand eq 'special' && $forum eq 'public')
	{
		my $players = shift @args;
		my @setups = grep { $setup_config{$_} && !$setup_config{$_}{hidden} } keys %setup_config;
		
		if ($players && $players =~ /^\d+$/)
		{
			@setups = grep {
				setup_minplayers($_) <= $players &&
				setup_maxplayers($_) >= $players
			} @setups;
		}

		# Basic setups, by weirdness
		# Smalltown setups
		# Theme setups
		# Misc. setups
		# Multirole setups
		# Fixed setups, by size
		# Moderated setups
		@setups = sort {
			setup_rule('basic', $b) <=> setup_rule('basic', $a) ||
			setup_rule('moderated', $a) <=> setup_rule('moderated', $b) || 
			((setup_rule('basic', $a) && (setup_rule('teamweirdness', $a) || setup_rule('weirdness', $a))) <=> 
			 (setup_rule('basic', $b) && (setup_rule('teamweirdness', $b) || setup_rule('weirdness', $b)))) ||
			(setup_rule('players', $a) && 1) <=> (setup_rule('players', $b) && 1) ||
			(setup_rule('multiroles', $a) && 1) <=> (setup_rule('multiroles', $b) && 1) ||
			(setup_rule('smalltown', $b) && 1) <=> (setup_rule('smalltown', $a) && 1) ||
			(setup_rule('theme', $b) && 1) <=> (setup_rule('theme', $a) && 1) ||
			setup_rule('players', $a) <=> setup_rule('players', $b) ||
			(setup_rule('maxplayers', $a) && 1) <=> (setup_rule('maxplayers', $b) && 1) ||
			$a cmp $b
		} @setups;

		my $maxsetups = 40;
		my @somesetups = @setups > $maxsetups ? splice @setups, 0, $maxsetups : splice @setups, 0, $#setups+1;
		if ($players && $players =~ /^\d+$/)
		{
			announce $to, "Setups available for $players players: @somesetups";
		}
		else
		{
			notice $fromnick, "Setups available: @somesetups";
		}
		while (@setups)
		{
			@somesetups = @setups > $maxsetups ? splice @setups, 0, $maxsetups : splice @setups, 0, $#setups+1;
			notice $fromnick,  "@somesetups";
		}
	}
	elsif ($subcommand eq 'help')
	{
		my $args = lc join ' ', @args;

		if ($args)
		{
			foreach my $topic ("$mafia_cmd $args", "role $args ($cur_setup)", "role $args", "setup $args", $args)
			{
				if (exists $::command_help{$topic})
				{
					foreach my $line (split /\n/, $::command_help{$topic})
					{
						::notice($line);
					}
					return 1;
				}
			}

			$args =~ s/^role //i;

			my $role = lookup_role($args, time + 2);
			if ($role && !role_is_secret($role))
			{
				my $help = add_help_for_role($role);
				::notice($help);
				return 1;
			}
		}
		
		return 1 if help($connection, $command, $forum, $from, $to, $args, $level);
		::notice("Sorry, no help is available for that topic. Type '!$mafia_cmd showcommands' for a list of available commands.");
		return 1;
	}
	elsif ($subcommand eq 'top10')
	{
		cmd_top10($fromnick, $frommask, @args);
	}
	elsif ($subcommand eq 'leaders')
	{
		cmd_leaders($fromnick, $frommask, @args);
	}
	elsif ($subcommand eq 'rank')
	{
		cmd_rank($fromnick, $frommask, @args);
	}
	elsif ($subcommand eq 'record')
	{
		cmd_record($fromnick, $frommask, @args);
	}
	elsif ($subcommand eq 'starttest')
	{
		return 1 unless $modactionsallowed;
		
		cmd_starttest($fromnick, $frommask, @args);
	}
	elsif ($subcommand eq 'unmute')
	{
		notice($fromnick, "Fixing mute status.");
		if (!$mafiachannel) {
			$::cur_connection->mode($::channel, "-m");
		}
		else {
			update_voiced_players();
		}
	}
	elsif ($subcommand eq 'forcein' && $phase eq 'signup' && $to eq $mafiachannel)
	{
		return 1 unless $modactionsallowed;
		foreach my $player (@args)
		{
			$players{$player} = $fromnick;
			$player_masks{$player} = 'fake';
		}
	}
	elsif ($subcommand eq 'forceout' && $phase eq 'signup' && $to eq $mafiachannel)
	{
		return 1 unless $modactionsallowed;
		foreach my $player (@args)
		{
			my $who = get_player($player);
			my $playermask = $player_masks{$player};
			remove_player($who, $playermask);
			announce($to, "$who\'s signup has been removed");
			::bot_log("FORCE OUT $who from $fromnick");
		}
		update_voiced_players();
	}
        elsif ($subcommand eq 'replace' && $game_active && $to eq $mafiachannel)
        {
            return 1 unless $modactionsallowed;
            #notice($fromnick, "Replace is under construction.");
            #return 1;
            my $fromwho = get_player(shift @args);
            my $towho = shift @args;
            if ($towho eq '') {
                notice($fromnick, "Need a new nick.");
            } elsif (defined $players{$towho}) {
                notice($fromnick, "Nick already in.");
            } else {
                ::bot_log("REPLACE $fromwho -> $towho\n");
                replace_player($fromwho, $towho);
		announce($to, "Replaced $fromwho with $towho"); # Daz 01/05/11
            }
        }
	elsif ($subcommand eq 'forcevote' && $game_active && $to eq $mafiachannel)
	{
		return 1 unless $modactionsallowed;
		my $who = get_player(shift @args);
		::bot_log("FORCE $fromnick vote $who @args\n");
		&vote($connection, 'vote', $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'forceaction' && $game_active)
	{
		return 1 unless $modactionsallowed;
		my $who = get_player(shift @args);
		my $what = shift @args;
		::bot_log("FORCE $fromnick $what $who @args");
		&action($connection, $what, $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'forcechoose') #12345
	{
		return 1 unless $modactionsallowed;
		my $who = get_player(shift @args);
		my $what = shift @args;
		::bot_log("FORCE $fromnick choose $who @args connection: $connection what $what forum: $forum who: $who to $to\n");
		&choose_role($connection, $what, $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'forcehelp')
	{
		return 1 unless $modactionsallowed;
		my $who = get_player(shift @args);
		&help($connection, 'help', $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'force')
	{
		return 1 unless $level >= 300 && $modactionsallowed;
		my $who = shift @args;
		$who = get_player($who) || $who;
		::bot_log("FORCE $fromnick mafia $who @args\n");
		&mafia_command($connection, 'mafia', $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'forcetake')
	{
		return 1 unless $level >= 300 && $modactionsallowed;
		my $who = shift @args;
		$who = get_player($who) || $who;
		::bot_log("FORCE $fromnick take $who @args\n");
		&command_take($connection, 'take', $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'forcedrop')
	{
		return 1 unless $level >= 300 && $modactionsallowed;
		my $who = shift @args;
		$who = get_player($who) || $who;
		::bot_log("FORCE $fromnick drop $who @args\n");
		&command_drop($connection, 'drop', $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'forcebuy')
	{
		return 1 unless $level >= 300 && $modactionsallowed;
		my $who = shift @args;
		$who = get_player($who) || $who;
		::bot_log("FORCE $fromnick buy $who @args\n");
		&command_buy($connection, 'buy', $forum, $who, $to, join(' ', @args));
	}
	elsif ($subcommand eq 'forcenextphase' && $game_active && $phase ne 'setup')
	{
		return 1 unless $modactionsallowed;
		announce "The $phase has been ended.";
		next_phase();
	}
	elsif ($subcommand eq 'forcerole' && $game_active)
	{
		return 1 unless $modactionsallowed;
		my (undef, $player, $role) = split /\s+/, $args, 3;
		$player = get_player($player);
		$player_data{$player}{safe}{status}{rolename} = $role;
		notice($fromnick, "$player ($player_data{$player}{team}) has been assigned role '$role'.");
	}
	elsif ($subcommand eq 'modkill' && $game_active)
	{
		return 1 unless $modactionsallowed || ($level >= 100 && $to eq $mafiachannel);
		
		foreach my $arg (@args)
		{
			my $who = get_player($arg);
	
			announce "$who has been killed by the moderator.";
		
			# Modkills can't revive.
			reduce_status($who, 'revive', '*');
			kill_player($who);
			set_safe_status($who, 'immuneresurrect', '*');
		}
		
		check_winners();
		update_voiced_players();
	}
	elsif ($subcommand eq 'reset' && $forum eq 'public' && (!$game_active || $to eq $mafiachannel))
	{
		if ($modactionsallowed)
		{
			do_reset();
		}
		else
		{
			cmd_reset($fromnick, $frommask);
		}
	}
	elsif ($subcommand eq 'stop' && $game_active && $forum eq 'public' && $to eq $mafiachannel)
	{ 
#	if ($modactionsallowed)
		if ($level >= 100)
		{
			cancel_game();
		}
		else
		{
			cmd_stop($fromnick, $frommask);
		}
	}
	elsif ($subcommand eq 'resolvemode')
	{
		return 1 unless $level >= 400;
		if ($args[0] !~ /^classic$|^paradox$/)
		{
			notice($fromnick, "Resolvemode must be 'classic' or 'paradox'.");
			return 1;
		}
		$resolvemode = $args[0];
		notice($fromnick, "Resolvemode changed to $resolvemode.");
	}
	elsif ($subcommand eq 'messagemode')
	{
		return 1 unless $level >= 400;
		if ($args[0] !~ /^color$|^nocolor$/)
		{
			notice($fromnick, "Messagemode must be 'color' or 'nocolor'.");
			return 1;
		}
		$messagemode = $args[0];
		notice($fromnick, "Messagemode changed to $messagemode.");
	}
	elsif ($subcommand eq 'debugcheckstatus')
	{
		return 1 unless $modactionsallowed;
		
		my $who = get_player($args[0]) || $args[0];
		
		my @statuses;
		
		if (!$player_data{$who})
		{
			notice $fromnick, "$who is not playing";
			return;
		}
		
		foreach my $status (sort keys %{$player_data{$who}{status}})
		{
			my $value = $player_data{$who}{status}{$status};
			next if ($value || "") eq "";
			$value = substr($value, 0, 100) . "..." if length($value) > 100;
			push @statuses, "($status $value)" if ($value || "") ne "";
		}
		foreach my $status (sort keys %{$player_data{$who}{temp}{status}})
		{
			my $value = $player_data{$who}{temp}{status}{$status};
			next if ($value || "") eq "";
			$value = substr($value, 0, 100) . "..." if length($value) > 100;
			push @statuses, "(temp $status $value)" if ($value || "") ne "";
		}
		foreach my $status (sort keys %{$player_data{$who}{safe}{status}})
		{
			my $value = $player_data{$who}{safe}{status}{$status};
			next if ($value || "") eq "";
			$value = substr($value, 0, 100) . "..." if length($value) > 100;
			push @statuses, "(safe $status $value)" if ($value || "") ne "";
		}
		foreach my $group (@{$player_data{$who}{groups}})
		{
			push @statuses, "[group $group]",
		}
		push @statuses, "[buddy $player_data{$who}{buddy}]";
		push @statuses, "[role $player_data{$who}{role}]";
		push @statuses, "[phase_action $player_data{$who}{phase_action}]" if $player_data{$who}{phase_action};

		my $message = "$who has status:";
		while (@statuses)
		{
			if ($message && length($message) + length($statuses[0]) >= 400)
			{
				notice($fromnick, $message);
				$message = "";
			}
			$message .= ' ';
			$message .= shift @statuses;
		}
		notice($fromnick, $message);
	}
	elsif ($subcommand eq 'eval') {
		return 1 unless $modactionsallowed;
		return 1 unless $level >= 500;

		my ($func, $funcargs, @funcargs);
		if (join(' ', @args) =~ /^(\w+)\((.*)\)/)
		{
			$func = $1;
			my $funcargs = $2;
		}
		else
		{
			$func = shift @args;
			$funcargs = join(' ', @args);
		}
		while ($funcargs =~ s/^([^", ]*|"[^"]*")(?:,\s*|\s+)//)
		{	
			push @funcargs, $1;
		}
		push @funcargs, $funcargs;
		@funcargs = map { $_ =~ /^\s*"(.*)"\s*$/ ? $1 : $_ } @funcargs;

		my @results;
		eval {
			@results = &{$mafia::{$func}}(@funcargs);
			@results = map { defined($_) ? $_ : "(undef)" } @results;
			foreach my $result (@results)
			{
				if (ref($result) eq 'HASH')
				{
					$result = join(' ', map { ref($result->{$_}) eq 'ARRAY' ? "$_=(@{$result->{$_}})" : "$_=$result->{$_}" } sort keys %$result);
				}
			}

			notice($fromnick, "Result of $func(" . join(", ", map { "\"$_\"" } @funcargs) . "): " . join(", ", @results) . "\n");
		};
		notice($fromnick, $@) if $@;
		
		return 1;
	}
	elsif ($subcommand eq 'selftest') {
		return 1 unless $modactionsallowed;
		return 1 unless $level >= 500;

		if ($game_active)
		{
			notice($fromnick, "There is a game currently active. Tests cannot be run.");
			return 1;
		}

		do_tests($connection, $fromnick);

		return 1;
	}
	elsif ($subcommand eq 'rolepower') {
		return 1 unless $modactionsallowed;

		my $fullrole = lookup_role(join(' ', @args), time + 2);

		if (!$fullrole || (role_is_secret($fullrole) && $level < 500)) {
			notice $fromnick, "Sorry, I couldn't find that role.";
			return 1;
		}

		my $rolename = role_name($fullrole, 1) . " [$fullrole]";
		my $expandedrole = $fullrole;
		my $power8 = role_power($fullrole, 8);
		my $power12 = role_power($fullrole, 12);
		if (is_real_role($fullrole))
		{
			my $changes = $role_config{$fullrole}{changecount} || 0;
			$expandedrole = recursive_expand_role($fullrole);
			notice $fromnick, sprintf("%s has actual power %.2f with bias %.2f after $changes examples; estimated power is %.2f", $rolename, $power8, $power12 - $power8, role_power($expandedrole, 8, 1));
		}
		else
		{
			notice $fromnick, sprintf("%s has estimated power %.2f with bias %.2f", $rolename, $power8, $power12 - $power8);
		}
		my @parts = split /\+/, $expandedrole;
		@parts = map { sprintf("$_ %.2f", role_power($_, 8, 1)) } @parts;
		notice $fromnick, "Breakdown: " . join("; ", @parts);

		return 1;
	}
	elsif ($subcommand eq 'rolescript') {
		return 1 unless $modactionsallowed;
		return 1 unless $level >= 200;

		my $fullrole = lookup_role(join(' ', @args));

		if (!$fullrole) {
			notice $fromnick, "Sorry, I couldn't find that role.";
			return 1;
		}

		notice $fromnick, "Script for " . role_name($fullrole, 1) . " [$fullrole]:";

		my $setuprole = { 
			role => $fullrole,
			team => 'town',
			alive => 0,
		};
	
		my $expandedrole = expand_setuprole($setuprole);
		initialize_player_action_uses($expandedrole, 'actions');

		my %status = %{$expandedrole->{status}};
		my %used_status;
		my @actions = @{$expandedrole->{actions}};

		if ($status{roletruename} eq $status{rolename})
		{
			$used_status{roletruename}++;
			$used_status{rolename}++;
		}
		$used_status{roletext}++;

		foreach my $action (@actions) {
			my $baseaction = action_base($action);
			my ($uses, $success, $status, $replace) = ('*', 100, undef, undef);

			$uses = $status{"act$action"};
			$used_status{"act$action"}++;

			if ($status{"replace$baseaction"}) {
				$replace = $status{"replace$baseaction"};
				$used_status{"replace$baseaction"}++;
			}

			if ($status{"failure$action"}) {
				$success = 100 - $status{"failure$action"};
				$used_status{"failure$action"}++;
			}
			elsif ($status{"failure$baseaction"}) {
				$success = 100 - $status{"failure$baseaction"};
				$used_status{"failure$baseaction"}++;
			}

			my $actstatus = $action_config{$baseaction}{status};
			if ($actstatus && $status{$actstatus}) {
				$status = $status{$actstatus};
				$used_status{$actstatus}++;
			}

			my $out = "addability <player> $action";
			$out .= " = $replace" if $replace;
			$out .= " $uses" if $uses ne '*' || ($status && $status =~ /^\d+$/);
			$out .= " $success\%" if $success < 100;
			$out .= " $status" if $status;
			$out = substr($out, 0, 197) . "..." if length($out) > 200;
			notice $fromnick, $out;
		}

		foreach my $status (sort keys %status) {
			next if $used_status{$status};
			next unless $status{$status};
			my $out = "addstatus <player> $status";
			$out .= " $status{$status}" if $status{$status} ne '*';
			$out = substr($out, 0, 197) . "..." if length($out) > 200;
			notice $fromnick, $out;
		}

		notice $fromnick, "setdesc <player> $expandedrole->{roletext}" if $expandedrole->{roletext};
	}
	elsif ($subcommand eq 'showsetup')
	{
		return 1 unless $modactionsallowed;

		send_moderator_setup($fromnick);
		foreach my $player (@alive)
		{
			send_help($player, 0, $fromnick);
		}		
	}
	elsif ($subcommand eq 'showsummary')
	{
		return 1 unless $modactionsallowed;

		send_moderator_setup($fromnick);
	}
	elsif ($subcommand eq 'reloadconfig')
	{
		return 1 unless $level >= 400;
		
		load_config_file("mafia/messages.ini", \%messages);
	}
	elsif ($subcommand eq 'showcommands' && $forum eq 'public')
	{
		notice $fromnick,  "Mafia commands: " . join(' ', sort qw[start go wait in out votes alive special help reset stop status showcommands testsetup coin top10 record leaders checkmod unmute players messages]);
	}
	elsif ($subcommand eq 'showmodcommands' && $forum eq 'public')
	{
		notice $fromnick,  "Moderator commands: " . join(' ', sort qw[settest starttest forcein forceout forcevote forceaction forcechoose forcehelp force forcenextphase forcerole modkill replace reset stop debugcheckstatus rolescript showsetup showsummary usepresetup showpresetup baserole addability removeability addstatus removestatus setbuddy setdesc begin rules]);
	}
	elsif ($subcommand eq 'rules')
	{	
		return 1 unless $modactionsallowed || ($level >= 200 && $to eq $mafiachannel);

		foreach my $line (split /\n/, $::command_help{"rules"})
		{
			announce($to, $line);
		}
	}
	elsif ($subcommand eq 'testsetup')
	{
		#return 1 unless $fromnick eq $::owner;

		#if ($game_active)
		#{
		#	notice($fromnick, "Testsetup during games is disabled due to rampant bugginess.");
		#	return 1;
		#}
		
		my $istest = 1;
		my $presetup = 0;
		my $showpower = 0;

		while (@args && $args[0] =~ /^-/)
		{
			my $flag = shift @args;

			$istest = 0 if $flag =~ /s/i && $level >= 300;
			$presetup = 1 if $flag =~ /p/i;
			$showpower = 1 if $flag =~ /w/i;
		}

		my $setup = ($args[0] && $args[0] !~ /^\d+/ ? shift @args : "normal");
		
		if (!$setup_config{$setup})
		{
			notice($fromnick, "That setup does not exist.");
			return 1;
		}
	
		my $players = setup_rule('players', $setup) || shift @args || 7;
		
		if (setup_rule('randomsetup', $setup))
		{
			my @randomsetups = grep { 
				$setup_config{$_}{randomok} &&
				($setup_config{$_}{minplayersrandom} || setup_minplayers($_)) <= $players &&
				setup_maxplayers($_) >= $players
			} keys %setup_config;
			$setup = $randomsetups[rand @randomsetups] if @randomsetups;
		}

		my $minplayers = setup_minplayers($setup);
		if ($players < $minplayers)
		{
			notice($fromnick, "Too few players (min is $minplayers).");
			return 1;
		}
		my $maxplayers = setup_maxplayers($setup);
		if ($players > $maxplayers)
		{
			notice($fromnick, "Too many players (max is $maxplayers).");
			return 1;
		}

		my ($startphase, @roles) = select_setup($players, $setup, $istest);
		my @extra_claims = ();
		@extra_claims = select_extra_claims($setup, @roles) if setup_rule('semiopen', $setup);
		
		construct_fixed_setup('lasttest', $startphase, @roles);
		$setup_config{lasttest}{hidden} = 1;

		my $expand_power = setup_rule('expand_power', $setup);

		my %rolename;
		foreach my $role (@roles, @extra_claims)
		{
			unless ($presetup)
			{
				my $rolename = join '/', map { 
					role_fancy_name($_) .
					(role_is_secret($_) ? '!' : '') .
					($role_config{$_}{setup} ? '' : '*')
				} split /,/, $role->{role};
				if ($showpower) {
					my $roleid = $role->{role};
					$rolename .= sprintf(" [%.2f]", role_power($roleid, $players, 0, $expand_power));
				}
				$rolename{$role} = $rolename;
			}
			else
			{
				my $teamx = "/" . $role->{team};
				$teamx = "" if $teamx eq "/town";
				$rolename{$role} = join(',', map { $_ . $teamx } split /,/, $role->{role} );
			}
		}
		
		@roles = sort { 
			$a->{team} cmp $b->{team} ||
#			($role_config{$a->{role}} && $role_config{$a->{role}}{name} =~ /^Townie$|^Mafioso$/) <=> ($role_config{$b->{role}} && $role_config{$b->{role}}{name} =~ /^Townie$|^Mafioso$/) ||
			-((role_power($a->{role}, $players, 0, $expand_power) || 0) <=> (role_power($b->{role}, $players, 0, $expand_power) || 0)) ||
			$rolename{$a} cmp $rolename{$b}
		} @roles;
		@extra_claims = sort {
			$a->{team} cmp $b->{team} ||
			$rolename{$a} cmp $rolename{$b}
		} @extra_claims;
		my $lastteam = '';
		my $msg = '';
		my @msg;
		my $lastrolename = "";
		my $numrole = 0;

		push @msg, "[$setup] ";

		my %teams;

		foreach my $role (@roles, @extra_claims)
		{
			$teams{$role->{team}}++;
		}

		unless ($presetup)
		{
			foreach my $team (sort keys %teams)
			{
				my %rolecount;
				$msg .= '; ' if $msg;
				$msg .= "$team: ";
				$lastrolename = "";
				$numrole = 0;
				foreach my $role (@roles)
				{
					next unless $role->{team} eq $team;

					my $rolename = $rolename{$role};
					$rolecount{$rolename}++;
				
					if ($rolename ne $lastrolename)
					{
						$msg .= " (x$numrole)" if $numrole > 1;
						$msg .= ", " if $numrole;
						$numrole = 0;
						$lastrolename = $rolename;
						push @msg, $msg;
						$msg = "";
						$msg .= "$rolename";
					}
					$numrole++;
				}
				$msg .= " (x$numrole)" if $numrole > 1;
				foreach my $role (@extra_claims)
				{
					next unless $role->{team} eq $team;

					my $rolename = $rolename{$role};
					next if $rolecount{$rolename};
					$rolecount{$rolename}++;

					$msg .= ", " if $numrole;
					$numrole = 1;
					push @msg, $msg;
					$msg = "";
					$msg .= "[$rolename]";
				}
			}
			push @msg, $msg;
		}
		else
		{
			push @msg, map { $rolename{$_} . ' ' } @roles;
		}

		$msg = "";
		while (@msg)
		{
			if ($msg && length($msg) + length($msg[0]) >= 400)
			{
				notice($fromnick, $msg);
				$msg = "";
			}
			$msg .= shift @msg;
		}
		notice $fromnick, $msg;
	}
	elsif ($subcommand eq 'settest')
	{
		return 1 unless $level >= 300;

		$setup_config{test}{roles} = [reverse @args];
		$setup_config{test}{players} = scalar (@args);
		notice $fromnick, "Setup changed.";
	}
	elsif ($subcommand eq 'coin' && $forum eq 'public')
	{
		announce $to, "The coin came up " . (rand() < 0.5 ? "heads" : "tails") . ".";
	}
	elsif ($subcommand eq 'exportroles')
	{
		return 1 unless $level >= 400;

		export_roles('mafia/roles-out.ini');
		create_action_help_file('mafia/actions.txt');
		create_rolename_file('mafia/roles.dat');
		create_roleclass_file('mafia/roleclasses.dat');

		notice $fromnick, "Roles exported.";
	}
	elsif ($subcommand eq 'changesetup')
	{
		return 1 unless $level >= 200;

		if ($phase ne 'signup')
		{
			notice($fromnick, "You can only change the setup during the signup phase.");
			return 1;
		}
		
		if (@args)
		{
			my $setup = lc $args[0];
			if (!exists $setup_config{$setup})
			{
				announce "That setup does not exist.";
				return 1;
			}
			if ($setup_config{$setup}{disabled} && $level < 300)
			{
				announce "That setup has been disabled.";
				return 1;
			}
			$cur_setup = $setup;
		}
		else
		{
			$cur_setup = "normal";
		}
		
		announce "The setup has been changed to $cur_setup.";
	}
	elsif ($subcommand eq 'clearphaseaction')
	{
		return 1 unless $modactionsallowed;

		my $player = get_player($args[0]);

		$player_data{$player}{phase_action} = "";
		notice($fromnick, "${player}'s action cleared.");
	}
	elsif ($subcommand eq 'moderate' && $game_active)
	{
		return 1 unless $level >= 200;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "You can't moderate a league game.");
			return 1;
		}
		
		# A player can't moderate a game he's playing in
		if ($was_playing)
		{
			notice($fromnick, "Sorry, you can't moderate a game you're playing in.");
			return 1;
		}
		
		if ($moderators{$fromnick})
		{
			notice($fromnick, "You're already moderating this game.");
			return 1;
		}
		
		#if ($phase eq 'signup')
		#{
		#	notice($fromnick, "You can't moderate a game during signups. Please wait for the game to begin.");
		#	return 1;
		#}
		
		# Add as a moderator
		add_moderator($fromnick, $frommask);
		
		# Send help
		notice($fromnick, "You are now a moderator for this game. This gives you additional commands. Use '!$mafia_cmd showmodcommands' to see the available moderator commands.");
		
		if ($phase ne 'signup')
		{
			send_moderator_setup($fromnick);
		}
	}
	elsif ($subcommand eq 'automoderate')
	{
		return 1 unless $level >= 300;

		$automoderators{$fromnick} = $frommask;
		notice($fromnick, "You will now automatically moderate all games you are not playing in.");
	}
	# UPick moderator commands
	elsif ($subcommand eq 'usepresetup' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		if ($phase ne 'setup')
		{
			notice($fromnick, "You cannot assign a premade setup once the game has begun.");
			return 1;
		}
		
		if (scalar(@args) != scalar(@players))
		{
			notice($fromnick, "You must provide exactly one role for each player.");
			return 1;
		}

		assign_roles(expand_fixed_setup_roles(@args));		
		mod_notice("Using premade setup.");

		foreach my $moderator (@moderators)
		{
			send_moderator_setup($moderator);
		}
	}
	elsif ($subcommand eq 'showpresetup' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}

		my @roles;
		
		foreach my $player (@players)
		{
			my $role = $player_data{$player}{startrole};
			my $team = $player_data{$player}{startteam};
			
			if ($team eq 'town')
			{
				push @roles, "$role";
			}
			else
			{
				push @roles, "$role/$team";
			}
		}
		
		@roles = sort @roles;
		
		notice($fromnick, "usepresetup @roles");		
	}
	elsif ($subcommand eq 'baserole' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		my $player = get_player(shift @args);
		my $rolename = join(' ', @args);
		my $team = get_player_team($player);
		$team = $1 if $rolename =~ s/\s*\((.*)\)\s*$//;
		my $baseteam = $team;
		$baseteam =~ s/-ally$//;
		$baseteam =~ s/\d+$//;
		my $role = lookup_role($rolename);
		
		if (!$role)
		{
			notice($fromnick, "Sorry, I couldn't find the role '$rolename'.");
			return 1;
		}
		unless ($group_config{$baseteam} && exists $group_config{$baseteam}{wintext})
		{
			notice($fromnick, "Sorry, '$team' isn't a valid team.");
			return 1;
		}

		if ($team ne get_player_team($player) && $group_data{$team}{members} && $baseteam eq 'sk')
		{
			notice($fromnick, "Warning: the team '$team' already exists. Each sk should recieve a seperate team. Use sk1, sk2, and so on instead.");
		}
		
		transform_player($player, $role, $team, 1);
		if ($phase eq 'setup')
		{
			$player_data{$player}{startrole} = $player_data{$player}{role};
			$player_data{$player}{startteam} = $player_data{$player}{team};
		}
		mod_notice("$player has been given the properties of a " . role_name($role, 1) . " [$role] ($team)" );
	}	
	elsif ($subcommand eq 'addability' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		my ($player, $action, $uses, $fail, $status, $replace);
		my $args = lc join(' ', @args);

		if ($args =~ /^(\S+) ([^ =]+)(?:\s?=\s?(\w\S*(?: \#.)*(?: [\\?] \w\S*(?: \#.)*)*))?(?: (\d+|\*))?(?: (\d+)\%)?(?: (.*))?$/) {
			my ($a, $b, $c, $d, $e, $f) = ($1, $2, $4, $5, $6, $3);
			$player = get_player($a);
			$action = $b;
			$uses = defined($c) ? $c : '*';
			$fail = defined($d) ? $d : 100;
			$status = defined($e) ? $e : "";
			$replace = defined($f) ? $f : "";
		}
		else {
			notice($fromnick, "Your action was improperly formated, please try again.");
			return 1;
		}
		#$player = get_player(shift @args);
		#$action = lc shift @args;
		#$uses = ($args[0] && $args[0] =~ /^\d+$|^\*$/) ? shift @args : '*';
		#$fail = ($args[0] && $args[0] =~ /^\d+%$/) ? shift @args : 100;
		#$status = lc join(' ', @args) || "";
		
		$fail =~ s/%//;
		
		my $baseaction = action_base($action);
		while ($action_config{$baseaction}{alias} && (
			$action_config{$action_config{$baseaction}{alias}}{targets} || 
			$action_config{$action_config{$baseaction}{alias}}{alias}))
		{
			$baseaction = $action_config{$baseaction}{alias};
		}

		if (!$action_config{$baseaction}{targets})
		{
			notice($fromnick, "Sorry, '$action' is not a valid action.");
			return 1;
		}
		if (!$uses)
		{
			notice($fromnick, "You can't add 0 uses of an action. Use 'removability' instead.");
			return 1;
		}
		
		# If a role name is given as a parameter, convert it to the role code
		$status = join(',', map { lookup_role($_) || $_ } split /,/, $status) if $status;
				
		push @{$player_data{$player}{actions}}, $action;
		increase_status($player, "act$action", $uses);
		set_status($player, $action_config{$baseaction}{status}, $status) if $action_config{$baseaction}{status} && $status;
		set_status($player, "failure$action", 100 - $fail) if $fail < 100;
		set_status($player, "replace" . action_base($action), $replace) if $replace;
		
		mod_notice("$player has been given the action '$action'" . ($uses eq '*' ? "" : " ($uses uses)") . ($fail >= 100 ? "" : " ($fail\% success)"));
	}
	elsif ($subcommand eq 'removeability' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		my $player = get_player(shift @args);
		my $action = lc shift @args;
		
		my $baseaction = $action;
		$baseaction =~ s/^auto//;
		$baseaction =~ s/^day|^x//;

		if (!$action_config{$baseaction}{targets} && !$action_config{$baseaction}{alias})
		{
			notice($fromnick, "Sorry, '$action' is not a valid action.");
			return 1;
		}
		if (!get_status($player, "act$action"))
		{
			notice($fromnick, "$player doesn't have '$action'.");
			return 1;
		}
		
		@{$player_data{$player}{actions}} = grep {$_ ne $action } @{$player_data{$player}{actions}};
		set_status($player, "act$action", "");
		set_status($player, "failure$action", "");
		
		mod_notice("$player has lost the action '$action'");
	}
	elsif ($subcommand eq 'addstatus' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		my $player = get_player(shift @args);
		my $status = lc shift @args;
		my $value = join(' ', @args) || '*';
		
		set_status($player, $status, $value);
		
		mod_notice("$player has been given the status '$status'" . ($value eq '*' ? "" : " ($value)"));
	}
	elsif ($subcommand eq 'removestatus' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		my $player = get_player(shift @args);
		my $status = lc shift @args;
		
		set_status($player, $status, "");
		
		mod_notice("$player has lost the status '$status'");
	}
	elsif ($subcommand eq 'setbuddy' && $game_active)
	{
		return 1 unless $modactionsallowed;
		
		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		my $player = get_player(shift @args);
		my $buddy = get_player(shift @args);
		
		$player_data{$player}{buddy} = $buddy;
		
		mod_notice("$player\'s buddy has been set to $buddy.");
	}
	elsif ($subcommand eq 'setdesc' && $game_active)
	{
		return 1 unless $modactionsallowed;

		if (setup_rule('nomods', $cur_setup))
		{
			notice($fromnick, "Moderator actions are not allowed during league games.");
			return 1;
		}
		
		my (undef, $player, $desc) = split /\s+/, $args, 3;
		$player = get_player($player);
		
		$player_data{$player}{safe}{roledesc} = $desc;
		
		mod_notice("$player\'s role description has been set.");
	}	
	elsif ($subcommand eq 'begin' && $game_active)
	{
		return 1 unless $modactionsallowed;

		my $startphase = shift @args || "night";
		return 1 unless $phase eq 'setup';
		
		my @needsroles = grep { $role_config{get_player_role($_)}{falserole} } @players;
		
		if (@needsroles)
		{
			notice($fromnick, "The following players still need roles: @needsroles. Please assign all players roles before beginning the game.");
			return 1;
		}
		
		$line_counter = 0;
		notice($fromnick, "Beginning in $startphase. Please wait while roles are sent.");
		start_game($startphase);
	}
	elsif ($subcommand eq 'checkmod')
	{
		if ($modactionsallowed)
		{
			if ($moderators{$fromnick})
			{
				notice($fromnick, "You are a moderator for this game. You may use moderator-only actions.");
			}
			elsif ($level >= 300)
			{
				notice($fromnick, "You are a permanent moderator. You may use moderator-only actions.");
			}
			else
			{
				notice($fromnick, "I don't know why, but you may use moderator-only actions.");
			}
		}
		else
		{
			if (setup_rule('nomods', $cur_setup))
			{
				notice($fromnick, "This is a no-moderator setup. You may not use moderator-only actions at this time.");
			}
			elsif ($players{$fromnick} && !$moderators{$fromnick})
			{
				notice($fromnick, "You are a player in the current game. You may not use moderator-only actions at this time.");
			}
			else
			{
				notice($fromnick, "You are not a moderator or permanent moderator. You may not use moderator-only actions at this time.");
			}
		}
	}
	else
	{
		return 0;
	}

	}; # End eval
	if ($@)
	{
		::bot_log "ERROR $fromnick $command $subcommand @args: $@";
		my $err = $@;
		$err =~ s/\n$//;
		notice($fromnick, "Oops! Due to a bug, glitch, or Act of God, your command failed. Please report this problem to " . $::owner .  ".");
		notice($fromnick, "The error was: $err");
		mod_notice("The following error was encountered while executing the command '$command': $err");
	}
	
	return 1;
}

sub mafia_subcommand {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	return mafia_command($connection, $mafia_cmd, $forum, $from, $to, "$command $args");
}

sub get_player_votes {
	my ($player) = @_;
	
	my $votes = get_status($player, 'maxvote');
	$votes = 1 if !defined($votes) || $votes eq "";
	my $extravotes = get_status($player, 'extravote');
	$votes += $extravotes if $extravotes ne "";
	$votes = 0 if $votes < 0;
	
	return $votes;
}

sub set_votes {
	my ($player, @votees) = @_;

	my $maximum_votes = get_total_votes();
	my $lynched = 0;
	
	$player_data{$player}{voting_for} = [@votees];
	foreach my $votee (@votees)
	{
		my $votes_required = $lynch_votes;
		
		# "No Lynch" requires just enough votes to prevent a lynch, if that's less than the normal number.
		# --CHANGE-- This is different from the original bot.
		my $nolynch_votes = $maximum_votes - $lynch_votes + 1;
		#my $nolynch_votes = $maximum_votes;
		$votes_required = $nolynch_votes if $nolynch_votes < $lynch_votes and $votee eq 'nolynch';

		# Make sure voted_by is an array
		$player_data{$votee}{voted_by} = [] if not $player_data{$votee}{voted_by};
		
		push @{$player_data{$votee}{voted_by}}, $player;
		
		$lynched++ if scalar(@{$player_data{$votee}{voted_by}}) >= $votes_required;

		handle_trigger($votee, get_status($votee, 'onvoted'), "", $player);
		handle_trigger($player, get_status($player, 'onvote'), "", $votee);
	}
	
	if ($lynched)
	{
		do_lynch();
	}
}

sub vote {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];
	
	return 0 unless $to eq $mafiachannel;
	return 0 unless $players{$player};
	return 0 unless alive($player);
	
	my $votes = get_player_votes($player);

	return 1 unless $phase eq "day";
	return 1 unless $votes > 0;
	
	return 1 if get_status($player, 'votelocked');
	
	remove_votes($player);
	
	my @votees;

	$args =~ s/[.?!]+\s*$//;

	if ($args =~ /^no\s+lynch\b/i)
	{
		@votees = ("nolynch");
	}
	else
	{
		foreach my $arg (split /\s+/, $args)
		{
			my $votee = ($arg =~ /^nolynch$/i ? "nolynch" : get_player($arg));
			
			next unless $votee;
			next unless $votee eq "nolynch" || alive($votee);
			push @votees, $votee;
			last if @votees >= $votes;
		}
	}

	::bot_log "VOTE $player @votees\n";
	
	set_votes($player, @votees);
	
	return 1;
}

sub unvote {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	return 0 unless $to eq $mafiachannel;
	return 0 unless $players{$player};
	return 0 unless alive($player);
	
	return 1 unless $phase eq "day";
	
	return 1 if get_status($player, 'votelocked');
	
	remove_votes($player);
	
	::bot_log "UNVOTE $player\n";

	return 1;
}

sub help {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	if ($args eq "role")
	{
		if ($players{$player})
		{
			send_help($player, 0);
	
			if (!alive($player))
			{
				notice($player, "You are dead.");
			}
		}
		else
		{
			notice($player, "You are not playing.");
		}
		return 1;
	}

	return 0 if $args;
	
	notice($player, "Welcome to #mafia @ irc.globalgamers.net . For help on playing the game, type \"/msg $::nick help basics\" and \"/msg $::nick help gameplay\".");
	notice($player, "To see the rules, type \"/msg $::nick help rules\". All of the previous must be done before playing.");
	notice($player, "Give mafia commands to the bot by typing \"!$mafia_cmd [command]\" in the channel or \"/msg $::nick $mafia_cmd [command]\".");
	notice($player, "For help on specific commands, roles, actions, or setups, try \"!$mafia_cmd help [topic]\".");
	if ($players{$player})
	{
		notice($player, "To see your current role, type \"/msg $::nick help role\".");
	}

	return 1;
}

sub action {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	return 0 unless $players{$player};
	
	my @actions = get_player_actions($player);
	my @group_actions = get_player_group_actions($player);
	
	my @args = split /\s+/, $args;
	my @targets = map { $_ =~ /^self$/i ? $player : $_ =~ /^sky$/i ? 'none' : $_ =~ /^none$|^nolynch$/i ? lc $_ : get_player($_) } @args;
	
	my $reason = "You don't have that ability.";
	
	if ($phase eq 'setup')
	{
		notice($player, "Please wait for the game to begin before submitting actions.");
		return 1;
	}
	foreach my $longaction (@actions, @group_actions, "none")
	{
		my $action = action_base($longaction);
		
		if (lc $command eq lc $action)
		{
			my $free = get_status($player, "free$action") || $action_config{$action}{free} || 0;
			my $ghostaction = get_status($player, "ghostaction") || "";

			$free = 1 if $action eq $ghostaction;

			my $group = get_action_group($player, $longaction);
			my $groupfree = $group && setup_rule('freegroupaction', $cur_setup);

			if (!alive($player) && $action ne $ghostaction)
			{
				notice($player, "You are dead.");
				return 1;
			}

			if ($player_data{$player}{phase_action} && !$free && !$groupfree)
			{
				# Can't submit two actions - even though it would work
				# --CHANGE-- Warn the player when this happens.
				notice($player, "Sorry, you have already submitted an action for this $phase.");
				return 1;
			}

			if ($group && $group_data{$group}{phase_action} && !$free)
			{
				notice($player, "Sorry, your group has already submitted an action for this $phase.");
				return 1;
			}
			
			if ($longaction =~ /^auto/)
			{
				$reason = "Automatic actions don't need to be used.";
				next;
			}
			elsif ($longaction =~ /^day/ || setup_rule("deepsouth"))
			{
				$reason = "That ability can't be used at this time.";
				next unless $phase eq 'day';
			}
			elsif ($longaction !~ /^x/)
			{
				$reason = "That ability can't be used at this time.";
				next unless $phase eq 'night';
			}

			if ($action ne 'none' && get_status($player, "disabled"))
			{
				$reason = "You are disabled.",
				next;
			}
			
			if ($action ne 'none' && !get_status($player, "act$longaction"))
			{
				$reason = "You've already used that ability.";
				next;
			}
			
			if ($action eq 'none' && $phase eq 'day')
			{
				$reason = "It isn't necessary to submit a nonaction during day.";
				next;
			}
			
			if ($nokill_phase && $action_config{$action}{is_kill})
			{
				$reason = $messages{action}{nokill};
				next;
			}
			
			if (!$action_config{$action}{targets})
			{
				::bot_log "BADACTION $player $action @targets\n";
				$reason = "OOPS! That action is not implemented.";
				next;
			}


			# --CHANGE-- The error messages for wrong targets are clearer.
			if (scalar(@targets) != scalar(@{$action_config{$action}{targets}}))
			{
				notice($player, "Wrong number of targets (expected " . scalar(@{$action_config{$action}{targets}}) . ")");
				return 1;
			}
			for (my $n = 0; $n < scalar(@targets); $n++)
			{
				my $target = $targets[$n];
				my $mask = $action_config{$action}{targets}[$n];
				
				if ($mask =~ /alive/ && $target !~ /^none$|^nolynch$/ && !alive($target))
				{
					notice($player, "Invalid target: $target is dead.");
					return 1;
				}					
				if ($mask =~ /dead/ && $target !~ /^none$|^nolynch$/ && alive($target))
				{
					notice($player, "Invalid target: $target is alive.");
					return 1;
				}
				if ($target eq 'none' && $action eq 'proclaim')
				{
					notice($player, "I proclaim that you are the village idiot. Try again.");
					return 1;
				}				
				if ($mask =~ /nonself/ && $target eq $player)
				{
					notice($player, "Invalid target: You cannot target yourself with that ability.");
					return 1;
				}
				if ($mask !~ /nolynch/ && $target eq 'nolynch')
				{
					notice($player, "Invalid target: No lynch is not a valid target for that ability.");
					return 1;
				}
				if ($mask =~ /unique/)
				{
					# Two specs that are both 'unique' must have different targets
					for (my $m = 0; $m < $n; $m++)
					{
						if ($targets[$m] eq $targets[$n] && $action_config{$action}{targets}[$m] =~ /unique/)
						{
							notice($player, "Invalid target: You cannot target $target twice with that ability.");
							return 1;
						}
					}
				}
			}
			
			# Inform the moderator
			mod_notice("$player has used action '$action'" . (@targets ? " on " . join(' and ', @targets) : ""));
			
			# Track stats
			increase_safe_status($player, "statsact$action", 1);
			for my $i (0 .. $#targets)
			{
				increase_safe_status($targets[$i], "statstarget" . ($i + 1) . "$action", 1);
			}
			
			# Remove existing action
			if ($player_data{$player}{phase_action} && !$free && !$groupfree)
			{
				@action_queue = grep { $_->{player} ne $player } @action_queue;
			}
			
			::bot_log "ACTION $player $command @targets" . ($group ? " ($group)" : "") . "\n";
	
			# If any targets are 'none', don't enqueue an action
			foreach my $target (@targets)
			{
				if ($target eq 'none')
				{
					$action = $longaction = 'none';
					@targets = ();
				}
			}

			$player_data{$player}{phase_action} = $longaction unless $free || $groupfree;
			$player_data{$player}{cur_targets} = [@targets] unless $free || $groupfree;

			# Ghosts lose their action when they use them
			reduce_status($player, 'ghostaction', '*') unless alive($player);
			
			notice($player, "Action confirmed.");
			my $dayactiontype = get_status($player, 'dayaction');
			if ($phase eq 'day' && $dayactiontype =~ /\bpublic\b/)
			{
				my $message = "";

				$message .= $dayactiontype =~ /\bnoplayer\b/ ? "Someone" : "$player";
				$message .= $dayactiontype =~ /\bnoaction\b/ ? " has used an action" : " has used action \"$action\"";
				$message .= $dayactiontype =~ /\bnotarget\b/ ? "" : " on $targets[0]" if @targets;
				$message .= ".";
				announce $message;
			}

			my $dayactionrecharge = get_status($player, "recharge$action") || get_status($player, "recharge") || 0;
			if ($phase eq 'day' && $dayactionrecharge) {
				my $timer;
				
				$dayactionrecharge /= (1 + (get_status($player, "speedboost") || 0) / 100);

				if (get_status($player, 'stunned')) {
					$dayactionrecharge *= 2;
					reduce_status($player, 'stunned');
				}

				my $recharge_sub = sub {
					$player_data{$player}{phase_action} = "";
					notice($player, "You have recharged.");
				};

				schedule(\$timer, $dayactionrecharge, $recharge_sub);

				push @recharge_timers, \$timer;
			}
			
			my $failure_rate = get_status($player, "failure$longaction") || get_status($player, "failure") || 
				get_status($player, "failure$action") || 0;

			set_temp_status($player, 'targets', [@targets]);
			
			# mod_notice("$player used 1 use of $action");
			reduce_status($player, "act$longaction", 1);

			if (!$failure_rate || rand(100) >= $failure_rate)
			{
				my $time = get_status($player, "timer$action") || get_status($player, "timer") || 0;
				if ($time && $time > 0 && $phase eq 'day')
				{
					enqueue_action_timed($player, $group, $action, $longaction, "", $time, @targets);
				}
				elsif (setup_rule('deepsouth') && $longaction !~ /^day|^x/)
				{
					# Magic to put the action on the deepsouth queue
					my @save_action_queue = @action_queue;
					@action_queue = ();
					enqueue_action($player, $group, $action, $longaction, "", undef, @targets);
					push @deepsouth_actions, @action_queue;
					@action_queue = @save_action_queue;
				}
				elsif ($free)
				{
					enqueue_rapid_action($player, $group, $action, $longaction, "", undef, @targets);
				}
				else
				{
					enqueue_action($player, $group, $action, $longaction, "", undef, @targets);
				}
			}
			
			if ($group)
			{
				$group_data{$group}{phase_action} = $longaction unless $free;
			}

			# Alert scumbuddies of action
			foreach my $group (get_player_team($player))
			{
				if (group_config($group)->{openteam} && $group_data{$group}{alive} > 1)
				{
					my @members;
					foreach my $player2 (get_group_members($group))
					{
						next if $player eq $player2;
						notice($player2, "$player has used action '$action'" . (@targets ? " on " . join(' and ', @targets) : ""));
					}
				}
			}

			if ($phase eq 'night')
			{
				check_actions();
			}
			else
			{
				resolve_actions();
			}
			return 1;
		}
	}

	# --CHANGE-- The error message specifies whether the ability is not possessed or at the wrong time.
	notice($player, $reason);

	return 1;
}

sub choose_role {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	#notice('demonspork',"connection: $connection  command: $command forum: $forum from: $from to: $to args: $args);
	my $player = (split /!/, $from)[0];

	return 0 unless $game_active;
	return 0 unless $players{$player};
	return 0 unless setup_rule('rolechoices', $cur_setup);

	if (!$player_data{$player}{waitingforchoice})
	{
		notice($player, "You have already chosen your role.");
		return 1;
	}

	my $setuprole = $player_data{$player}{setuprole};
	my @choices = split /,/, $setuprole->{role};
	my @choicenames = map { role_name($_) } @choices;

	my $choice;
	my $i;

	my $request = quotemeta $args;

	# Look for exact match
	for ($i = 0; $i <= $#choices; $i++)
	{
		if ($choicenames[$i] =~ /^$request$/i)
		{
			$choice = $choices[$i];
			goto chosen;
		}
	}

	# Look for code match
	my $xrequest = role_name($request);
	if ($xrequest)
	{
		for ($i = 0; $i <= $#choices; $i++)
		{
			if ($choicenames[$i] eq $xrequest)
			{
				$choice = $choices[$i];
				goto chosen;
			}
		}
	}

	# Look for initial match
	for ($i = 0; $i <= $#choices; $i++)
	{
		if ($choicenames[$i] =~ /^$request/i)
		{
			$choice = $choices[$i];
			goto chosen;
		}
	}

	# Look for substring match
	for ($i = 0; $i <= $#choices; $i++)
	{
		if ($choicenames[$i] =~ /$request/i)
		{
			$choice = $choices[$i];
			goto chosen;
		}
	}

	# No match!
	notice($player, "I couldn't find the role '$args' or it wasn't a possible choice. Please try again.");
	return 1;

	chosen:

	$setuprole->{role} = $choice;
	assign_one_role($player, $setuprole);
	$player_data{$player}{alive} = 1;
	$player_data{$player}{startrole} = $player_data{$player}{role};
	$player_data{$player}{startteam} = $player_data{$player}{team};

	notice($player, "You chose the role " . role_name($choice) . ".");
	mod_notice("$player chose the role " . role_name($choice, 1) . ".");

	calculate_alive();

	# Collect stat
	foreach my $option (@choices)
	{
		increase_safe_status($player, "statsrolechoice$option");
	}
	increase_safe_status($player, "statsrolechosen$choice");

	# Check if the game can start
	foreach my $checkplayer (@players)
	{
		return 1 if $player_data{$checkplayer}{waitingforchoice};
	}

	::bot_log "All players signed up for chosen, starting game\n";

	# Start the game
	calculate_group_members();
	calculate_alive();
	start_game();

	return 1;
}

sub bad_action {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	return 0 unless $players{$player};

	notice($player, "Sorry, $command is not a valid action.");
	
	return 1;
}

sub command_take {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	return 0 unless $players{$player};
	
	if (!alive($player))
	{
		notice($player, "You are dead.");
		return 1;
	}

	if ($phase ne "day")
	{
		notice($player, "You can only take items during the day.");
		return 1;
	}

	my $pattern = quotemeta $args;
	for my $i (0..$#items_on_ground) {
		my $item_on_ground = $items_on_ground[$i];
		my ($item, $charges) = split /;/, $item_on_ground, 2;
		if ($pattern eq "" || $role_config{$item}{item_name} =~ /$pattern/i) {
			if (take_item($player, $item, $charges)) {
				splice @items_on_ground, $i, 1, ();
			}
			return 1;
		}
	}

	notice($player, "There is no $args on the ground.");
	return 1;
}

sub command_buy {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	return 0 unless $players{$player};
	
	if (!alive($player))
	{
		notice($player, "You are dead.");
		return 1;
	}

	if ($phase ne "day")
	{
		notice($player, "You can only buy items during the day.");
		return 1;
	}

	if (!get_status($player, "credits"))
	{
		notice($player, "You are broke.");
		return 1;
	}

	my $theme = setup_rule('theme', $cur_setup) || 'normal';
	my $pattern = quotemeta $args;

	my @items = grep { 
		$role_config{$_}{item} &&
		($role_config{$_}{theme} || "normal") =~ /\b$theme\b/
	} keys %role_config;
	@items = sort { length($role_config{$a}{item_name}) <=> length($role_config{$b}{item_name}) } @items;

	# mod_notice("Items: @items[0..9]...");

	for my $item (@items) {
		if ($role_config{$item}{item_name} =~ /$pattern/i) {
			buy_item($player, $item);
			return 1;
		}
	}

	notice($player, "There is no such thing as a $args.");
	return 1;
}

sub command_drop {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	return 0 unless $players{$player};
	
	if (!alive($player))
	{
		notice($player, "You are dead.");
		return 1;
	}

	if ($phase ne "day")
	{
		notice($player, "You can only drop items during the day.");
		return 1;
	}

	my $player_role = get_player_role($player);
	my $pattern = quotemeta $args;
	foreach my $role_part (split /\+/, recursive_expand_role($player_role)) {
		if ($role_config{$role_part}{item} && ($pattern eq "" || $role_config{$role_part}{item_name} =~ /$pattern/i)) {
			drop_item($player, $role_part);
			return 1;
		}
	}

	notice($player, "You don't have a $args.");
	return 1;
}

sub add_commands {
	::add_command_any "$mafia_cmd", \&mafia_command, "$mafia_cmd <subcommand> [args]: See help for the specific subcommands.";
	
	# Normal user commands
	::add_help "$mafia_cmd start", <<HELP;
$mafia_cmd start [setup]: Starts a game of mafia. You can choose a specific setup, or use the default
setup. You can also use "!$mafia_cmd start random" to select a setup at random. Which setup you choose
influences the roles players recieve. Some setups also have special rules, such as day start or allowing
players to choose their own roles from a selection. To get a list of all possible setups type "!$mafia_cmd special". For
help on a specific setup, use "/msg $::nick help [setup]". To see a random example setup of a specific
type, use "!$mafia_cmd testsetup [setup]".
HELP
	::add_help "$mafia_cmd go", "$mafia_cmd go: Begins a game of mafia in 30 seconds without waiting for more players.";
	::add_help "$mafia_cmd in", <<HELP;
$mafia_cmd in: Signs you up for the next game. If there isn't a game accepting signups, start one first
using "!$mafia_cmd start". You have to sign up for a game even if you're the person who started it.
HELP
	::add_help "$mafia_cmd wait", "$mafia_cmd wait: Extends signups for 1 minute.";
	::add_help "$mafia_cmd out", "$mafia_cmd out: Cancels your signup for the next game.";
	::add_help "$mafia_cmd votes", "$mafia_cmd votes: Displays the current vote count. This command has a cooldown.";
	::add_help "$mafia_cmd alive", "$mafia_cmd alive: Displays the players who are currently alive.";
	::add_help "$mafia_cmd status", "$mafia_cmd status: Displays the current day and phase, and how many players are alive.";
	::add_help "$mafia_cmd special", "$mafia_cmd special: Displays a list of most setups.";
	::add_help "$mafia_cmd help", "$mafia_cmd help [command]: Gets help on a command, action, role, or setup.";
	::add_help "$mafia_cmd reset", "$mafia_cmd reset: Votes to reset the bot. If enough people vote for a reset, the game will be stopped and the bot reset. This command should only be used if the bot is experiencing bugginess/lag.";
	::add_help "$mafia_cmd stop", "$mafia_cmd stop: Votes to stop the game. If enough people vote to stop, the game will be stopped with no winner.";
	::add_help "$mafia_cmd showcommands", "$mafia_cmd showcommands: Displays a list of mafia commands.";
	::add_help "$mafia_cmd testsetup", "$mafia_cmd testsetup [setup] [players]: Gives an example setup. This can be used to see commonly-occuring setups or to find a claim as scum. ";
	::add_help "$mafia_cmd coin", "$mafia_cmd coin: Flips a coin and announces the result.";
	::add_help "$mafia_cmd record", "$mafia_cmd record [pattern]: Displays a random record achievement.";
	::add_help "$mafia_cmd top10", "$mafia_cmd top10 [setup/team]: Displays the top 10 highest-scoring players for a particular setup or team.";
	
	# Privileged commands
	::add_help "$mafia_cmd starttest", "$mafia_cmd starttest: Starts a game of 'test' using fake players. This is a privileged command.";
	::add_help "$mafia_cmd force", "$mafia_cmd force <player> <subcommand> [argument1] [argument2] ...: Uses the 'mafia' command on another player's behalf. This is a privileged command.";
	::add_help "$mafia_cmd resolvemode", "$mafia_cmd resolvemode <classic|paradox>: Sets the action resolution mode, which determines the order of night actions. Classic mode processes actions in a fixed order, while paradox mode sorts them in an intuitive fashion to prevent collisions. This is a privileged command.";
	::add_help "$mafia_cmd messagemode", "$mafia_cmd messagemode <color|nocolor>: Sets the message display mode to include or exclude color codes. This is a privileged command.";
	::add_help "$mafia_cmd reloadconfig", "$mafia_cmd reloadconfig: Reloads messages.ini from disk. This is a privileged command.";
	::add_help "$mafia_cmd settest", "$mafia_cmd settest [role1]/[team1] [role2]/[team2] [role3]/[team3] ...: Sets the roles of the 'test' special setup. This is a privileged command.";
	::add_help "$mafia_cmd exportroles", "$mafia_cmd exportroles: Writes roles-out.ini with a list of all roles in fadebot format. This is a privileged command.";
	
	# Moderator commands
	::add_help "$mafia_cmd forcein", "$mafia_cmd forcein [player1] [player2] ...: Forces fake players into a game during signups. Messages that would be sent to the fake players are sent to you instead. This is a moderator-only command.";
	::add_help "$mafia_cmd forceout", "$mafia_cmd forceout [player1] [player2] ...: Removes players from a game during signups. This is a moderator-only command.";
	::add_help "$mafia_cmd forcenextphase", "$mafia_cmd forcenextphase: Causes the game to move to the next phase immediately. Action resolution still happens. This is a moderator-only command.";
	::add_help "$mafia_cmd forcevote", "$mafia_cmd forcevote <player> [player1] [player2] ...: Votes on another player's behalf. This is a moderator-only command.";
        ::add_help "$mafia_cmd replace", "$mafia_cmd replace <old_player> <new_player>: Replaces old_player with new_player in the game. This is a moderator-only command.";
	::add_help "$mafia_cmd forceaction", "$mafia_cmd forceaction <player> <action> [target1] [target2] ...: Performs an action on another player's behalf. This is a moderator-only command.";
	::add_help "$mafia_cmd forcehelp", "$mafia_cmd forcehelp <player>: Sends a list of help topics to the player.  This is a moderator-only command.";
	::add_help "$mafia_cmd forcechoose", "$mafia_cmd forcechoose <player>: forces the player to choose a random selection in chosen setups. This is a moderator-only command.";
	::add_help "$mafia_cmd debugcheckstatus", "$mafia_cmd debugcheckstatus <player>: Displays the current status effects on a player. This is a moderator-only command.";
	::add_help "$mafia_cmd showsetup", "$mafia_cmd showsetup: Shows the role PMs  of all players in the current game. This is a moderator-only command.";
	::add_help "$mafia_cmd showsummary", "$mafia_cmd showsummary: Shows the true roles & alignments  of all players in the current game. This is a moderator-only command.";
	::add_help "$mafia_cmd forcerole", "$mafia_cmd forcerole <player> <role>: Changes the rolename of a player. This is a moderator-only command.";
	::add_help "$mafia_cmd baserole", "$mafia_cmd baserole <player> <role> (<team>): Assigns a player all the attributes of the given role. You must assign each player a role using this command before beginning a upick game. All previous attributes are removed. This is a moderator-only command.";
	::add_help "$mafia_cmd addability", "$mafia_cmd addability <player> <ability> [= alias] [uses] [success\%] [parameter]: Grants a player uses of an action. This is a moderator-only command.";
	::add_help "$mafia_cmd removeability", "$mafia_cmd removeability <player> <ability>: Denies a player uses of an action. This is a moderator-only command.";
	::add_help "$mafia_cmd addstatus", "$mafia_cmd addstatus <player> <status> [value]: Sets a special status on a player. This is a moderator-only command.";
	::add_help "$mafia_cmd removestatus", "$mafia_cmd removestatus <player> <status>: Resets a special status on a player. This is a moderator-only command.";
	::add_help "$mafia_cmd setbuddy", "$mafia_cmd setbuddy <player> <buddy>: Sets a player's \"buddy\", the special player for roles such as Lyncher and Twin. This is a moderator-only command.";
	::add_help "$mafia_cmd setdesc", "$mafia_cmd setdesc <player> <description>: Sets a player's role description. This is a moderator-only command.";
	::add_help "$mafia_cmd begin", "$mafia_cmd begin [phase]: Begins the game in the chosen phase. This is a moderator-only command.";
	::add_help "$mafia_cmd modkill", "$mafia_cmd modkill [player]: Immediately removes a player from the current game. This is a moderator-only command.";
	::add_help "$mafia_cmd changesetup", "$mafia_cmd changesetup [setup]: Changes the setup of a game during the signup phase. This is a moderator-only command.";
	::add_help "$mafia_cmd rolescript", "$mafia_cmd rolescript [rolename/rolecode]: Displays the series of moderator commands that would be necessary to turn a townie into a given role. This is a moderator-only command.";
	::add_help "$mafia_cmd usepresetup", "$mafia_cmd usepresetup <role1> <role2> ...: Takes a concise role listing (as given by the showpresetup command) and assigns the roles randomly to the current players. This is a moderator-only command.";
	::add_help "$mafia_cmd showpresetup", "$mafia_cmd showpresetup: Displays a consise listing of all the roles in the current setup, which can be used with the usepresetup or settest commands. This is a moderator-only command.";
	
	::add_command_public "vote", \&vote, <<HELP;
vote [player1] [player2] ...: Votes to lynch a player during a game of mafia. You don't need to unvote
before revoting. Lynch happens immediately as soon as any player reaches the required votes to lynch.
You can also vote to end the day without lynching with "!vote nolynch". No lynch happens when enough
players are voting no lynch so that the remaining players don't have the votes to carry out a lynch.
If you have multiple votes, list all of them in the same line. You can vote for the same player multiple
times or for several different players. You can see the current votes at any time by typing
"!$mafia_cmd votes. This command will also show the number of votes required, and will display 'damage' in gunfight-setups.".
HELP
	::add_command_public "unvote", \&unvote, "unvote: Removes your current vote. You don't need to unvote before voting somebody else.";
	::add_command_public "take", \&command_take, "take [item]: Takes an item. (gunfight/theme-setups only)";
	::add_command_public "drop", \&command_drop, "drop [item]: Drops an item. (gunfight/theme-setups only)";
	::add_command_public "buy", \&command_buy, "buy [item]: Buys an item. (gunfight/theme-setups only)";
	::add_command_any "help", \&help;
	::add_command_private "setrole", \&setrole;
		::add_command_private "baserole", \&mafia_subcommand;
	::add_command_private "addability", \&mafia_subcommand;
	::add_command_private "removeability", \&mafia_subcommand;
	::add_command_private "addstatus", \&mafia_subcommand;
	::add_command_private "removestatus", \&mafia_subcommand;
	::add_command_private "setbuddy", \&mafia_subcommand;
	::add_command_private "setdesc", \&mafia_subcommand;
	::add_command_private "begin", \&mafia_subcommand;

	::add_command_private "choose", \&choose_role;

	::add_help "basics", <<BASICS;
Type "!help rules" to see the channel rules. 
-
To start a game, type "!$mafia_cmd start [setup]" in the channel. To get a list of setups, use
"!$mafia_cmd special". Beginners should stick to straight, mild, balanced, unranked, or average. 
-
Once a game has been started, join it by typing "!$mafia_cmd in". You have to do this even if you're the
person who started the game. Signups end automatically after 3 minutes. If all interested players
have signed up before the timer expires, you can start the game early with "!$mafia_cmd go".
-
Your role will be sent to you by XylBot in the form of 'Role (alignment). Roletext. Abilities' 
To submit a night or day action to the bot, type "/msg $::nick [action] [target]". For example, to
inspect Dave, type "/msg $::nick inspect Dave". For more details, type "/msg $::nick help actions".
-
To vote, type "!vote [player]". To clear your vote, type "!unvote". You don't need to unvote before
revoting. For more details, type "/msg $::nick help vote". To see more about gameplay, type "/msg $::nick help gameplay."
BASICS
	::add_help "actions", <<ACTIONS;
To submit a night or day action to the bot, type "/msg $::nick [action] [target]". For example, to
inspect Dave, type "/msg $::nick inspect Dave". The bot will confirm your action with a message. If you
don't recieve any response, check to see if you mistyped "$::nick" or the action. You can get help about
a specific action using "/msg $::nick help [action]".
-
The actions you can use are listed in your role PM, after "Abilities:" or "Group Abilities:". If you
have more than one action listed, you can only use one each night. When you have a night action you
don't want to use, you must type "/msg $::nick none" so that the bot knows not to wait for you. If you're
mafia, only one member of the mafia can use the mafiakill action, so discuss who will make the kill
with your teammates. The person who uses mafiakill can not use one of their role actions as well.
-
Actions that start with "(day)" are day actions which can be used in the day (or voting) phase and usually 
take immediate effect; leave off the "(day)" when you submit them. Actions
that start with "(x)" can be used during either day or night. A few roles have actions marked "(auto)",
which means you will use them automatically every night. They don't count as your action for the night and
you cannot choose not to use them.
ACTIONS
	::add_help "gameplay", <<GAMEPLAY;
Games in mafia inolves two phases: day and night. During the night, actions are used. During the day, 
players vote to lynch (kill) a player. The aim as 'mafia' or 'sk' is to survive until there are the same 
number of townies left as there are members of the mafia (commonly called 'scum'). As the town, the aim is 
to eliminate all the members of the mafia. The town is an uninformed majority and do not know the alignments of 
each other, while the mafia knows who is a member of the mafia. 
-
During the day, the town will attempt to identify who the scum is, while the mafia will try to mislead members of
the town into lynching each other. 
-
A common tool used is a 'massclaim' or 'MC'. A player will count down, and upon reaching 0 all living players
will say their role, actions they used on each night, and anything that happened to them. An example claim layout 
is 'Cop, inspected Dave N0, got town.' It is critical that players do NOT copypaste any botmessages relating
to their claim, and town players should aim not to lie here.
-
As scum, it is advisable not to claim your real role. This can be achieved by using a 'fakeclaim'. Common fakeclaims
include townie and doctor and serve the purpose of making the player look like town - and thus are more likely 
to win. Certain roles have minimum player limits (doctor can only appear with 4 or more players), so be careful
not to claim a role that cannot occur. To find a role that you can fakeclaim, see "/msg $::nick help testsetup'.
GAMEPLAY
	::add_help "rules", <<RULES;
Failing to follow these rules may result in being removed from games and/or banned.
Operators may also use their discretion in managing the channel for areas not covered by these rules.
If you have any questions, concerns or suggestions, PM an Operator (@).  

1. You may only communicate privately with a player if it is nighttime and they are part of the same scum/mason group as you.
2. Private messages from the bot, including but not limited to your role PM, actions sent and results received, should not be pasted. Paraphrasing may be used instead.
3. You may not impersonate a user unless you are replacing them into the current game.
4. You must attempt to fulfill your win condition in all games. You may not intentionally delay a certain win. 
5. You may not bring outside information or vendettas into the current game.
6. Do not join games you cannot complete. If you need to leave, say so and '/nick YourNewNick' before you go.
7. Abuse of bot and server mechanics is against the spirit of the game and as such should not be used. Users should also seek not to use non-standard characters during a game.
8. Do not spam the channel or use excessive caps. Multiple bot commands should be done in PM. 
9. Discrimination (including but not limited to race, sexuality, gender, religion) and excessive abuse is forbidden.  
RULES
	
	foreach my $action (keys %action_config)
	{
		my $alias = $action_config{$action}{alias} || "";
		$alias =~ s/\s*#\d+//g;
		my $aliashelp = (exists $action_config{$alias} && $action_config{$alias}{help});
		$aliashelp =~ s/\b$alias\b/$action/g if $aliashelp;
		my $help = $action_config{$action}{help} || $aliashelp || "$action [target1] [target2] ...: Perform the command '$action' during a game of mafia.";
		::add_command_private $action, \&action, $help unless $action_config{$action}{public};
		::add_command_public $action, \&action, $help if $action_config{$action}{public};
	}
	::add_command_private "*default*", \&bad_action;

	foreach my $role (sort keys %role_config)
	{
		next unless $role_config{$role}{setup} || $role_config{$role}{showhelp};
		next if role_is_secret($role);

		add_help_for_role($role);
	}
	
	foreach my $setup (keys %setup_config)
	{
		my $minplayers = setup_minplayers($setup);
		my $maxplayers = setup_maxplayers($setup);
		my $players = " ($minplayers to $maxplayers players)";
		$players = " ($minplayers players)" if $minplayers == $maxplayers;
		my $help = $setup_config{$setup}{help} || "$setup$players: No help is available for this setup. Try '$mafia_cmd testsetup $setup' to see sample roles.";
		::add_help "setup " . lc($setup), $help;
	}
		
	::add_command_private "setmafiacommand", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;

		my $fromnick = (split /!/, $from)[0];
		if (lc $fromnick ne lc $::owner)
		{
			::notice("Sorry, you don't have permission to use this command.");
			return 1;
		}
		
		$mafia_cmd = $args;		
		::add_commands();
		::notice("Mafia command changed to '$mafia_cmd'.");
		return 1;
	}, "setmafiacommand <command>: Changes the command used for mafia. This is a privileged command.";
}

sub role_help_text {
	my ($role, $style) = @_;

	my $name = role_name($role, 1);
	$name = role_name($role, 0) if $name =~ /Unknown Role|#NAME/;
	$name =~ s/Unknown Role|#NAME/Role/g;

	$style = "normal" if !defined($style);

	if ($style eq "forum") {
		my $shortname = role_name($role, 0);
		$shortname =~ s/ Role$//;
		my $qm_shortname = quotemeta $shortname;
		if ($name ne $shortname) {
			$name = "[i]" . $name . "[/i]";
			$name =~ s/$qm_shortname/[\/i]$shortname\[i]/;
		}
		$name = "[b]" . $name . "[/b]";
	}

	my $theme = $role_config{$role}{theme} || 'normal';
	my $expandedrole = expand_setuprole($role);

	my $help = role_text($role, 1);

	if ($style eq "forum") {
		my $shorthelp = role_text($role, 0);
		my $qm_shorthelp = quotemeta $shorthelp;
		if ($help ne $shorthelp) {
			$help = "[i]" . $help . "[/i]";
			$help =~ s/$qm_shorthelp/[\/i]$shorthelp\[i]/;
		}
	}

	my @teams = map { my $a; ($a = $_) =~ s!/.*$!!; $a } split /,/, ($role_config{$role}{setup} || "unknown");
	my @actions = @{ $expandedrole->{actions} };
	@actions = map {
		my $a = $_;
		my $b = $a;
		$a =~ s/^auto(day|x|)/(auto)/;
		$a =~ s/^(day|x)/($1)/;
		$a =~ s/;1$/ (1 use)/;
		$a =~ s/;(\d+)$/ ($1 uses)/;
		$b =~ s/;\d+$//;
		$a =~ s/\(day\)/!/ if $action_config{action_base($b)}{public};
		$a .= " (" . (100 - $role_config{$role}{status}{"failure$b"}) . "% success)" if $role_config{$role}{status}{"failure$b"} &&
			$role_config{$role}{status}{"failure$b"} =~ /^\d+$/;
		$a
	} @actions;

	$help = "No description." if !$help;
		
	my $rarity = $role_config{$role}{template_rarity} || $role_config{$role}{rarity} || 1;
	my $extra = $rarity <= 2 ? "very common" : $rarity <= 20 ? "common" : $rarity <= 50 ? "uncommon" : $rarity <= 100 ? "rare" : "super-rare";

	$extra = join(', ', @teams) . "; $extra";

	$extra .= "; $role_config{$role}{minplayers}+ players" if $role_config{$role}{minplayers};

	unless ($role_config{$role}{setup})
	{
		$extra = "unknown";
	}
	if (role_is_secret($role))
	{
		$extra = "unknown";
	}

	$extra .= sprintf("; %i credits", item_cost($role)) if $role_config{$role}{item};
	$extra = "$theme; $extra" unless $theme =~ /\bnormal\b/;
	$extra =~ s/; unknown\b//;

	my $helpdesc = "$name ($extra):" . ($help ? " $help" : "") . 
		(@actions ? " Actions: @actions" : "");

	return $helpdesc;
}

sub add_help_for_role {
	my ($role) = shift;
	
	my $theme = $role_config{$role}{theme} || 'normal';
	my $themex = "";
	$themex = " ($role_config{$role}{theme})" if $theme !~ /\bnormal\b/;
		
	my $name = role_name($role, 1);
	$name = role_name($role, 0) if $name =~ /Unknown Role|#NAME/;
	$name =~ s/Unknown Role|#NAME/Role/g;
	my $shortname = $name;
	$shortname =~ s/\bvigilante\b/vig/i;
	$shortname =~ s/\bdoctor\b/doc/i;
	$shortname =~ s/\broleblocker\b/rb/i;
	# my $fancyname = role_fancy_name($role);

	my $helpdesc = role_help_text($role);
	
	::add_help "role " . lc($name) . $themex, $helpdesc;
	# ::add_help "role " . lc($fancyname) . $themex, $helpdesc;
	::add_help "role " . lc($shortname) . $themex, $helpdesc;
	::add_help "role " . lc($role) . $themex, $helpdesc;

	return $helpdesc;
}
