package mafia;

use strict;
use warnings;
no warnings 'redefine', 'qw';
use sort 'stable';
use Carp qw(cluck);

use String::Similarity;
use IO::Handle;
use Fcntl ':flock';

sub next_phase;

our $game_active;
our %config;

our ($phase, $day);
our ($lynch_votes);
our (@players, %players, %player_masks, %players_by_mask, @alive, @moderators, %moderators);
our (%automoderators);
our (%voiced_players);
our (%player_data, %group_data);
our ($last_votecount_time);
our (@action_queue, @resolved_actions, @deepsouth_actions);
our (@message_queue);
our (@last_winners);
our ($brag_count);
our (@items_on_ground);

our ($gameid, $gamelogfile);

our $resolvemode;
$resolvemode = 'paradox' unless defined($resolvemode);
our $messagemode;
$messagemode = 'color' unless defined($messagemode);
our $mafia_cmd;
$mafia_cmd = 'xmafia' unless defined($mafia_cmd);

our $cur_setup;
our $nonrandom_assignment;

our $mafiachannel;
our $phases_without_kill;
our $nokill_phase;
our $need_roles;

our %stop_voters;
our %reset_voters;

our $just_testing;
our @test_scheduled_events;
our @test_winners;
our $test_schedule_croak;
our $test_noflush;

# These files are automatically loaded by the bot skeleton.
our @files = qw(roles actions.pm resolver.pm commands.pm setup.pm test.pm);

our (@funny_roles);

our %role_config = ();
our %setup_config;
our %action_config;

our %group_config = (
	town => {
		wintext => "You win when all the bad guys are gone.",
		actions => [],
	},
	"town-ally" => {
		wintext => "You win if the town wins.",
		actions => [],
		nonteam => 1,
	},
	mafia => {
		wintext => "You win when you have majority and there are no other killers.",
		actions => ["mafiakill"],
		openteam => 1,
		weapon => 'gun',
	},
	wolf => {
		wintext => "You win when you have majority and there are no other killers.",
		actions => [],
		openteam => 1,
	},
	"mafia-ally" => {
		wintext => "You win if the Mafia wins.",
		actions => [],
		nonteam => 1,
	},
	survivor => {
		wintext => "You win if you are alive at the end of the game.",
		actions => [],
		nonteam => 1,
	},
	sk => {
		wintext => "You win when you are in the final two and there are no other killers.",
		actions => [],
	},
	cult => {
		wintext => "You win when you have majority and there are no other killers.",
		actions => [],
		openteam => 1,
	},
	mason => {
		actions => [],
		openteam => 1,
	},
	sibling => {
		actions => [],
		openteam => 1,
		sibling => 1,
	},
	lyncher => {
		wintext => "",
		actions => [],
	},
	jester => {
		wintext => "",
		actions => [],
		nonteam => 1,
	},
	assassin => {
		wintext => "",
		actions => [],
		openteam => 1,
	},
	assassin => {
		wintext => "",
		actions => [],
		openteam => 1,
	},
	
	# Factions for faction mafia
	townspeople => {
		wintext => "You win when both Fanatics are dead.",
		actions => [],
	},
	fanatics => {
		wintext => "You win when both Townspeople are dead.",
		actions => [],
	},
	merchant => {
		wintext => "You win when one Townsperson and one Fanatic are dead.",
		actions => [],
	},
	grimreaper => {
		wintext => "You win when one Townsperson, one Fanatic, and the Merchant are dead.",
		actions => [],
	},
);

our %messages;

$config{"start_time"} = 180;
$config{"votecount_time"} = 180;
$config{"night_time"} = 180;
$config{"night_reminder_time"} = 45;
$config{"minimum_players"} = 3;
$config{"maximum_players"} = 40;
$config{"chosen_time"} = 180;


our $signuptimer;
our $signupwarningtimer;
our $nighttimer;
our $nightremindtimer;
our $nightmintimer;
our $votetimer;
our $starttimer;
our $logclosetimer;
our $bragtimer;
our $pulsetimer;
our $chosentimer;

# This is used to prevent night from ending immediately when no or only a few players have night actions
our $night_ok;

our $resolving;
our $lynching;

# Timed actions
our @timed_action_timers;
our @recharge_timers;
our @misc_timers;

our %all_timers;

# Output lines
our $line_counter;

sub and_words {
	my (@words) = @_;

	return "" unless @words;
	return $words[0] if @words == 1;
	return $words[0] . " and " . $words[1] if @words == 2;
	return join(', ', @words[0..$#words-1]) . ", and " . $words[$#words];
}

sub schedule {
	my ($timerref, $time, $sub) = @_;
	
	unschedule($timerref) if $timerref;

	if ($test_schedule_croak)
	{
		cluck("Recursive schedule() in test?");
		return;
	}
	
	my $xsub = sub {
		delete $all_timers{$timerref};
		$$timerref = undef;
		eval { &$sub };
		::bot_log "ERROR timer: $@" if $@;
	};

	if ($just_testing)
	{
		push @test_scheduled_events, $xsub;
		$$timerref = undef;
		return;
	}
	
	$$timerref = $::cur_connection->schedule($time, $xsub);
	
	$all_timers{$timerref} = $timerref;
}

sub unschedule {
	my ($timerref) = @_;
	
	if ($$timerref)
	{
		delete $all_timers{$timerref};
		$::cur_connection->parent->dequeue_scheduled_event($$timerref);
		$$timerref = undef;
	}
}

sub unschedule_all {
	foreach my $key (keys %all_timers)
	{
		unschedule($all_timers{$key});
	}
}

sub announce {
	my ($channel, $msg);
	my $c = "\003";

	return if $just_testing;
	
	$line_counter++;
	
	if (@_ > 1)
	{
		($channel, $msg) = @_;
	}
	else
	{
		($channel, $msg) = ($mafiachannel, @_);
	}
	
	if ($messagemode eq 'color')
	{
		$msg =~ s/(?<!\w)\|\|(?!\w)/${c}15,14|${c}01,14|${c}00,01/g;
		::say($channel, "${c}14,15|${c}15,14|${c}01,14|${c}00,01 MAFIABOT ${c}15,14|${c}01,14|${c}00,01 $msg ${c}15,14|${c}01,14|${c}0,15|");
	}
	else
	{
		::say($channel, "||| MAFIABOT || $msg |||");
	}
}

sub notice {
	my ($player, $message) = @_;
	
	return if $just_testing;

	$line_counter++;
	
	if (!$players{$player} || $players{$player} eq $player)
	{
		::notice($player, $message);
	}
	else
	{
		::notice($players{$player}, "($player) $message");
	}
}

sub mod_notice {
	my ($message) = @_;
	
	foreach my $moderator (@moderators)
	{
		notice($moderator, $message);
	}
}

sub gamelog {
	my ($type, $message) = @_;

	cluck "Log of empty message" if !$message;

	return if $just_testing;
	
	# Make sure the game logfile is open
	if (!$gamelogfile || !defined(fileno($gamelogfile)))
	{
		open $gamelogfile, '>>', "mafia/game.log";
		autoflush $gamelogfile 1;
		::bot_log "LOG opened\n";
	}

	::bot_log "LOG $type $gameid $message\n";
	
	print $gamelogfile "$type $gameid $message\n";
	
	# Close the log after 30 seconds
	schedule(\$logclosetimer, 30, sub { close($gamelogfile); undef $gamelogfile; ::bot_log "LOG closed\n"; });
}

sub update_voiced_players {
	my %new_voiced_players;

	return if $just_testing;
	return unless $::cur_connection;

	my $allow_talk = 0;
	$allow_talk = 1 if $phase ne 'night' && $phase ne 'nightsetupwait' && get_total_votes() > 0;
	$allow_talk = 1 if setup_rule('noday');
	$allow_talk = 1 if setup_rule('nonight');
	$allow_talk = 0 if (setup_rule('rolechoices') && $phase eq 'setup');
	
	foreach my $player (@alive)
	{
		$new_voiced_players{$player}++ if $allow_talk;
	}
	foreach my $player (@moderators)
	{	
		$new_voiced_players{$player}++;
	}

	if ($phase eq 'signup')
	{
		foreach my $player (keys %players)
		{
			$new_voiced_players{$player}++;
		}
	}

	my @tovoice = sort keys %new_voiced_players;
	my @todevoice = grep { !$new_voiced_players{$_} } sort keys %voiced_players;

	while (@tovoice)
	{
		my @players = splice(@tovoice, 0, scalar(@tovoice > 5 ? 5 : @tovoice));
		$::cur_connection->mode($mafiachannel, '+' . ('v' x scalar(@players)), @players);
	}
	while (@todevoice)
	{
		my @players = splice(@todevoice, 0, scalar(@todevoice > 5 ? 5 : @todevoice));
		$::cur_connection->mode($mafiachannel, '-' . ('v' x scalar(@players)), @players);
	}

	%voiced_players = %new_voiced_players;

	if ($phase eq 'night' || $phase eq 'day' || $phase eq 'dusk' || $phase =~ /setupwait/ || ($phase eq 'setup' && setup_rule('rolechoices', $cur_setup) ) )
	{
		$::cur_connection->mode($mafiachannel, "+m");
	}
	else
	{
		$::cur_connection->mode($mafiachannel, "-m");
	}
}

sub shuffle_list {
	my ($list) = @_;

	my ($i, $j);
	for ($i = $#{$list}; $i > 0; $i--)
	{
		$j = int(rand($i + 1));
		($list->[$i], $list->[$j]) = ($list->[$j], $list->[$i]);
	}
}
sub get_player {
	my $arg = shift;
	
	foreach my $player (@players)
	{
		if (lc $arg eq lc $player)
		{
			return $player;
		}
	}
	
	# This section requires String::Similarity.
	my $bestplayer = "";
	my $bestvalue = 0;
	my $minimum = 0.75;
	foreach my $player (@players)
	{
		my $value = similarity(lc $arg, lc $player, $minimum);
		if ($value > $bestvalue)
		{
			$bestplayer = $player;
			$bestvalue = $value;
		}
	}
	if ($bestvalue >= $minimum)
	{
		::bot_log "FUZZY $arg -> $bestplayer\n";
		return $bestplayer;
	}
	
	return wantarray ? () : "";
}

sub get_status {
	my ($player, $status) = @_;
	
	cluck("Can't get status '$status' for player '$player'") unless $player_data{$player};
	
	foreach my $s ($player_data{$player}{temp}{status}{$status}, $player_data{$player}{safe}{status}{$status}, "") {
		if (defined($s) && $s ne "") {
			return $s;
		}
	}

	# Check for disable
	if (($player_data{$player}{safe}{status}{disabled} || $player_data{$player}{temp}{status}{disabled}) 
		&& $status !~ /^rolename$|^roletruename$|^hp$|^damage$|^timedset/)
	{
		return "";
	}

	foreach my $s ($player_data{$player}{status}{$status}, "") {
		if (defined($s) && $s ne "") {
			return $s;
		}
	}
}

# Decrease a status by an amount (default 1). Temporary status is decreased first.
# If the amount is greater than the temporary status, it rolls over.
sub reduce_status {
	my ($player, $status, $amount) = @_;
	
	$amount = 1 unless $amount;
	
	if ($amount eq '*')
	{
		$player_data{$player}{temp}{status}{$status} = "";
		$player_data{$player}{safe}{status}{$status} = "";
		$player_data{$player}{status}{$status} = "";

		handle_trigger($player, get_status($player, "onloststatus:$status")) unless get_status($player, $status);
		return;
	}
	
	if ($amount !~ /^\d+$/)
	{
		$player_data{$player}{temp}{status}{$status} = "" if ($player_data{$player}{temp}{status}{$status} || "") eq $amount;
		$player_data{$player}{safe}{status}{$status} = "" if ($player_data{$player}{safe}{status}{$status} || "") eq $amount;
		$player_data{$player}{status}{$status} = "" if ($player_data{$player}{status}{$status} || "") eq $amount;

		handle_trigger($player, get_status($player, "onloststatus:$status")) unless get_status($player, $status);
		return;
	}
	
	if (($player_data{$player}{temp}{status}{$status} || "") =~ /^\d+$/)
	{
		if ($player_data{$player}{temp}{status}{$status} >= $amount)
		{
			$player_data{$player}{temp}{status}{$status} -= $amount;

			handle_trigger($player, get_status($player, "onloststatus:$status")) unless get_status($player, $status);
			return;
		}
		else
		{
			$amount -= $player_data{$player}{temp}{status}{$status};
			$player_data{$player}{temp}{status}{$status} = 0;
		}
	}
	if (($player_data{$player}{safe}{status}{$status} || "") =~ /^\d+$/)
	{
		if ($player_data{$player}{safe}{status}{$status} >= $amount)
		{
			$player_data{$player}{safe}{status}{$status} -= $amount;

			handle_trigger($player, get_status($player, "onloststatus:$status")) unless get_status($player, $status);
			return;
		}
		else
		{
			$amount -= $player_data{$player}{safe}{status}{$status};
			$player_data{$player}{safe}{status}{$status} = 0;
		}
	}
	if (($player_data{$player}{status}{$status} || "") =~ /^\d+$/)
	{
		if ($player_data{$player}{status}{$status} >= $amount)
		{
			$player_data{$player}{status}{$status} -= $amount;

			handle_trigger($player, get_status($player, "onloststatus:$status")) unless get_status($player, $status);
			return;
		}
		else
		{
			$amount -= $player_data{$player}{status}{$status};
			$player_data{$player}{status}{$status} = 0;
		}
	}
}

sub increase_status {
	my ($data, $status, $amount) = @_;

	$data = $player_data{$data} unless ref($data) eq 'HASH';
	
	$amount = 1 unless defined($amount);
	
	# ::bot_log "STATUS+ $player $status $amount\n";
	
	($data->{status}{$status} = $amount), return if $amount !~ /^\d+$/;
	
	return if ($data->{status}{$status} || 0) !~ /^\d+$/;
	$data->{status}{$status} += $amount;
}

sub increase_temp_status {
	my ($data, $status, $amount) = @_;
	
	$data = $player_data{$data} unless ref($data) eq 'HASH';
	
	$amount = 1 unless defined($amount);

	# ::bot_log "TEMPSTATUS+ $player $status $amount\n";
	
	($data->{temp}{status}{$status} = $amount), return if $amount !~ /^\d+$/;
	
	return if ($data->{temp}{status}{$status} || 0) !~ /^\d+$/;
	$data->{temp}{status}{$status} += $amount;
}

sub increase_safe_status {
	my ($data, $status, $amount) = @_;
	
	$data = $player_data{$data} unless ref($data) eq 'HASH';
	
	$amount = 1 unless defined($amount);

	# ::bot_log "SAFESTATUS+ $player $status $amount\n";
	
	($data->{safe}{status}{$status} = $amount), return if $amount !~ /^\d+$/;
	
	return if ($data->{safe}{status}{$status} || 0) !~ /^\d+$/;
	$data->{safe}{status}{$status} += $amount;
}

sub set_status {
	my ($data, $status, $amount) = @_;
	
	if (ref($data) ne 'HASH')
	{
		cluck("Can't set status '$status' for player '$data'") unless $player_data{$data};
		$data = $player_data{$data};
	}
	
	$data->{status}{$status} = $amount;
}

sub set_temp_status {
	my ($data, $status, $amount) = @_;
	
	if (ref($data) ne 'HASH')
	{
		cluck("Can't set status '$status' for player '$data'") unless $player_data{$data};
		$data = $player_data{$data};
	}
	
	$data->{temp}{status}{$status} = $amount;
}

sub set_safe_status {
	my ($data, $status, $amount) = @_;
	
	if (ref($data) ne 'HASH')
	{
		cluck("Can't set status '$status' for player '$data'") unless $player_data{$data};
		$data = $player_data{$data};
	}
	
	$data->{safe}{status}{$status} = $amount;
}

sub get_group_members {
	my $group = shift;
	return @{$group_data{$group}{members} || []};
}

sub get_action_group {
	my ($player, $action) = @_;
	
	return get_status($player, "group$action");
}

sub group_config {
	my ($group) = @_;
	
	$group =~ s/\d+$//;
	
	return $group_config{$group} || { actions => [] };
}

sub get_group_actions {
	my ($group) = @_;

	my $specialactions = setup_rule("${group}actions");
	if ($specialactions) {
		return split /,/, $specialactions;
	}
	
	return @{group_config($group)->{actions}};
}

sub get_player_role {
	my $player = shift;
	
	return $player_data{$player}{role};
}

sub get_player_role_name {
	my $player = shift;
	
	return get_status($player, 'rolename');
}

sub get_player_role_truename {
	my $player = shift;

	return $player_data{$player}{safe}{status}{rolename} || get_status($player, 'roletruename');
}

sub get_player_role_plural {
	my $player = shift;
	my $rolename = get_player_role_name($player);
	my $role = get_player_role($player);
	
	return $role_config{$role}{pluralname} || "${rolename}s" || $role;
}

sub get_player_team {
	my $player = shift;
	
	return $player_data{$player}{team};
}

sub get_player_team_short {
	my $player = shift;
	my $team = $player_data{$player}{team};
	$team =~ s/\d+$//;
	return $team;
}

sub get_player_groups {
	my $player = shift;
	
	cluck("Player '$player' has no groups"), return () unless $player_data{$player}{groups};
	
	return @{$player_data{$player}{groups}};
}

sub get_player_actions {
	my $player = shift;

	cluck("Player '$player' has no actions"), return () unless $player_data{$player}{actions};
	
	return @{$player_data{$player}{actions}};
}

sub get_player_group_actions {
	my $player = shift;
	
	cluck("Player '$player' has no group actions"), return () unless $player_data{$player}{group_actions};

	return @{$player_data{$player}{group_actions}};
}

sub get_player_all_actions {
	my $player = shift;
	
	return (get_player_actions($player), get_player_group_actions($player));
}

sub get_player_weapon {
	my $player = shift;
	
	my $weapon = get_status($player, 'weapon') || group_config(get_player_team_short($player))->{weapon} || "";
	return "" if $weapon eq 'none';
	return $weapon;
}

sub alive {
	my $player = shift;
	
	return $player_data{$player}{alive};
}

sub count_role_as {
	my $role = shift;
	return $role_config{$role}{countas} || $role;
}

sub action_base {
	my $action = shift;
	$action =~ s/^auto//;
	$action =~ s/^x|^day//;
	$action =~ s/;\d+$//;
	return $action;
}

sub setup_rule {
	my ($rule, $setup) = @_;

	$setup = $cur_setup || "normal" unless $setup;
	$setup = $setup->{setup} if ref($setup) eq 'HASH';

	return $setup_config{$setup}{$rule} || 0;
}

sub shirt_color {
	my ($setup, $i) = @_;

	$setup = $setup->{setup} if ref($setup) eq 'HASH';

	return $setup_config{$setup}{shirts}[$i];
}

sub estimate_template_power {
	my ($template, $numplayers) = shift;

	if (defined($role_config{$template}{template_estimated_power}))
	{
		return $role_config{$template}{template_estimated_power};
	}

	my $total = 0;
	my $count = 0;

	my @sources;

	foreach my $role (keys %role_config)
	{
		next unless $role_config{$role}{alias};
		next unless $role_config{$role}{setup};

		my $expandedrole = recursive_expand_role($role);

		if ($expandedrole =~ /\+$template\b/)
		{
			my $prerole = $expandedrole;
			$prerole =~ s/\+$template\b//;
			$prerole = canonicalize_role($prerole, 0);
			next unless $role_config{$prerole}{setup};

			my $prepower = role_power($prerole, $numplayers);
			my $power = role_power($role, $numplayers);

			my $weight = 1 + ($role_config{$role}{changecount} || 0);
			$weight = 1 + ($role_config{$prerole}{changecount} || 0) if 1 + ($role_config{$role}{changecount} || 0) < $weight && !$role_config{$role}{fixed_power_base};
			$weight = 50 if $weight > 50;

			$total += ($power - $prepower) * $weight;
			$count += $weight;
			push @sources, "$role $weight";
		}
	}

	my $power = $count ? $total / $count : 0;
	$role_config{$template}{template_estimated_power} = $power;

	# ::bot_log("INFO estimated power of template $template at $power (" . join(', ', @sources) . ")\n");
	return $power;
}

sub role_power {
	my ($role, $numplayers, $multirole, $expand) = @_;
	
	cluck "Called role_power on undef" unless defined($role);

	my @role = split /,/, $role;
	my $power = undef;

	$multirole = ($role =~ /\+/) unless defined($multirole);

	# The "power" of a role is defined to be the average power from 4 to 12 players.
	# The "power bias" is twice the difference between the power of the role at 4 players and the power of the role at 12 players.
	my $bias = 0;
	$bias = ($numplayers - 8) / 4 if $numplayers;
	$bias = 1 if $bias > 1;
	$bias = -1 if $bias < -1;

	$expand = 0 if ($role_config{$role}{changecount} || 0) >= 20;
	
	foreach my $choice (@role)
	{
		my $choicepower = 0;
		$choice = recursive_expand_role($choice) if $expand;
		foreach my $subrole (split /\+/, $choice)
		{
			my $subrolepower;
			if ($role_config{$subrole}{template})
			{
				$subrolepower = estimate_template_power($subrole, $numplayers);
			}
			else
			{
				$subrolepower = $role_config{$subrole}{power} || 0;
			}
			$subrolepower += $bias * ($role_config{$subrole}{powerbias} || 0);
			$choicepower += $subrolepower;

			my $multirolepower = $role_config{$subrole}{powermultirole};
			$multirolepower = 0 unless $multirolepower;
			$choicepower += $multirolepower if $multirole;
		}
		$power = $choicepower if !defined($power) || $choicepower > $power;
	}

	return $power;
}

sub recursive_expand_role {
	my ($role) = @_;

	my @baseparts = split /\+/, $role;
	my @roleparts;
	while (@baseparts)
	{
		my $basepart = shift @baseparts;
		if ($role_config{$basepart}{alias})
		{
			unshift @baseparts, '*' . $basepart;
			unshift @baseparts, split /\+/, $role_config{$basepart}{alias};
			unshift @baseparts, '*';
			next;
		}
		push @roleparts, $basepart if $basepart;
	}

	return wantarray ? @roleparts : join('+', grep { $_ !~ /^\*/ } @roleparts);
}

sub is_vanilla_role {
	my ($role) = @_;

	# return 1 if $role eq 't' || $role eq 'm' || $role eq 'sv' || $role eq 'sk' || $role eq 'cult1';
	# Serial Killer and Cult Leader aren't truly vanilla, because they have abilities.
	return 1 if $role eq 't' || $role eq 'm' || $role eq 'sv';
	return 0;
}

sub combine_roles {
	my ($validrole, $rolepart, $namedonly) = @_;

	my @suffixes = $rolepart;

	push @suffixes, $1 if $rolepart =~ /^(?:template|item)_(.*)$/;
	push @suffixes, $rolepart;

	foreach my $suffix (@suffixes)
	{
		next if $role_config{$validrole . $suffix}{nocombine};
		if (is_real_role($validrole . $suffix, $namedonly))
		{
			$validrole .= $suffix;
			return $validrole;
		}
		if ($role_config{$validrole . $suffix}{alias} && $role_config{$validrole . $suffix}{alias} ne "$validrole+$rolepart")
		{
			$validrole = $role_config{$validrole . $suffix}{alias};
			return $validrole;
		}
	}

	my @subroles = split /\+/, $validrole;
	if (@subroles >= 2)
	{
		# If a template only applies to ONE subrole, attach it there.
		# If a nontemplate attaches to ANY subrole, attach it there.
		foreach my $subrole (@subroles)
		{
			next if $role_config{$rolepart}{template} && grep { $_ ne $subrole && valid_template($rolepart, $_) } @subroles;
			my $subcombinedrole = combine_roles($subrole, $rolepart, 1);
			next unless $subcombinedrole;

			return join('+', map { $_ eq $subrole ? $subcombinedrole : $_ } @subroles );
		}

		# If a template attaches to one subrole, move that subrole last and attach it.
		foreach my $subrole (@subroles)
		{
			# next if grep { $_ ne $subrole && combine_roles($_, $rolepart, 1) } @subroles;
			my $subcombinedrole = combine_roles($subrole, $rolepart, 1);
			next unless $subcombinedrole;
			next if $subcombinedrole eq $subrole;

			return join('+', grep { $_ ne $subrole } (@subroles), $subcombinedrole);
		}
	}

	return undef;
}

sub get_total_votes {
	my $total_votes = 0;
	
	foreach my $player (@alive)
	{
		$total_votes += get_player_votes($player);
	}
	
	return $total_votes;
}

sub calculate_lynch_votes {
	my $maxvotes = get_total_votes();
	$maxvotes = scalar(@alive) if $maxvotes > scalar(@alive);
	$lynch_votes = int($maxvotes / 2) + 1;
}

sub calculate_alive {
	@alive = grep { alive($_) } @players;
}

sub collect_player_group_actions {
	my ($player) = @_;
	
	if (setup_rule('no_group_actions', $cur_setup))
	{
		$player_data{$player}{group_actions} = [];
		return;
	}

	my @group_actions = ();
	foreach my $group (get_player_groups($player))
	{
		foreach my $action (get_group_actions($group))
		{
			next if get_status($player, "group$action");
			push @group_actions, $action;
			set_status($player, "group$action", $group);
		}
	}
	if (get_status($player, 'groupactions'))
	{
		foreach my $action (split /,/, get_status($player, 'groupactions'))
		{
			my $shortaction = $action;
			$shortaction =~ s/;\d+//;
			next if get_status($player, "group$shortaction");
			push @group_actions, $action;
			set_status($player, "group$shortaction", get_player_team($player)) unless get_player_team($player) eq 'town';
		}
	}
	$player_data{$player}{group_actions} = [@group_actions];
}

sub initialize_player_action_uses {
	my ($setuprole, $actiontype) = @_;

	$setuprole = $player_data{$setuprole} unless ref($setuprole) eq 'HASH';

	foreach my $action (@{$setuprole->{$actiontype}})
	{
		if ($action =~ s/;(\d+)$//)
		{
			my $uses = $1;
			
			increase_status($setuprole, "act$action", $uses);
		}
		else
		{
			increase_status($setuprole, "act$action", '*');
		}
	}
}

sub role_name {
	my ($role, $use_truename) = @_;

	our (%name_cache, %truename_cache);

	$use_truename = 0 if !defined($use_truename);

	if (!exists $name_cache{$role}) {
		my $setuprole = expand_setuprole($role);
		$name_cache{$role} = $setuprole->{name};
		$truename_cache{$role} = $setuprole->{truename};
	}

	return $use_truename ? $truename_cache{$role} : $name_cache{$role};
}

sub role_text {
	my ($role, $include_help) = @_;
	$include_help = 0 unless defined($include_help);

	my $expanded_role = expand_setuprole($role);
	my $roletext = $expanded_role->{roletext};
	my $help = $expanded_role->{help};

	$roletext .= ' ' . $help if $help && $include_help;

	return $roletext;
}

sub expand_setuprole {
	my ($setuprole) = @_;

	our %setuprole_cache;
	my $docache = 0;

	$setuprole = { role => $setuprole }, $docache = 1 unless ref($setuprole) eq 'HASH';

	if ($setuprole->{role} =~ /\*/) {
		cluck("expand_setuprole called on $setuprole->{role}\n");
	}

	if ($docache && $setuprole_cache{$setuprole->{role}})
	{
		return $setuprole_cache{$setuprole->{role}};
	}

	my $superrole = $setuprole->{role};
	my $role = $superrole;
	# $role = $role_config{$role}{alias} if $role_config{$role}{alias};
	
	my @subroles = recursive_expand_role($role);
	
	my @actions = ();
	my %status = ();
	my @groups = ();
	my $name = "Unknown Role";
	my $truename = "Unknown Role";
	my $roletext = "";
	my $rolehelp = "";
	my $baserole = "";

	my @items;

	my @roletextstack;

	my @orig_subroles = @subroles;

	while (@subroles)
	{
		my $subrole = shift @subroles;
		my ($savedroletext, $savedrolehelp, $savedname, $savedtruename);

		if ($subrole eq '*')
		{
			push @roletextstack, [$roletext, $rolehelp, $name, $truename];
			next;
		}

		if ($subrole =~ /^\*/)
		{
			if (!@roletextstack) {
				cluck("No saved role text in expand_setuprole for $subrole (subrole of $role = @orig_subroles)\n");
				next;
			}
			($savedroletext, $savedrolehelp, $savedname, $savedtruename) = @{pop @roletextstack};
			$subrole =~ s/^\*//;
		}

		if ($role_config{$subrole}{item})
		{
			push @items, $role_config{$subrole}{item_name};
		}

		# #VALUE is replaced with the old action of a status.
		# #ACTION0, #ACTION1, etc are replaced with actions.
		my %newstatus;
		foreach my $key (keys %{ $role_config{$subrole}{status} || {} })
		{
			for my $i (($key =~ /#ACTION\*/ || $role_config{$subrole}{status}{$key} =~ /#ACTION\*/) ? 0..$#actions : 0) {
				my $value = $role_config{$subrole}{status}{$key};
				my $newkey = $key;
				my @baseactions = map { action_base($_) } @actions;
				$newkey =~ s/#ACTION\*/$baseactions[$i]/g;
				$newkey =~ s/#ACTION(\d+)/$baseactions[$1] || "none"/ge;
				$newkey =~ s/#BASE/$baserole/g;
				$newkey =~ s/#VALUE:(\S+)/$status{$1}/g;
				$newkey =~ s/#VALUE/$status{$key}/g;
				$value =~ s/#ACTION\*/$status{"replace$baseactions[$i]"} || $baseactions[$i]/ge;
				$value =~ s/#ACTION(\d+)/($baseactions[$1] && $status{"replace$baseactions[$1]"}) || $baseactions[$1] || "none"/ge;
				$value =~ s/#ACTIONNAME\*/$baseactions[$i]/g;
				$value =~ s/#ACTIONNAME(\d+)/$baseactions[$1] || "none"/ge;
				$value =~ s/#BASE/$baserole/g;
				$value =~ s/#VALUE:(\S+)/$status{$1} || ""/ge;
				$value =~ s/#VALUE/$status{$key}/g;
				$newstatus{$newkey} = $value;
			}
		}
		my @newactions;
		foreach my $action (@{ $role_config{$subrole}{actions} || [] })
		{
			for my $i ($action =~ /#ACTION\*/ ? 0..$#actions : 0) {
				my $newaction = $action;
				$newaction =~ s/#ACTION\*/$actions[$i] || "none"/ge;
				$newaction =~ s/#ACTION(\d+)/$actions[$1] || "none"/ge;
				$newaction =~ s/;\d+;/;/g;
				push @newactions, $newaction;
			}
		}
		my @newgroups = @{ $role_config{$subrole}{groups} || [] };
		
		@actions = $role_config{$subrole}{replaceactions} ? @newactions : (@actions, @newactions);
		%status = $role_config{$subrole}{replacestatus} ? %newstatus : (%status, %newstatus);
		@groups = $role_config{$subrole}{replacegroups} ? @groups : (@groups, @newgroups);
				
		my @baseactions = @actions;
		map { s/;.*// } @baseactions;
		
		my $oldroletext = $roletext;
		$oldroletext = $savedroletext if defined($savedroletext) && $role_config{$subrole}{roletext};
		$roletext = $role_config{$subrole}{roletext} || $roletext;
		$roletext =~ s/#TEXT/$oldroletext/g;
		$roletext =~ s/#NAME/$name/g;
		$roletext =~ s/#ACTION(\d+)/$baseactions[$1] || "none"/ge;
		$roletext =~ s/^\s+//;
		$roletext =~ s/\s+$//;

		my $oldrolehelp = $rolehelp;
		$oldrolehelp = $savedrolehelp if defined($savedrolehelp) && $role_config{$subrole}{help};
		$rolehelp .= ' ' . $role_config{$subrole}{help} if $role_config{$subrole}{help};
		$rolehelp =~ s/#TEXT/$oldroletext/g;
		$rolehelp =~ s/#NAME/$name/g;
		$rolehelp =~ s/#ACTION(\d+)/$baseactions[$1] || "none"/ge;
		$rolehelp =~ s/^\s+//;
		$rolehelp =~ s/\s+$//;

		my $oldname = $name;
		$oldname = $savedname if defined($savedname) && $role_config{$subrole}{name};
		my $oldtruename = $truename;
		$oldtruename = $savedtruename if defined($savedtruename) && ($role_config{$subrole}{truename} || $role_config{$subrole}{name});

		$name = $role_config{$subrole}{name} || $oldname;
		$truename = $role_config{$subrole}{truename} || $role_config{$subrole}{name} || $oldtruename;
		$name =~ s/#NAME/$oldname/g;
		$truename =~ s/#NAME/$oldtruename/g;

		if ($role_config{$subrole}{name} && !$role_config{$subrole}{template} && $oldname ne "Unknown Role")
		{
			$name = "$name $oldname";
			$truename = "$truename $oldtruename";
		}

		if (!$role_config{$subrole}{template} && $oldroletext ne "" && $oldroletext ne $roletext)
		{
			$roletext = "$oldroletext $roletext";
		}
		
		$baserole = ($baserole ? "$baserole+$subrole" : $subrole);
	}

	# An alias can override the role name and role text
	if ($superrole ne $role)
	{
		if ($role_config{$superrole}{roletext})
		{
			$roletext = $role_config{$superrole}{roletext};
		}
	}

	$name = $setuprole->{name} if $setuprole->{name};
	$truename = $setuprole->{name} if $setuprole->{name};

	if (@items) {
		if ($name eq 'Unknown Role') {
			$name = $truename = join(", ", @items);
		}
		else {
			$truename .= " (" . join(", ", @items) . ")";
			$name .= " (" . join(", ", @items) . ")";
		}
	}

	my $expandedrole = {%$setuprole};
	$expandedrole->{actions} = [@actions];
	$expandedrole->{status} = {%status};
	$expandedrole->{groups} = [@groups];
	$expandedrole->{name} = $name;
	$expandedrole->{truename} = $truename;
	$expandedrole->{roletext} = $roletext;
	$expandedrole->{help} = $rolehelp;
	
	# Get name/truename
	set_status($expandedrole, 'rolename', $expandedrole->{name});
	set_status($expandedrole, 'roletruename', $expandedrole->{truename});
	set_status($expandedrole, 'roletext', $expandedrole->{roletext});

	if ($docache)
	{
		$setuprole_cache{$setuprole->{role}} = $expandedrole;
	}

	return $expandedrole;
}
	
sub assign_one_role {
	my ($player, $setuprole) = @_;

	$setuprole = expand_setuprole($setuprole);

	::bot_log "ASSIGN $player ", $setuprole->{role}, " ", $setuprole->{team}, "\n";

	$player_data{$player} = {%$setuprole};
			
	push @{$player_data{$player}{groups}}, $player_data{$player}{team};
	
	# Get a buddy
	my @buddies = grep { $_ ne $player } (@alive ? @alive : @players);
	$player_data{$player}{buddy} = $buddies[rand @buddies];
	
	# Collect group actions
	collect_player_group_actions($player);

	# Get action uses
	initialize_player_action_uses($player_data{$player}, 'actions');
	initialize_player_action_uses($player_data{$player}, 'group_actions');
}

sub swap_roles {
	my ($player1, $player2) = @_;
	
	return if $player1 eq $player2;
	
	# Swap role names
	($player_data{$player1}{role}, $player_data{$player2}{role}) = ($player_data{$player2}{role}, $player_data{$player1}{role});
	
	# Swap actions
	($player_data{$player1}{actions}, $player_data{$player2}{actions}) = ($player_data{$player2}{actions}, $player_data{$player1}{actions});
	
	# Swap status
	($player_data{$player1}{status}, $player_data{$player2}{status}) = ($player_data{$player2}{status}, $player_data{$player1}{status});
	
	# Remove group action uses
	foreach my $action (get_player_group_actions($player1))
	{
		reduce_status($player1, "act$action", '*');
	}
	foreach my $action (get_player_group_actions($player2))
	{
		reduce_status($player2, "act$action", '*');
	}
	
	# Recalculate groups
	collect_player_group_actions($player1);
	collect_player_group_actions($player2);

	# Get player group action uses
	initialize_player_action_uses($player1, 'group_actions');
	initialize_player_action_uses($player2, 'group_actions');

	# Canonicalize
	adjust_player_role_after_change($player1);
	adjust_player_role_after_change($player2);
}

sub calculate_group_members
{
	foreach my $group (keys %group_data)
	{
		$group_data{$group}{alive} = 0;
		$group_data{$group}{members} = [];
	}
	
	foreach my $player (@players)
	{
	    ::bot_log("Calculating group for $player\n");
		foreach my $group (get_player_groups($player))
		{
			push @{$group_data{$group}{members}}, $player;
			$group_data{$group}{alive}++ if alive($player);
		}
	}
}

sub assign_roles {
	my @roles = @_;
	
	%player_data = ();
	%group_data = ();

	shuffle_list(\@roles) unless $nonrandom_assignment;

	foreach my $player (@players)
	{
		# Get a random role
		my $setuprole = pop @roles;

		if (setup_rule('maxchoices', $cur_setup) || $setuprole->{role} =~ /,/)
		{
			my @choices = map { role_name($_) } split /,/, $setuprole->{role};
			my $teamshort = $setuprole->{team};
			$teamshort =~ s/\d+$//;
			$player_data{$player}{waitingforchoice} = 1;
			$player_data{$player}{setuprole} = $setuprole;
			$player_data{$player}{role} = $setuprole->{role};
			$player_data{$player}{team} = $setuprole->{team};
			$player_data{$player}{groups} = [];
			$player_data{$player}{actions} = [];
			$player_data{$player}{status} = {};
			send_help($player);
		}
		else
		{
			# Assign the role
			assign_one_role($player, $setuprole);
			$player_data{$player}{alive} = 1;
			$player_data{$player}{startrole} = $player_data{$player}{role};
			$player_data{$player}{startteam} = $player_data{$player}{team};
		}
	}

	calculate_group_members();
	calculate_alive();
}

sub describe_ability {
	my ($player, $ability) = @_;
	my $shortability = action_base($ability);
	my $uses = get_status($player, "act$ability");
	my $recharge = get_status($player, "recharge$shortability");
	
	if ($uses ne '*')
	{
		$ability .= ($uses eq 1 ? " ($uses use" : (!$uses ? " (unusable" : " ($uses uses"));
		if ($recharge) {
			$ability .= "; recharge ${recharge}s";
		}
		$ability .= ")";
	}
	elsif ($recharge)
	{
		$ability .= " (recharge ${recharge}s)";
	}
	
	$ability =~ s/^auto(day|x|)/(auto)/;
	$ability =~ s/^day/!/ if $action_config{$shortability}{public};
	$ability =~ s/^(day|x)/($1)/;
	

	return $ability;
}

sub message_or_notice {
	my ($player, $text, $bymsg) = @_;
	
	if (!$bymsg)
	{
		notice($player, $text);
	}
	else
	{
		enqueue_message($player, $text);
	}
}

sub get_roletext {
	my ($player, $role, $team, $nonames) = @_;
	my $roletext = $player_data{$player}{safe}{roledesc} || get_status($player, 'roletext') || "";
	my $wintext = group_config($team)->{wintext};

	if ($roletext =~ /TOWNIE1/)
	{
		my $target;
		foreach my $player (@players)
		{
			$target = $player if get_status($player, 'lyncher') eq $team;
		}
		$target = "????" if $nonames;
		$roletext =~ s/TOWNIE1/$target/;
	}

	$roletext =~ s/SHIRT(\d+)/ shirt_color($cur_setup, $1 - 1) /ge;

	my $buddy = $player_data{$player}{buddy};
	$buddy = "????" if $nonames;
	$roletext =~ s/BUDDY1/$buddy/g;
	
	my $text = "Role: $role ($team). $roletext $wintext";
	
	foreach my $group (get_player_groups($player))
	{
		my $groupshort = $group;
		$groupshort =~ s/\d+$//;
		if (group_config($group)->{openteam} && $group_data{$group}{alive} > 1)
		{
			my $groupdesc = $messages{help}{$groupshort} || "Your team is: #TEXT1";
			my $members = join(' ', get_group_members($group));
			$members = join(' ', ("????") x scalar(get_group_members($group))) if $nonames;
			$groupdesc =~ s/\#TEXT1/$members/;
			$text .= ' ' . $groupdesc;
		}
	}
	
	$text =~ s/\s+$//;
	$text =~ s/\s+/ /g;

	return $text;
}

sub send_help {
	my ($player, $bymsg, $towho, $nonames) = @_;
	my $team = get_player_team_short($player);

	if ($moderators{$player})
	{
		message_or_notice($towho || $player, "You are a moderator.");
		return;
	}

	if ($player_data{$player}{setuprole})
	{
		my @choices = map { role_name($_) } split /,/, $player_data{$player}{role};
		message_or_notice($towho || $player, "You are $team. You may choose from the roles: " . join(", ", @choices), $bymsg);
		return;
	}

	my $role = get_player_role_name($player);
	my $roletext = $player_data{$player}{safe}{roledesc} || get_status($player, 'roletext') || "";
	my $wintext = group_config($team)->{wintext};
	my $to = $towho || $player;
	my $prefix = ($to eq $player ? "" : ($nonames ? "????: " : "$player: "));

	my $message = $prefix . get_roletext($player, $role, $team, $nonames);

	while (length($message) > 300)
	{
		my $break = 300;
		$break-- while $break > 0 && substr($message, $break - 1, 2) =~ /\w\w/;
		message_or_notice($to, substr($message, 0, $break), $bymsg);
		$message = substr($message, $break);
	}
	message_or_notice($to, $message, $bymsg);
	
	my $text;
	
	# --CHANGE-- Abilities and group abilities are sent seperately
	my @abilities = map { describe_ability($player, $_) } get_player_actions($player);
	if (@abilities)
	{
		$text = "Abilities: " . join(' ', @abilities);
		if ($text =~ /\bx/)
		{
			if (setup_rule('deepsouth')) {
				$text .= " x-abilities happen immediately when used.";
			}
			else {
				$text .= " x-abilities can be used during day or night.";
			}
		}
		message_or_notice($to, $prefix . $text, $bymsg);
	}
	if (get_player_group_actions($player))
	{
		my @abilities = map { describe_ability($player, $_) } get_player_group_actions($player);
		$text = "Group abilities: " . join(' ', @abilities);
		message_or_notice($to, $prefix . $text, $bymsg);
	}
	if (!$nonames) 
	{
		foreach my $group (get_player_team($player))
		{
			if (group_config($group)->{openteam} && $group_data{$group}{alive} > 1)
			{
				my @members;
				foreach my $player (get_group_members($group))
				{
					push @members, "$player (" . get_player_role_name($player) . ")";
				}
				$text = "Team members: " . join(", ", @members);
				message_or_notice($to, $prefix . $text, $bymsg);
			}
		}
	}
}

sub send_tip {
	my $player = shift;
	my @tips;
	
	my $role = get_player_role($player);
	@tips = (@tips, @{ $role_config{$role}{tips} }) if $role_config{$role}{tips};
	
	my $team = get_player_team_short($player);
	@tips = (@tips, @{ $group_config{$team}{tips} }) if $group_config{$team}{tips};
	
	foreach my $action (get_player_all_actions($player))
	{
		my $alias = $action_config{$action}{alias} || "";
		$alias =~ s/\s*#\d+//g;
		if ($action_config{$action}{tips})
		{
			@tips = (@tips, @{ $action_config{$action}{tips} });
		}
		elsif (exists $action_config{$alias} && $action_config{$alias}{tips})
		{
			@tips = (@tips, @{ $action_config{$alias}{tips} });
		}
	}
	
	return unless @tips;
	
	notice($player, "Tip: " . $tips[rand @tips]);
}

sub send_roles {
	foreach my $player (@players)
	{
		send_help $player, 0;
		#send_tip $player;
	}
}

sub show_alive {
	announce "Living players: " . join(' ', @alive);
}
sub show_playersin { 		# Daz
	announce "Players: " . join(' ', @players);
}
sub stop_game {
	# Log
	gamelog("end", time()) if $game_active;
	
	$game_active = 0;
	%players = %player_masks = %players_by_mask = ();
	@players = @alive = ();
	%moderators = ();
	@moderators = ();
	$phase = "";
	$day = 0;
	%reset_voters = %stop_voters = ();
	unschedule(\$votetimer);
	unschedule(\$pulsetimer);
	unschedule(\$nighttimer);
	unschedule(\$nightremindtimer);
	unschedule(\$nightmintimer);
	unschedule(\$starttimer);
	unschedule(\$chosentimer);
	# Clear timed action timers
	for (my $i = 0; $i < scalar(@timed_action_timers); $i++)
	{
		unschedule(\$timed_action_timers[$i]{timer}) if $timed_action_timers[$i]{timer};
	}
	# Clear recharge timers
	while (@recharge_timers) {
		my $timer = shift @recharge_timers;
		unschedule $timer;
	}
	while (@misc_timers) {
		my $timer = shift @misc_timers;
		unschedule $timer;
	}
	@timed_action_timers = ();
	@action_queue = @resolved_actions = @deepsouth_actions = ();
	@items_on_ground = ();

	update_voiced_players();
}

sub game_over {
	my @winners = @_;
	my %winning_players;
	my %winning_groups;
	
	return unless $game_active;

	$phase = "gameover";
	update_voiced_players();
	
	if (!@winners)
	{
		::bot_log "WIN nobody (draw)\n";
		announce "Game over. It's a draw!";
	}
	elsif ($winners[0] eq "")
	{
		::bot_log "WIN nobody (game stopped)\n" unless $phase eq 'signup';
		announce "The game has been stopped.";
	}
	else
	{
		::bot_log "WIN @winners\n";
		my @winner_descs;
		foreach my $winning_group (@winners)
		{
			$winning_groups{$winning_group}++;

			my @winning_players = get_group_members($winning_group);
			push @winner_descs, "($winning_group: @winning_players)";
			foreach my $player (@winning_players)
			{
				$winning_players{$player}++;
			}
		}
		announce "Game over! Winners: @winner_descs";
	}
	
	# Record stats
	if (!@winners || $winners[0] ne "")
	{
		foreach my $player (@players)
		{
			my $result = $winning_players{$player} ? "win" : "lose";
			$result = "draw" if !@winners;
			
			gamelog("result", "$player $result $player_data{$player}{startteam} $player_data{$player}{startrole} " .
				"$player_data{$player}{team} $player_data{$player}{role} " .
				(alive($player) ? "alive " : "dead ") . (get_status($player, 'killedby') || 'unknown'));
				
			my @stats;
			foreach my $key (sort keys %{$player_data{$player}{safe}{status}})
			{
				next unless $key =~ /^stats(.*)$/;
				my $stat = $1;
				push @stats, "$stat " . (get_status($player, "stats$stat") || 0);
			}
			gamelog("stats", "$player @stats");
		}

		my $numplayers = scalar(@players);

		if (@winners && !setup_rule('moderated', $cur_setup) && $cur_setup ne 'test' && $cur_setup ne 'replay' && $numplayers > 3)
		{
			read_adaptive_powers();

			if (0)
			{
				foreach my $player (@players)
				{
					my $role = $player_data{$player}{startrole};
					my $team = $player_data{$player}{startteam};
					next if $role_config{$role}{nonadaptive};
					next if $player_masks{$player} eq 'fake';

					my $baseteam = $team;
					$baseteam =~ s/-ally$|\d+$//;

					my $change = $winning_players{$player} ? 0.0325 : -0.03;

					# Bias ranges from -1 at 4 players to +1 at 12 players
					my $bias = ($numplayers - 8) / 4;
					$bias = 1 if $bias > 1;
					$bias = -1 if $bias < 1;

					if ($role !~ /\+/)
					{
						# Hack - only count the town side of sibling
						next if $baseteam eq 'mafia' && $role eq 'sib2';

						# Make sure the keys exist, to avoid warnings
						$role_config{$role}{power} = 0 unless defined($role_config{$role}{power});
						$role_config{$role}{powerbias} = 0 unless defined($role_config{$role}{powerbias});

						# This accelerates the rate of change until roles settle
						my $changemult = 5 - $role_config{$role}{changecount} / 10;
						$changemult = 1 if $changemult < 1;

						# If numplayers == 8 (bias 0), then the power at 4 and 12 players change by the normal amount.
						# If numplayers == 12 (bias +1), then the power at 12 players changes more than the normal amount, and the power at 4 players changes less.
						# If numplayers == 4 (bias -1), then the power at 4 players changes more than the normal amount, and the power at 4 players changes less.
						$role_config{$role}{power} += $change * $changemult;
						$role_config{$role}{powerbias} += $change * $bias;
						$role_config{$role}{changecount}++;

						# Also change the power of any derived roles
						foreach my $role2 (keys %role_config)
						{
							next unless $role_config{$role2}{alias};
							next unless $role_config{$role2}{alias} =~ /\b$role\b/;
		
							$role_config{$role2}{power} += $change * $changemult;
							$role_config{$role2}{powerbias} += $change * $bias;
							$role_config{$role2}{changederived}++;
						}
					}
					else
					{
						my @subroles = split /\+/, $role;
						foreach my $subrole (@subroles)
						{
							# Hack - only count the town side of sibling
							next if $baseteam eq 'mafia' && $subrole eq 'sib2';

							$role_config{$subrole}{powermultirole} = 0 unless defined($role_config{$subrole}{powermultirole});

							# Divide the change among all subroles
							$role_config{$subrole}{powermultirole} += $change * 2 / @subroles;
							$role_config{$subrole}{changemulti}++;
						}
					}
				}
			} # If 0

			# Clear the template power cache
			foreach my $role (keys %role_config)
			{
				delete $role_config{$role}{template_estimated_power};
			}

			if (0)
			{
				write_adaptive_powers();
			} # If 0
		}
	}

	# Print the setup
	if (!setup_rule('hidesetup', $cur_setup))
	{
		foreach my $team (sort keys %group_data)
		{
			my @members;
			foreach my $player (@players)
			{
				if ($player_data{$player}{startteam} eq $team)
				{
					push @members, $player . " (" . role_name($player_data{$player}{startrole}, 1) . ")";
				}
			}
			
			next unless @members;
			
			announce "$team: @members";
		}
	}
	
	foreach my $moderator (@moderators)
	{
		gamelog("moderator", "$moderator $player_masks{$moderator}");
	}

	# Record the last player(s) to win
	if (%winning_players) {
		my @temp_winners = grep { $player_masks{$_} ne 'fake' } 
			sort { lc $a cmp lc $b} keys %winning_players;
		@last_winners = @temp_winners if @temp_winners;

		$brag_count = 0;
		schedule(\$bragtimer, 120, \&brag) unless $just_testing;
	}

	@test_winners = sort keys %winning_players;

	stop_game();
}

sub read_adaptive_powers {
	open POWER, "<", "mafia/rolepower.dat";

	my $line;
	while ($line = <POWER>)
	{
		chomp $line;
		my ($role, @data) = split /\s/, $line;
		next if $role_config{$role}{nonadaptive};
		while (@data)
		{
			my $key = shift @data;
			my $value = shift @data;
			$role_config{$role}{$key} = $value;
		}
	}

	close POWER;

	::bot_log "Read adaptive roles\n";
}

sub write_adaptive_powers {
	open POWER, ">", "mafia/rolepower.dat.new";

	foreach my $role (sort keys %role_config)
	{
		next if $role_config{$role}{nonadaptive};
		next unless $role_config{$role}{changecount} || $role_config{$role}{changederived} || $role_config{$role}{changemulti};

		my $power = $role_config{$role}{power};
		my $powerbias = $role_config{$role}{powerbias};
		my $changecount = $role_config{$role}{changecount};
		my $powermultirole = $role_config{$role}{powermultirole};
		my $changederived = $role_config{$role}{changederived};
		my $changemulti = $role_config{$role}{changemulti};

		$power = 0 unless defined($power);
		$powerbias = 0 unless defined($powerbias);
		$changecount = 0 unless defined($changecount);
		$powermultirole = 0 unless defined($powermultirole);
		$changederived = 0 unless defined($changederived);
		$changemulti = 0 unless defined($changemulti);

		print POWER "$role power $power powerbias $powerbias powermultirole $powermultirole changecount $changecount changederived $changederived changemulti $changemulti\n";
	}

	close POWER;
	rename("mafia/rolepower.dat.new", "mafia/rolepower.dat");

	::bot_log "Wrote adaptive roles\n";
}

sub brag {
	unless ($game_active) {
		if (scalar(@last_winners) == 1) {
			announce "Congratulations to $last_winners[0] for a solo win in the last game!";
		}
		elsif (scalar(@last_winners) > 1) {
			announce "Congratulations to " . and_words(@last_winners) . " for winning the last game!";
		}
	}

	my $braginterval;
	if ($brag_count < 4) {
		my @bragintervals = (5, 10, 30, 60);
		$braginterval = $bragintervals[$brag_count];
	}
	else {
		$braginterval = 120;
	}

	if (++$brag_count < 20) {
		schedule(\$bragtimer, $braginterval * 60, \&brag);
	}
}

sub remove_votes {
	my $player = shift;

	if ($player_data{$player}{voting_for})
	{
		# Remove previous votes
		foreach my $votee (@{$player_data{$player}{voting_for}})
		{
			@{$player_data{$votee}{voted_by}} = grep {$_ ne $player } @{$player_data{$votee}{voted_by}};
		}
	}
	
	$player_data{$player}{voting_for} = undef;
}

sub has_action {
	my $player = shift;
	
	my @actions = get_player_all_actions($player);
	
	foreach my $action (@actions)
	{
		# Group actions don't count if someone else used them first
		my $group = get_action_group($player, $action);
		if ($group && $group_data{$group}{phase_action})
		{
			next;
		}
		
		# Don't count fully used actions
		if (!get_status($player, "act$action"))
		{
			next;
		}
		
		if ($action =~ /^auto/)
		{
			next;
		}
		if (setup_rule('deepsouth'))
		{
			return 1 if $phase eq 'day';
		}
		elsif ($action =~ /^x/)
		{
			return 1;
		}
		elsif ($action =~ /^day/)
		{
			return 1 if $phase eq 'day';
		}
		else
		{
			return 1 if $phase eq 'night';
		}
	}
	
	return 0;
}
	
sub check_actions {
	return if $phase eq 'night' && !$night_ok;
	
	foreach my $player (@alive)
	{
		next if !has_action($player);
		next if $player_data{$player}{phase_action};
		
		return 1;
	}

	if (setup_rule('freegroupaction', $cur_setup)) {
		foreach my $group (keys %group_data) {
			next if !get_group_actions($group);
			next if $group_data{$group}{phase_action};

			return 1;
		}
	}
	
	if ($phase eq 'night')
	{
		next_phase();
	}
	else
	{
		resolve_actions();
	}
	return 0;
}

sub enqueue_message {
	my ($player, $message, @extra) = @_;

	$message =~ s/#[A-Z]+(\d+)/$extra[$1 - 1]/ge;
	
	push @message_queue, [$player, $message];
}

sub flush_message_queue {
	return if $test_noflush;
	return if $need_roles;		# Don't send messages before roles

	if (@message_queue)
	{
		::bot_log "MESSAGE sending " . scalar(@message_queue) . " queued messages\n";
	}

	# Send all queued messages
	foreach my $message (@message_queue)
	{
		my ($recipient, $text) = @$message;
		#::bot_log "$message ";
		#::bot_log @$message, "\n";
		if (alive($recipient))
		{
			notice($recipient, $text);
			push @{$player_data{$recipient}{safe}{messages}}, "\u$phase $day: $text";
		}
		foreach my $player (@alive)
		{
			if (get_status($player, 'telepathy') eq $recipient)
			{
				my $who = get_status($recipient, "bussed2") || $recipient;
				notice($player, "$who: $text");
			}
		}
	}
	@message_queue = ();
}

sub clear_votes {
	foreach my $player (@players, "nolynch")
	{
		$player_data{$player}{voting_for} = undef;
		$player_data{$player}{voted_by} = undef;
	}
	$last_votecount_time = 0;
	
	foreach my $player (@alive)
	{
		my $votee = get_status($player, 'votelocked');
		next unless $votee;
		if (!alive($votee))
		{
			set_safe_status($player, 'votelocked', "");
			next;
		}
		set_votes($player, ($votee) x get_player_votes($player));
	}
}

sub clear_actions {
	foreach my $player (@players)
	{
		$player_data{$player}{phase_action} = "";
		$player_data{$player}{cur_targets} = undef;
	}
	foreach my $group (sort keys %group_data)
	{
		$group_data{$group}{phase_action} = "";
		$group_data{$group}{has_used_action} = 0;
	}
	@action_queue = ();
}

sub clear_temp {
	foreach my $player (@players)
	{
		$player_data{$player}{temp} = undef;
	}
}

sub night_reminder {
	announce "Waiting for all actions...";
	schedule(\$nightremindtimer, $config{night_reminder_time}, \&night_reminder) unless $just_testing;
}

sub construct_fixed_setup {
	my ($setup, $startphase, @roles) = @_;
	
	$setup_config{$setup}{players} = scalar(@roles);
	$setup_config{$setup}{roles} = [ map { $_->{role} . '/' . $_->{team} } @roles ];
	$setup_config{$setup}{start} = $startphase;
}

sub start_game {
	my $startphase = shift;

	$startphase = $cur_setup->{startphase} unless defined($startphase);

	send_setup_to_moderators();
	
	# Log
	gamelog("start", "$mafiachannel " . time() . " " . $cur_setup->{setup} . " " . scalar(@players));
	foreach my $player (@players)
	{
		gamelog("player", "$player $player_masks{$player}");
	}

	$startphase = "night" unless $startphase;	
	::bot_log "START $startphase\n";
	
	$need_roles = 1;

	@items_on_ground = ();

	foreach my $player (@alive) {
		handle_trigger($player, get_status($player, "onstart"));
	}
	
	unschedule(\$chosentimer) unless !setup_rule('rolechoices', $cur_setup);

	if ($startphase =~ /day/)
	{
		$phase = "day";
		$nokill_phase = 0;
		$day = 1;
		do_phase_actions();
		$phase = "daysetupwait";
		schedule(\$starttimer, 2 + $::linedelay * 1.5 * $line_counter, \&start_day );
	}
	else
	{
		$phase = "night";
		$nokill_phase = ($startphase =~ /nokill/);
		$day = 0;
		do_phase_actions();
		$phase = "nightsetupwait";
		schedule(\$starttimer, 2 + $::linedelay * 1.5 * $line_counter, \&start_night );
	}
}

sub send_moderator_setup {
	my ($fromnick) = @_;

	foreach my $group (sort keys %group_data)
	{
		next unless $group_data{$group}{alive};
		
		notice($fromnick, "$group: " . join(', ', map 
			{ $_ . ' (' . 
			  (get_player_role_truename($_) eq role_name(get_player_role($_), 1) ? get_player_role_truename($_) :
			   get_player_role_truename($_) . "/" . role_name(get_player_role($_), 1))
			  . (($player_data{$_}{safe}{roledesc} || get_status($_, 'roletext') || "") =~ /BUDDY/ ? " to " . $player_data{$_}{buddy} : "")
			  . ')'} 
			@{$group_data{$group}{members}}));
	}
}

sub send_setup_to_moderators {
	# Send teams to the moderator
	foreach my $moderator (@moderators)
	{
		send_moderator_setup($moderator);
	}
}

sub select_extra_claims {
	my ($setup, @roles) = @_;

	my $weirdness = setup_rule('weirdness', $setup); 
	$weirdness = rand(1.0) if setup_rule('randomweirdness', $setup);

	my %power = (town => rand(1.0));

	my $players = @roles;

	my @extraclaims = select_roles($setup, { townnormal => int(rand($players / 2)), townpower => int(rand($players / 3)) + 1, townbad => 0, sk => int(rand($players / 6)) + (rand() < 0.2 ? 1 : 0), survivor => int(rand($players / 6)) + (rand() < 0.2 ? 1 : 0), cult => 0, mafia => int(rand($players / 3)) + 1, mafia2 => 0, wolf => 0 }, $weirdness, $players, 1, \%power);

	if (grep { $_->{role} =~ /^sib/ } (@roles, @extraclaims))
	{
		push @extraclaims, { team => "town", role => "sib2" };
		push @extraclaims, { team => "mafia", role => "sib2" };
	}

	return @extraclaims;
}

sub setup {
	my $numplayers = @players;
	my $minplayers = setup_minplayers($cur_setup);
	
	$line_counter = 0;

	if (setup_rule('randomsetup', $cur_setup))
	{
		my @randomsetups = grep { 
			$setup_config{$_}{randomok} &&
			($setup_config{$_}{minplayersrandom} || setup_minplayers($_)) <= $numplayers &&
			setup_maxplayers($_) >= $numplayers
		} keys %setup_config;
		$cur_setup = $randomsetups[rand @randomsetups] if @randomsetups;
	}
	
	if ($numplayers < $minplayers)
	{
		announce "$numplayers players signed up - not enough players (minimum is $minplayers). The game has been cancelled.";
		stop_game();
	}
	else
	{
		# Hack: Shuffle shirts for eyewitness
		if ($setup_config{$cur_setup}{shirts})
		{
			my $shirts = $setup_config{$cur_setup}{shirts};
			shuffle_list($shirts);
		}
		
		my ($startphase, @roles) = select_setup($numplayers, $cur_setup);
		# construct_fixed_setup('replay', $startphase, @roles);
		assign_roles @roles;

		if (setup_rule('upick', $cur_setup))
		{
			announce "Signups are over. $numplayers playing. Please select your role name now using 'setrole'." . ($cur_setup eq "normal" ? "" : " (Setup: $cur_setup)");
		}
		elsif (setup_rule('moderated', $cur_setup))
		{
			announce "Signups are over. $numplayers playing. Please wait while the moderator assigns roles." . ($cur_setup eq "normal" ? "" : " (Setup: $cur_setup)");
		}
		else
		{
			announce "Signups are over. $numplayers playing. Sending roles... (Setup: $cur_setup)";

			if (((($setup_config{$cur_setup}{"numalts$numplayers"} || 0) == 1 || $setup_config{$cur_setup}{roles}) &&
				!grep(/,/, @{$setup_config{$cur_setup}{roles} || $setup_config{$cur_setup}{"roles${numplayers}_1"}}) &&
				!setup_rule('smalltown')) ||
				setup_rule('open') || setup_rule('semiopen'))
			{
				my %role_count;

				my @extraclaims = ();

				my $hiderolecount = setup_rule('semiopen') || 0;

				if ($hiderolecount)
				{
					@extraclaims = select_extra_claims($cur_setup, @roles);
				}

				foreach my $role (@roles, @extraclaims)
				{
					my $team = $role->{team};
					my $name = role_name($role->{role}, 1);
					$team =~ s/\d$// if $hiderolecount;
					$role_count{$team}{$name}++;
				}

				my %teamroles;
				foreach my $team (keys %role_count)
				{
					$teamroles{$team} = [ map { 
						$hiderolecount ? $_ :
						$role_count{$team}{$_} > 1 ? "$_ (x$role_count{$team}{$_})" : $_ 
					} sort keys %{$role_count{$team}} ];
				}
				my @teamroles = map { "[$_] " . join(', ', @{$teamroles{$_}}) } sort keys %teamroles;

				if ($hiderolecount)
				{
					announce("This is a semi-open setup. The possible roles are: @teamroles");
				}
				else
				{
					announce("This is a fixed setup. The roles are: @teamroles");
				}
			}

			if (setup_rule('smalltown'))
			{
				foreach my $player (@players)
				{
					my $publicrole = $player_data{$player}{publicrole};
					my $name = role_name($publicrole);

					$name .= " (" . $role_config{$publicrole}{class} . ")" if $role_config{$publicrole}{class};

					if ($role_config{$publicrole}{propername})
					{
						announce "$player is $name.";
					}
					else
					{
						announce "$player is the $name.";
					}
				}
			}
		}

		my @specialrules;

		push @specialrules, "Moderated" if setup_rule('moderated', $cur_setup);
		push @specialrules, "Theme roles" if setup_rule('theme', $cur_setup);
		# push @specialrules, "Chosen roles" if setup_rule('rolechoices', $cur_setup);
		push @specialrules, "No incomplete role PMs" if setup_rule('nobastard', $cur_setup);
		push @specialrules, "Day start" if $startphase eq 'day';
		push @specialrules, "Cop head start" if $startphase eq 'nightnokill';
		push @specialrules, "No mafia kill" if setup_rule('no_group_actions', $cur_setup);
		push @specialrules, "Roles not revealed on death" if setup_rule('hidedeath', $cur_setup) || setup_rule('noreveal', $cur_setup);
		push @specialrules, "Dayless" if setup_rule('noday', $cur_setup);
		push @specialrules, "Nightless" if setup_rule('nonight', $cur_setup);
		push @specialrules, "Deep south" if setup_rule('deepsouth', $cur_setup);

		if (@specialrules)
		{
			announce("The following special rules are in effect: " . join(', ', @specialrules));
		}

		$cur_setup = { setup => $cur_setup, numplayers => $numplayers, startphase => $startphase };

		@message_queue = ();
		
		$phases_without_kill = 0;
		$resolving = $lynching = 0;

		foreach my $automoderator (keys %automoderators)
		{
			next if $players{$automoderator};
			add_moderator($automoderator, $automoderators{$automoderator});
		}
	
		
		if (!setup_rule('upick', $cur_setup) && !setup_rule('moderated', $cur_setup) && !setup_rule('maxchoices', $cur_setup))
		{
			start_game($startphase);
		}
		if (setup_rule('maxchoices', $cur_setup))
		{
			announce "Please choose your role using /msg $::nick choose <role>";
			announce "Players: " . join(' ', @players); 		# Daz
			announce "The game will begin in $config{'chosen_time'} seconds or when all choices are in";
			schedule(\$chosentimer, $config{"chosen_time"}, \&end_choosing);
		}
	}
}

sub setup_minplayers {
	my ($setup) = @_;

	return setup_rule('players', $setup) || setup_rule('minplayers', $setup) || $config{"minimum_players"};
}

sub setup_maxplayers {
	my ($setup) = @_;

	return setup_rule('players', $setup) || setup_rule('maxplayers', $setup) || $config{"maximum_players"};
}

sub end_signups_warning {
	return unless $phase eq 'signup';

	announce "Everybody in? The game starts in 30 seconds!";
}

sub end_signups {
	return unless $phase eq 'signup';

	unschedule(\$signuptimer);
	unschedule(\$signupwarningtimer);

	@players = @moderators = ();
	foreach my $player (sort {lc $a cmp lc $b} keys %players)
	{
		push @players, $player if $players{$player} && !$moderators{$player};
		push @moderators, $player if $players{$player} && $moderators{$player};
	}
	
	mod_notice("You are a moderator for this game. This gives you additional commands. Use '!$mafia_cmd showmodcommands' to see the available moderator commands.");
	
	$phase = "setup";
 	setup();

	update_voiced_players();
}

sub end_choosing {	
	my $args;

	foreach my $player (@players)
	{
		if (!alive($player))
		{
			notice($player, "Your role has been chosen for you because you failed to submit a choice within $config{'chosen_timer'} seconds");
			&choose_role( $::connection , 'choose' , 'private' , $player, $::nick, $args);
		}
		
	}
	return;
}

sub canonicalize_role {
	my ($role, $validate, $team) = @_;

	# Existing roles don't need to be canonicalized
	return $role if is_real_role($role) && !$team;

	# Cache
	our %canonicalize_cache;
	if ($validate && $canonicalize_cache{$role} && $canonicalize_cache{$role}{$team || '*'})
	{
		# ::bot_log("CANONICALIZE cache hit ($role, " . ($team || '*') . ")\n");
		return $canonicalize_cache{$role}{$team || '*'};
	}

	# Make a valid role
	my @roleparts = grep { $_ !~ /^\*/ } recursive_expand_role($role);
	
	# Fix teams
	$team =~ s/\d+$// if $team;
	@roleparts = map { $role_config{$_}{status}{"teamaltrole$team"} || $_ } @roleparts if $team;

	my $validrole = shift @roleparts;
	@roleparts = sort { 
		($role_config{$a}{template} || 0) <=> ($role_config{$b}{template} || 0) ||
		defined($role_config{$a}{truename}) <=> defined($role_config{$b}{truename})
	} @roleparts;
	while (@roleparts)
	{
		my $rolepart;
		for (my $i = 0; $i <= $#roleparts; $i++)
		{
			last if $role_config{$roleparts[$i]}{template} && !$role_config{$roleparts[0]}{template};
			if (valid_template($roleparts[$i], $validrole) && 
			    defined(combine_roles($validrole, $roleparts[$i], 1)))
			{
				$rolepart = splice @roleparts, $i, 1;
				last;
			}
		}
		unless ($rolepart)
		{
			for (my $i = 0; $i <= $#roleparts; $i++)
			{
				last if $role_config{$roleparts[$i]}{template} && !$role_config{$roleparts[0]}{template};
				if (valid_template($roleparts[$i], $validrole))
				{
					$rolepart = splice @roleparts, $i, 1;
					last;
				}
			}
		}
		$rolepart = shift @roleparts unless $rolepart;

		next if $validate && !valid_template($rolepart, $validrole);

		my $combined_role = combine_roles($validrole, $rolepart);
		if (defined($combined_role))
		{
			$validrole = $combined_role;
			next;
		}

		if (is_vanilla_role($rolepart))
		{
			next;
		}
		if (!$role_config{$rolepart}{template} && is_vanilla_role($validrole))
		{
			$validrole = $rolepart;
			next;
		}
		if ($validrole eq $rolepart)
		{
			next;
		}
		$validrole .= '+' . $rolepart;
	}

	if ($validate)
	{
		$canonicalize_cache{$role}{$team || '*'} = $validrole;
	}

	return $validrole;
}

sub transform_player {
	my ($player, $role, $team, $forcechange, $recruiter) = @_;

	my $oldrole = get_player_role($player);
	my $oldteam = get_player_team($player);

	# If role isn't given, use the default for the role
	if (!$role && !$team)
	{
		($role, $team) = split /,/, get_status($player, 'transform');
	}

	# If role isn't given, use the old role
	$role = $oldrole unless $role;

	# If team isn't given, use the old team
	$team = $oldteam unless $team;
	
	# If team ends with an '0', (such as sk0 or survivor0) pick an unused number
	if ($team =~ s/0$//)
	{
		my $teamnum = 1;
		$teamnum++ while exists $group_data{"$team$teamnum"};
		$team .= $teamnum;
	}

	# If role is in the form "old=new", transform just part of the role
	if ($role =~ /=/)
	{
		my ($oldpart, $newpart) = map { quotemeta $_ } split /=/, $role;
		$role = $oldrole;
		$role = recursive_expand_role($role);
		$role =~ s/\b$oldpart\b/$newpart/;
		$role = canonicalize_role($role, 1, $team);
	}
	# If the role is in the form "+template", add the template to existing role
	elsif ($role =~ /^\+/)
	{
		$role = $oldrole . $role;
		$role = canonicalize_role($role, 1, $team);
	}
	
	::bot_log("TRANSFORM $player $role $team\n");
	
	# If both role and team are the same, and change is not forced, do nothing
	return if $role eq $oldrole && $team eq $oldteam && !$forcechange;
	
	my $oldsetuprole = expand_setuprole(get_player_role($player));
	my $newsetuprole = expand_setuprole($role);
	initialize_player_action_uses($oldsetuprole, "actions");
	initialize_player_action_uses($newsetuprole, "actions");
	my $oldstatus = $player_data{$player}{status};

	my $setuprole = { 
		role => $role,
		team => $team,
		alive => alive($player),
		startrole => $player_data{$player}{startrole},
		startteam => $player_data{$player}{startteam},
		temp => $player_data{$player}{temp},
		safe => $player_data{$player}{safe},
		phase_action => $player_data{$player}{phase_action},
		voting_for => $player_data{$player}{voting_for},
		delayed_actions => $player_data{$player}{delayed_actions},
		buddy => $player_data{$player}{buddy},
	};

	if ($team ne $oldteam)
	{
		my $baseteam = $team;
		$baseteam =~ s/\d+$//;
		my $oldbaseteam = $oldteam;
		$oldbaseteam =~ s/\d+$//;

		if ($group_config{$oldbaseteam}{openteam})
		{
			foreach my $member (get_group_members($oldteam))
			{
				next if $member eq $player;
				enqueue_message($member, "$player has left your team.");
			}
		}
		if ($group_config{$baseteam}{openteam})
		{
			foreach my $member (get_group_members($team))
			{
				next if $member eq $player;
				next if $member eq $recruiter;
				enqueue_message($member, "$player has joined your team.");
			}
		}
	}
	
	assign_one_role($player, $setuprole);
	calculate_group_members();

	# Carry over statuses that didn't depend on the role
	unless ($forcechange)
	{
		my %newsetuprolestatus = ( %{$newsetuprole->{status}} );
		foreach my $action (@{$newsetuprole->{actions} || []}) {
			my $shortaction = $action;
			my $count = '*';
			$count = $1 if $shortaction =~ s/;(\d+)$//;
			$newsetuprolestatus{"act$shortaction"} = $count;
		}

		my %oldsetuprolestatus = ( %{$oldsetuprole->{status}} );
		foreach my $action (@{$oldsetuprole->{actions} || []}) {
			my $shortaction = $action;
			my $count = '*';
			$count = $1 if $shortaction =~ s/;(\d+)$//;
			$oldsetuprolestatus{"act$shortaction"} = $count;
		}

		foreach my $status (keys %$oldstatus)
		{
			# We save status if:
			# The new role does not change the status, and
			# The status was set at something other than default, and
			# Either the old status or new status is interesting
			if (($oldsetuprolestatus{$status} || "") eq ($newsetuprolestatus{$status} || "") &&
			    ($oldstatus->{$status} || "") ne ($oldsetuprolestatus{$status} || "") &&
			    ($oldstatus->{$status} || $newsetuprole->{status}{$status}))
			{
				if ($status =~ /^act(.*)$/ && $oldstatus->{$status})
				{
					my $action = $1;
					my $hasability = 0;
					foreach my $action2 (get_player_all_actions($player))
					{
						$hasability = 1 if $action2 eq $action;
					}
					push @{$player_data{$player}{actions}}, $action unless $hasability;
				}
				set_status($player, $status, $oldstatus->{$status});
			}
		}
	}
	
	# Inform the moderator
	if ($phase ne 'setup')
	{
		mod_notice("$player has been assigned the role " . get_player_role_truename($player) . " ($team)");
	}

	handle_trigger($player, get_status($player, "onstart")) unless get_status($player, "onstart") eq ($oldstatus->{onstart} || "");
}

sub adjust_player_role_after_change {
	my ($player) = @_;

	my $role = get_player_role($player);
	my $team = get_player_team($player);
	my $adjustedrole = canonicalize_role($role, 1, $team);

	transform_player($player, $adjustedrole, $team);
}

sub handle_trigger {
	my ($player, $result, $special, @targets) = @_;

	return unless $result;	

	::bot_log "TRIGGER $player $result\n";
	
	if ($result eq 'action')
	{
		do_auto_action($player, "", "", "notrigger,noblock", $special, @targets);
	}
	elsif ($result =~ /^action:(.*)$/)
	{
		do_auto_action($player, $1, "", "notrigger,noblock,locked", $special, @targets);
	}
	elsif ($result =~ /^use:(.*)$/)
	{
		do_auto_action($player, $1, "", "notrigger", $special, @targets);
	}
	elsif ($result =~ /^activate:(.*)$/)
	{
		my $action = $1;
		if (get_status($player, "act$action")) {
			reduce_status($player, "act$action");
			$action = action_base($action);
			do_auto_action($player, $action, "", "notrigger", $special, @targets);
		}
	}
	elsif ($result eq 'transform')
	{
		transform_player($player);
		enqueue_message($player, $messages{action}{transform});
		send_help($player, 1);
	}
	elsif ($result =~ /^transform:(.*)$/)
	{
		my ($newrole, $newteam) = split /,/, $1, 2;
		transform_player($player, $newrole, $newteam);
		enqueue_message($player, $messages{action}{transform});
		send_help($player, 1);
	}
	elsif ($result eq 'silenttransform')
	{
		transform_player($player);
	}
	elsif ($result =~ /^silenttransform:(.*)$/)
	{
		my ($newrole, $newteam) = split /,/, $1, 2;
		transform_player($player, $newrole, $newteam);
	}
	elsif ($result eq 'inherit')
	{
		my $role = get_player_role($targets[0]);
		my $xrole = get_status($player, 'inherittemplate');
		if ($xrole)
		{
			$role .= "+$xrole" if $xrole ne '*';
			my $preinheritrole = get_status($player, 'preinheritrole');
			if (!$preinheritrole)
			{
				$preinheritrole = get_player_role($player);
				set_status($player, 'preinheritrole', $preinheritrole);
			}
			my @parts = recursive_expand_role($preinheritrole);
			@parts = grep { $_ !~ /^\*/ } @parts;
			@parts = grep { !$role_config{$_}{status}{inherittemplate} } @parts;
			$preinheritrole = join('+', @parts);
			$role .= "+$preinheritrole" if $preinheritrole;
		}
		transform_player($player, $role);
		enqueue_message($player, $messages{action}{transform});
		send_help($player, 1);
	}
	elsif ($result eq 'win')
	{
		game_over(get_player_team($player));
		return;
	}
	elsif ($result eq 'winsoft')
	{
		my $team = get_player_team($player);
		$group_data{$team}{won} = 1;
		foreach my $player2 (get_group_members($team))
		{
			notice($player2, "You win! However, the game will keep going until the remaining players have won or lost.");
			announce "$player2 has won the game.";
			reduce_status($player2, 'revive', '*');
			kill_player($player2);
			set_status($player2, 'immuneresurrect');
		}
		update_voiced_players();
	}
	else
	{
		::bot_log("TRIGGER strange trigger $result!\n");
		mod_notice("Looks like a bug: $player did trigger '$result' but I can't do that.");
	}
}

sub miller_role {
	my ($role, $team) = @_;
	my $miller = canonicalize_role($role, 1, $team);
	$miller = join '+', grep {
		!$role_config{$_}{status}{deathrole} &&
		!$role_config{$_}{status}{inspectrole}
	} split /\+/, $miller;
	return $miller;
}

sub kill_player {
	my ($player, $killer) = @_;
	
	return unless alive($player);
	
	# Check for revive
	if (get_status($player, 'revive'))
	{
		reduce_status($player, 'revive');
		
		my $msg = $messages{death}{revived};
		$msg =~ s/#PLAYER1/$player/;
		announce $msg;
		
		if (get_status($player, 'revive') eq 'transform')
		{
			transform_player($player);
			enqueue_message($player, $messages{action}{transform});
			send_help($player, 1);
		}
		elsif (get_status($player, 'revive') =~ /^transform:(.*)$/)
		{
			my ($newrole, $newteam) = split /,/, $1, 2;
			transform_player($player, $newrole, $newteam);
			enqueue_message($player, $messages{action}{transform});
			send_help($player, 1);
		}

		my $damage = get_status($player, 'damage') || 0;
		my $hp = get_status($player, 'hp') || 100;
		my $revivehp = get_status($player, 'revivehp') || 1;

		if ($hp - $damage < $revivehp) {
			set_safe_status($player, 'damage', $hp - $revivehp);
		}
		
		handle_trigger($player, get_status($player, 'onrevive'));
		
		increase_safe_status($player, 'statsrevives', 1);
		
		return;
	}
	
	::bot_log "KILL $player\n";
	
	$player_data{$player}{alive} = 0;

	my $role = get_status($player, 'deathrole') || (setup_rule('noreveal', $cur_setup) ? get_player_role_name($player) : get_player_role_truename($player));
	my $team = get_status($player, 'deathteam') || get_player_team_short($player);
	if ($role eq '*') {
		$role = role_name(miller_role(get_player_role($player), $team));
	}
	
	announce "$player was a $role ($team)." unless setup_rule('hidesetup', $cur_setup) or setup_rule('hidedeath', $cur_setup);

	set_safe_status($player, 'killedby', $killer);
	increase_safe_status($player, 'statsdeaths', 1);
	increase_safe_status($player, 'statskilled', 1) if $killer;
	increase_safe_status($killer, 'statskills', 1) if $killer;
	
	# Inform the moderator
	mod_notice("$player was killed by $killer.") if $killer;

	if (get_status($player, 'recruit'))
	{
		my @followers;
		foreach my $cultist (get_group_members(get_player_team($player)))
		{
			next unless get_status($cultist, 'recruited');
			push @followers, $cultist;
		}
		if (@followers)
		{
			announce "${player}'s followers have committed suicide.";
			foreach my $cultist (@followers)
			{
				kill_player($cultist, '');
			}
		}
	}
	
	# Kill siblings
	foreach my $group (get_player_groups($player))
	{
		next unless group_config($group)->{sibling};
		
		foreach my $player2 (get_group_members($group))
		{
			next unless alive($player2);
			
			my $msg = $messages{death}{sibling};
			$msg =~ s/#PLAYER1/$player2/;
			announce $msg;
			kill_player($player2);
		}
	}
	
	# Trigger the player
	handle_trigger($player, get_status($player, "ongrave"), undef, $killer);

	# Trigger the killer
	handle_trigger($killer, get_status($killer, "onkill"), undef, $player) if $killer && alive($killer);
	
	# Trigger other players
	my $roleshort = get_player_role($player);
	my $roleexpanded = recursive_expand_role($roleshort);
	my $teamshort = get_player_team_short($player);
	my @triggers = ();
	foreach my $player2 (@alive)
	{
		my @results;
		push @results, get_status($player2, "onbuddydeath") if $player eq $player_data{$player2}{buddy};
		push @results, get_status($player2, "onroledeath:$roleshort");
		push @results, get_status($player2, "onteamdeath:$teamshort");
		push @results, get_status($player2, "ondeath");
		push @results, get_status($player2, "onpowerdeath") if role_power(get_player_role($player)) >= 0.4;
		if ($roleexpanded =~ /\+/)
		{
			foreach my $subrole (split /\+/, $roleexpanded)
			{
				push @results, get_status($player2, "onroledeath:$subrole");
			}
		}
		foreach my $result (@results)
		{
			handle_trigger($player2, $result, undef, $player);
		}
		
		# Only one kill1 takes effect per death
		@results = ();
		push @results, get_status($player2, "onroledeath1:$roleshort");
		push @results, get_status($player2, "ondeath1");
		push @results, get_status($player2, "onpowerdeath1") if role_power(get_player_role($player)) >= 0.4;
		if ($roleexpanded =~ /\+/)
		{
			foreach my $subrole (split /\+/, $roleexpanded)
			{
				push @results, get_status($player2, "onroledeath1:$subrole");
			}
		}
		foreach my $result (@results)
		{
			push @triggers, [$player2, $result, undef, $player] if $result;
		}
	}
	# Handle kill1
	if (@triggers)
	{
		my $trigger = $triggers[rand @triggers];
		handle_trigger(@$trigger);
	}

	# Give the ghost action (if any)
	my $ghostaction = get_status($player, 'ghostaction');
	if ($ghostaction) {
		push @{$player_data{$player}{actions}}, "x$ghostaction";
		increase_status($player, "actx$ghostaction", 1);
		notice($player, "You have gained the ability to use '$ghostaction' on another player while dead. You must use this within the next 60 seconds, or it will be used on a random player.");

		my $timer;
		push @misc_timers, \$timer;
		schedule(\$timer, 60, sub {
			return unless get_status($player, 'ghostaction');

			#my ($player, $action, $longaction, $xtype, $special, @targets) = @_;
			do_auto_action($player, $ghostaction, $ghostaction, "notrigger");
			reduce_status($player, 'ghostaction', '*');
		});
	}
	
	# Drop items
	my $player_role = get_player_role($player);
	foreach my $sub_role (split /\+/, recursive_expand_role($player_role)) {
		drop_item($player, $sub_role, 1) if $role_config{$sub_role}{item};
	}
	
	# Kill followers of a cult leader
	clear_votes();
	calculate_group_members();
	calculate_alive();
	calculate_lynch_votes();
	
	$phases_without_kill = 0;
}

sub do_auto_action {
	my ($player, $action, $longaction, $xtype, $special, @targets) = @_;
	
	my $type = ($xtype ? "auto,$xtype" : "auto");
	
	$action = get_status($player, 'auto') unless $action;
	
	# Handle default targets for most actions here
	if ($action_config{$action} && $action_config{$action}{targets} && !@targets)
	{
		my $default = get_status($player, 'default') || '#?';
		my $numtargets = scalar(@{$action_config{$action}{targets}});

		if ($default eq '#?')
		{
			for my $i (1 .. $numtargets)
			{
				my $targetrestrict = $action_config{$action}{targets}[$i - 1];
				my @posstargets = grep { $_ ne $player } @players;
				@posstargets = grep { alive($_) } @posstargets if $targetrestrict =~ /\balive\b/;
				@posstargets = grep { !alive($_) } @posstargets if $targetrestrict =~ /\bdead\b/;
				for my $prevtarget (@targets)
				{
					@posstargets = grep { $_ ne $prevtarget } @posstargets;
				}
				shuffle_list(\@posstargets);

				push @targets, (shift(@posstargets) || "none");
			}
		}
		elsif ($default =~ /^#b$/i)
		{
			@targets = ($player_data{$player}{buddy}) x $numtargets;
		}
	}

	mod_notice("$player has automatically used action '" . ($longaction || $action) . "'" . (@targets ? " on " . join(' and ', @targets) : "") . ($xtype ? " [$xtype]" : ""));

	enqueue_action($player, "", $action, $longaction, $type, $special, @targets);
	resolve_actions() unless $resolving || $phase eq 'night';
}

sub release_delayed_actions {
	my ($player) = @_;

	return unless $player_data{$player}{delayed_actions};

	::bot_log "RELEASE $player\n";

	foreach my $action (@{$player_data{$player}{delayed_actions}})
	{
		$action->{type} = $action->{type} ? "$action->{type};notrigger,nodelay" : "notrigger,nodelay";
		push @action_queue, $action;

		::bot_log "  * $action->{player} $action->{action}" . ($action->{status} && length($action->{status}) <= 15 ? " ($action->{status})" : "") . " [$action->{type}] @{$action->{targets}}\n";
	}

	delete $player_data{$player}{delayed_actions};
}

sub pulse {
	foreach my $player (@alive)
	{
		my $result = get_status($player, "onpulse");
		handle_trigger($player, $result);
	}

	foreach my $player (@alive)
	{
		my $regen = get_status($player, "regen");

		if ($regen) {
			reduce_status($player, "damage", $regen);
			#mod_notice("$player regenerated $regen damage");
		}

		my $pulsedamage = get_status($player, "pulsedamage");

		if ($pulsedamage) {
			increase_safe_status($player, "damage", $pulsedamage);
			#mod_notice("$player took $pulsedamage pulse damage");
			# announce "$player took $pulsedamage damage.";
			if (get_status($player, "damage") >= (get_status($player, "hp") || 100))
			{
				action_kill($player, "", $player);
			}
		}
	}
	
	schedule(\$pulsetimer, 10, \&pulse);
}

sub do_phase_actions {
	# Clear reset/stop votes
	%reset_voters = %stop_voters = ();

	# Handle poison & disease
	foreach my $player (@alive)
	{
		if (get_status($player, 'poisoned'))
		{
			reduce_status($player, 'poisoned', 1);
			if (!get_status($player, 'poisoned'))
			{
				my $msg = $messages{death}{poisoned};
				$msg =~ s/#PLAYER1/$player/;
				$msg =~ s/#TEXT1/poison/;
				announce $msg;
				kill_player($player);
			}
		}
		if ($phase eq 'day' && get_status($player, 'disease') && rand(100) < get_status($player, 'disease'))
		{
			my $msg = $messages{death}{poisoned};
			$msg =~ s/#PLAYER1/$player/;
			$msg =~ s/#TEXT1/disease/;
			announce $msg;
			kill_player($player);
		}
	}
	
	# Handle disable
	foreach my $player (@alive)
	{
		if (get_status($player, 'disabled'))
		{
			reduce_status($player, 'disabled', 1);
			if (!get_status($player, 'disabled'))
			{
				my $msg = $messages{action}{disable2};
				enqueue_message($player, $msg);
			}
		}
	}
	
	# Handle RAF
	if ($phase eq 'day')
	{
		my %tokill;
		# First, announce actions.
		foreach my $player (@alive)
		{
			next unless get_status($player, 'duelist');
			my $target = get_status($player, 'shot') || 'sky';
			announce "$player shot $target.";
		}
		# Next, handle players who shot other players.
		foreach my $player (@alive)
		{
			my $target = get_status($player, 'shot');
			if ($target && $target ne $player)
			{
				if (get_status($target, 'shot') eq $target)
				{
					set_temp_status($target, 'saved', '*');
					$tokill{$player} = $target;
				}
				else
				{				
					$tokill{$target} = $player;
				}
			}
		}
		# Handle players who shot themselves.
		foreach my $player (@alive)
		{
			my $target = get_status($player, 'shot');
			if ($target eq $player && !get_status($player, 'saved'))
			{
				$tokill{$player} = $player;
			}
		}

		foreach my $player (sort keys %tokill)
		{
			announce "$player is dead.";
		}
		
		if (scalar(keys %tokill) < @alive)
		{
			foreach my $player (sort keys %tokill)
			{
				kill_player($player, $tokill{$player});
			}
		}
		# If everyone is dead, resurrect players who died
		else
		{
			foreach my $player (@alive)
			{
				my $msg1 = $messages{action}{resurrect1};
				$msg1 =~ s/#PLAYER2/$player/;
				announce $msg1;			
			}
		}
	}

	# Handle rock-paper-scissors
	if ($phase eq 'day') {
		my %rps = (rock=>0, paper=>0, scissors=>0);
		foreach my $player (@alive) {
			my $choice = get_status($player, 'rps') || 'none';
			$rps{$choice}++;
			if ($choice ne 'none') {
				announce "$player played $choice.";
			}
		}

		my %tokill;
		foreach my $player (@alive) {
			my $choice = get_status($player, 'rps') || 'none';
			my $kill = 0;
			if ($choice eq 'none') {
				$kill = 1 if $rps{rock} > 0 || $rps{paper} > 0 || $rps{scissors} > 0;
			}
			elsif ($choice eq 'rock') {
				$kill = 1 if $rps{paper} >= $rps{rock} && $rps{paper} > $rps{scissors};
				$kill = 1 if $rps{paper} >= 1 && $rps{scissors} == 0;
			}
			elsif ($choice eq 'paper') {
				$kill = 1 if $rps{scissors} >= $rps{paper} && $rps{scissors} > $rps{rock};
				$kill = 1 if $rps{scissors} >= 1 && $rps{rock} == 0;
			}
			elsif ($choice eq 'scissors') {
				$kill = 1 if $rps{rock} >= $rps{scissors} && $rps{rock} > $rps{paper};
				$kill = 1 if $rps{rock} >= 1 && $rps{paper} == 0;
			}
			$tokill{$player}++ if $kill;
		}

		foreach my $player (sort keys %tokill)
		{
			announce "$player is dead.";
		}
		
		if (scalar(keys %tokill) < @alive)
		{
			foreach my $player (sort keys %tokill)
			{
				kill_player($player, $tokill{$player});
			}
		}
	}
	
	clear_actions();
	clear_temp();

	flush_message_queue();	
	check_winners();
	
	my $nokillphases = setup_rule('nokillphases', $cur_setup) || 8;
	
	# Check for draw by stalemate
	if ($phases_without_kill >= $nokillphases)
	{
		announce "No kills have happened in the past " . ($nokillphases / 2) . " days.";
		game_over();
	}
	elsif ($phases_without_kill == $nokillphases - 2)
	{
		announce "No kills have happened in the past " . (($nokillphases - 2) / 2) . " days. If there are no kills in the next day, the game will be a draw.";
	}
	$phases_without_kill++;
	
	# Clear resolved actions
	@resolved_actions = ();

	# Handle ondusk - special
	if ($phase eq 'night')
	{
		my @save_alive = @alive;
		$phase = 'dusk';
		foreach my $player (@save_alive)
		{
			foreach my $trigger ("onall", "ondusk", "ondusk$day")
			{
				my $result = get_status($player, $trigger);
				handle_trigger($player, $result);
			}
		}
		resolve_actions() if @action_queue;
		$phase = 'night';
	}

	# Clear resolved actions
	@resolved_actions = ();

	# Handle onX triggers
	$resolving = 1;
	my @save_alive = @alive;
	foreach my $player (@save_alive)
	{
		foreach my $trigger ("on$phase", "on$phase$day")
		{
			my $result = get_status($player, $trigger);
			handle_trigger($player, $result);
		}

		if ($phase eq 'day')
		{
			my $result = get_status($player, "onall");
			handle_trigger($player, $result);
		}
	}
	
	# Handle automatic actions
	foreach my $player (@save_alive)
	{
		foreach my $action (get_player_all_actions($player))
		{
			next unless $action =~ /^auto/;
			if (!setup_rule('deepsouth'))
			{
				next if $action =~ /^autoday/ && $phase ne 'day';
				next if $action !~ /^auto(day|x)/ && $phase eq 'day';
			}
			
			next unless get_status($player, "act$action");
			reduce_status($player, "act$action", 1);
			
			my $shortaction = action_base($action);
			
			::bot_log "AUTO $player $action\n";
			do_auto_action($player, $shortaction, $action, "");
		}
	}

	$resolving = 0;
	resolve_actions() if @action_queue && $phase eq 'day';

	# Undelay delayed actions
	if ($phase eq 'night')
	{
		foreach my $player (@players)
		{
			next unless $player_data{$player}{delayed_actions};
			release_delayed_actions($player);
		}
	}

	# Send roles
	if ($need_roles) {
		# Quash all messages sent before the roles
		@message_queue = ();
		send_roles();
		$need_roles = 0;
	}
	
	flush_message_queue() if $phase eq 'day';

	# Voice/unvoice players
	update_voiced_players() unless setup_rule('deepsouth');
}

sub vote_reminder {
	vote_count();
	schedule(\$votetimer, $config{votecount_time}, \&vote_reminder) unless $just_testing;
}

sub start_day {
	$phase = "day";
	update_voiced_players();
	calculate_lynch_votes();
	announce "It is $phase $day. It takes $lynch_votes votes to lynch.";
	show_alive();
	clear_votes();
	schedule(\$votetimer, $config{votecount_time}, \&vote_reminder) unless $just_testing;
	schedule(\$pulsetimer, 10, \&pulse);

	# If no one can vote and there are no day abilities, skip day.
	my $maxvotes = get_total_votes();
	my $actions = check_actions();
	if (!$maxvotes && !$actions)
	{
		next_phase();
		return;
	}
}

sub end_day {
	unschedule(\$votetimer);
	unschedule(\$pulsetimer);
	
	# Clear extra votes
	foreach my $player (@alive)
	{
		set_safe_status($player, 'extravote', "");
		set_safe_status($player, 'votelocked', "");
	}

	# Handle Deep South actions
	if (@deepsouth_actions) {
		@action_queue = @deepsouth_actions;
		@deepsouth_actions = ();
		resolve_actions();
	}

	# Clear recharge timers
	while (@recharge_timers) {
		my $timer = shift @recharge_timers;
		unschedule $timer;
	}
}

sub start_night {
	$phase = "night";
	update_voiced_players();
	my $nick = $::nick;
	announce "It is $phase $day. Night ends in $config{night_time} s (or when all choices are in). Submit actions to $nick.";
	show_alive();
	schedule(\$nighttimer, $config{night_time}, \&next_phase);
	schedule(\$nightremindtimer, $config{night_reminder_time}, \&night_reminder) unless $just_testing;
	schedule(\$nightmintimer, 10 + rand(10), sub { $night_ok = 1; check_actions(); } );
	$night_ok = 0;
}

sub end_night {
	unschedule(\$nighttimer);
	unschedule(\$nightremindtimer);
	unschedule(\$nightmintimer);
	resolve_actions();
}

sub next_phase {
	my $next_phase;
	
	$nokill_phase = 0;

	if ($phase eq 'day')
	{
		end_day();
		$next_phase = 'night';
	}
	else
	{
		end_night();
		$next_phase = 'day';
	}

	return unless $game_active;

	$phase = $next_phase;
	$day++ if $phase eq 'day';
	
	::bot_log "PHASE $phase $day\n";
	
	do_phase_actions();
	return unless $game_active;
	
	if ($phase eq 'day' && setup_rule('noday', $cur_setup))
	{
		$phase = $next_phase = 'night';
	}
	elsif ($phase eq 'night' && setup_rule('nonight', $cur_setup))
	{
		$phase = $next_phase = 'day';
		$day++;
	}
	
	if ($next_phase eq 'day')
	{
		start_day();
	}
	else
	{
		start_night();
	}
}

sub poisoned_team_members {
	my $team = shift;
	my $poisoned = 0;
	
    player:
	foreach my $player (@alive)
	{
		if (get_player_team($player) eq $team)
		{
			$poisoned++ if get_status($player, 'poisoned');
		}
	}
	
	return $poisoned;
}

sub nonaligned_killers {
	my $team = shift;
	my $killers = 0;
	
	my $baseteam = $team;
	$baseteam =~ s/\d+$//;
	
    player:
	foreach my $player (@players)
	{
		next unless alive($player) || get_status($player, 'ghostaction');
		if (get_player_team($player) !~ /^$team$|^$baseteam-ally$|^survivor\d*$/)
		{
			if (@items_on_ground) 
			{
				$killers++;
				next player;
			}

			foreach my $action (get_player_all_actions($player))
			{
				next unless get_status($player, "act$action");
				my $shortaction = action_base($action);
				my $replaceaction = get_status($player, "replace$shortaction") || $shortaction;
				foreach my $subaction (split /\s*[?\\]\s*/, $replaceaction)
				{
					$subaction =~ /^(\S+)/;
					if ($action_config{$1}{is_kill})
					{
						$killers++;
						next player;
					}
				}
			}
			my $auto = get_status($player, 'auto');
			next unless $auto && $action_config{$auto};
			if ($action_config{$auto}{is_kill})
			{
				$killers++;
				next player;
			}
		}
	}
	
	return $killers;
}

sub check_winners {
	my @winners;
	my $end_game = 0;

	if (scalar(@alive) > 0) {
		# Don't handle winning if any 'ghost' actions are pending
		foreach my $player (@players) {
			return if !alive($player) && get_status($player, 'ghostaction');
		}
	}
	
	my $num_nonteam = 0;
	foreach my $group (sort keys %group_data)
	{
		next unless $group_data{$group}{alive};
		my $group_short = $group;
		$group_short =~ s/\d+$//;
		$num_nonteam += $group_data{$group}{alive} if $group_config{$group_short}{nonteam};
	}
	
	foreach my $group (sort keys %group_data)
	{
		if ($group_data{$group}{won})
		{
			push @winners, $group;
			next;
		}
		
		next unless $group_data{$group}{alive};
		
		my $num_team = $group_data{$group}{alive};
		my $num_poisoned = poisoned_team_members($group);
		my $num_killers = nonaligned_killers($group) + $num_poisoned;
		my $num_alive = scalar(@alive);
		my $groupshort;
		($groupshort = $group) =~ s/\d+$//;
		
		next if $num_poisoned >= $group_data{$group}{alive};
		
		if ($groupshort eq 'town' && $num_team + $num_nonteam == $num_alive)
		{
			push @winners, $group;
			$end_game = 1;
		}
		if (($groupshort eq 'mafia' || $groupshort eq 'sk' || $groupshort eq 'cult' || $groupshort eq 'wolf') && ($num_team * 2 >= $num_alive || $num_team + $num_nonteam == $num_alive) && $num_killers == 0)
		{
			push @winners, $group;
			$end_game = 1;
		}
		if ($groupshort eq 'survivor')
		{
			push @winners, $group;
			$end_game = 1 if $num_nonteam == $num_alive;
		}
		if ($groupshort eq 'lyncher')
		{
			$end_game = 1 if $num_alive < 3;
		}
		
		# Groups for faction mafia
		if ($groupshort eq 'townspeople' && $group_data{fanatics}{alive} == 0)
		{
			push @winners, $group;
			$end_game = 1;
		}
		if ($groupshort eq 'fanatics' && $group_data{townspeople}{alive} == 0)
		{
			push @winners, $group;
			$end_game = 1;
		}
		if ($groupshort eq 'merchant' && $group_data{townspeople}{alive} <= 1 && $group_data{fanatics}{alive} <= 1)
		{
			push @winners, $group;
			$end_game = 1;
		}
		if ($groupshort eq 'grimreaper' && $group_data{townspeople}{alive} <= 1 && $group_data{fanatics}{alive} <= 1 && $group_data{merchant}{alive} == 0)
		{
			push @winners, $group;
			$end_game = 1;
		}
	}
	
	my @allies = ();
	foreach my $group (@winners)
	{
		my $basegroup = $group;
		$basegroup =~ s/\d+$//;
		if ($group_data{"$basegroup-ally"}{members} && @{$group_data{"$basegroup-ally"}{members}})
		{
			push @allies, "$basegroup-ally";
		}
	}
	@winners = (@winners, @allies);
	
	if ($end_game or scalar(@alive) <= 1)
	{
		game_over(@winners);
	}
}

sub vote_count {
	return unless $phase eq 'day';
	
	$last_votecount_time = time;
	unschedule(\$votetimer);
	schedule(\$votetimer, $config{votecount_time}, \&vote_reminder) unless $just_testing;
	
	my $players_voting = 0;

	my $total_damage = 0;

	foreach my $player (@players) {
		$total_damage += (get_status($player, "damage") || 0);
	}
	
	if (get_total_votes() > 0)
	{
		announce "VOTE COUNT ($lynch_votes to lynch)";
	}
	elsif ($total_damage > 0 || @items_on_ground)
	{
		announce "DAMAGE COUNT";
	}
	else
	{
		return;
	}
	
	foreach my $player ("nolynch", @alive)
	{
		next unless $player_data{$player}{voted_by} || get_status($player, "damage");
		
		my @voters = @{$player_data{$player}{voted_by} || []};
		my $votes = scalar(@voters);
		my $damage = get_status($player, "damage") || 0;

		next unless $votes || $damage;
		
		my $announcement;
		$announcement = ($player ne "nolynch" ? $player : "No Lynch");
		if ($votes > 0)
		{
			$players_voting++;
	
			$announcement .= " - $votes (@voters)";
			$announcement .= "; $damage damage" if $damage > 0;
		}
		elsif ($damage > 0)
		{
			$announcement .= " - $damage damage";
		}
		announce $announcement;
	}
	
	if (!$players_voting && $total_damage == 0)
	{
		announce "No one is currently voting.";
	}

	if (@items_on_ground) {
		my @items = map { my ($i, undef) = split /;/, $_, 2; $role_config{$i}{item_name} } @items_on_ground;
		announce "ON GROUND - " . join(", ", @items);
	}
}

sub do_lynch {
	vote_count();
	
	my $lynches = 0;
	my @tokill;
	
	my %killer;
	
	foreach my $player (@alive)
	{
		next unless $player_data{$player}{voted_by};
		
		my @voters = @{$player_data{$player}{voted_by}};
		next unless scalar(@voters) >= $lynch_votes;

		my $onlynch = get_status($player, 'onlynch');

		my $msg = $messages{lynch}{lynched};
		$msg =~ s/#PLAYER1/$player/;
		announce $msg;
		
		push @tokill, $player;
		$killer{$player} = $voters[$#voters];
		$lynches++;
		
		increase_safe_status($player, 'statslynched', 1);
		increase_safe_status($voters[$#voters], 'statshammers', 1);
		increase_safe_status($voters[0], 'statswagonstarts', 1);
		foreach my $voter (@voters)
		{
			increase_safe_status($voter, 'statsbandwagons', 1);
		}
				
		if ($onlynch)
		{
			if ($onlynch eq 'supersaint')
			{
				# Get the last voter
				my $killer = $voters[$#voters];
				
				my $msg = $messages{lynch}{supersaint};
				$msg =~ s/#PLAYER1/$player/;
				$msg =~ s/#PLAYER2/$killer/;
				
				announce $msg;
				
				kill_player($killer);
			}
			elsif ($onlynch eq 'transform')
			{
				increase_temp_status($player, "revive", "transform");
			}
			elsif ($onlynch =~ /^transform:(.*)$/)
			{
				increase_temp_status($player, "revive", "transform:$1");
			}
			elsif ($onlynch eq 'revive')
			{
				increase_temp_status($player, "revive", '*');
			}
			elsif ($onlynch eq 'action')
			{
				$lynching = 1;
				do_auto_action($player, "", "", "noblock", undef, $voters[$#voters]);
				$lynching = 0;
			}
			elsif ($onlynch =~ /^action:(.*)$/)
			{
				$lynching = 1;
				do_auto_action($player, $1, "", "noblock", undef, $voters[$#voters]);
				$lynching = 0;
			}
			elsif ($onlynch eq 'lyncherwins')
			{
				my $lyncher = get_status($player, 'lyncher');
				if ($group_data{$lyncher}{alive})
				{	
					game_over($lyncher);
					return;
				}
			}
			elsif ($onlynch eq 'lyncherwinssoft')
			{
				my $lyncher = get_status($player, 'lyncher');
				if ($group_data{$lyncher}{alive})
				{	
					$group_data{$lyncher}{won} = 1;
					foreach my $player2 (get_group_members($lyncher))
					{
						notice($player2, "You win! However, the game will keep going until the remaining players have won or lost.");
						announce "$player2 has won the game.";
						reduce_status($player2, 'revive', '*');
						kill_player($player2);
						set_status($player2, 'immuneresurrect');
					}
				}
			}
			elsif ($onlynch eq 'win')
			{
				game_over(get_player_team($player));
				return;
			}
			elsif ($onlynch eq 'winsoft')
			{
				my $team = get_player_team($player);
				$group_data{$team}{won} = 1;
				foreach my $player2 (get_group_members($team))
				{
					notice($player2, "You win! However, the game will keep going until the remaining players have won or lost.");
					announce "$player2 has won the game.";
					reduce_status($player2, 'revive', '*');
					kill_player($player2);
					set_status($player2, 'immuneresurrect');
				}
			}
		}
	}
	
	foreach my $kill (@tokill)
	{
		kill_player($kill, $killer{$kill});
	}
	
	if (!$lynches)
	{
		announce $messages{lynch}{nolynch};
	}
	
	flush_message_queue();
	check_winners();
	update_voiced_players();
	return unless $game_active;
	next_phase();
}

sub load_config_file {
	my ($file, $hash, $extra_hash) = @_;
	my $line;
	my $section;
	my $extra = "";
	
	open FILE, "<", $file;
	
	::bot_log "Loading mafia config from $file\n";
	
	%$hash = ();
	%$extra_hash = () if $extra_hash;
	
	while (defined($line = <FILE>))
	{
		# Get rid of trailing whitespace 
		$line =~ s/\s*$//;
		
		if ($extra_hash && $line =~ /^;;;\s*(\S+):\s*(.*)$/)
		{
			my $key = $1;
			my $value = $2;
			
			$extra_hash->{$section}{$key} = $value;
			next;
		}
		
		# Remove comments
		next if $line =~ /^\s*;/;
		
		if ($line =~ /^\s*\[(.*?)\]\s*$/)
		{
			$section = $1;
			next;
		}
		
		if ($line =~ /^\s*([^=\s]+)\s*=\s*(.*)$/)
		{
			my $key = $1;
			my $value = $2;
			
			$hash->{$section}{$key} = $value;
		}
	}
	
	close FILE;
}

sub role_fancy_name {
	my $role = shift;
	my $role_name = role_name($role, 0);
	my $role_truename = role_name($role, 1);
	if ($role_truename && $role_truename ne $role_name)
	{
		my $qualifier = $role_truename;
		$qualifier =~ s/(?:Mystery|Secret)\s+//;
		$qualifier =~ s/\s+$role_name|$role_name\s*//;
		return $role_name . ' (' . $qualifier . ')';
	}
	else
	{
		return $role_name;
	}
}

sub valid_template {
	my $template = shift;
	my $base_role = shift;

	# Verify that this template can be used
	my $minactions = $role_config{$template}{template_minactions};
	my $maxactions = $role_config{$template}{template_maxactions};
	my $requireactions = $role_config{$template}{template_requireactions};
	my $forbidstatus = $role_config{$template}{template_forbidstatus};
	my $ignoregroup = $role_config{$template}{template_ignoregroupactions};

	my $expandedrole = expand_setuprole($base_role);
	my $roleactions = scalar(@{$expandedrole->{actions}});

	my @actions = @{$expandedrole->{actions}};
	my $backupactions = $expandedrole->{status}{backupactions};
	push @actions, split(',', $backupactions) if $backupactions;
	my $groupactions = $expandedrole->{status}{groupactions};
	push @actions, split(',', $groupactions) if $groupactions && !$ignoregroup;

	my @templateactions = @{ $role_config{$template}{actions} || [] };
	my $templatebackupactions = $role_config{$template}{status}{backupactions};
	push @templateactions, split(',', $templatebackupactions) if $templatebackupactions;
	my $templategroupactions = $role_config{$template}{status}{groupactions};
	push @templateactions, split(',', $templategroupactions) if $templategroupactions;

	return 0 unless $base_role;

	return 0 unless !defined($minactions) || scalar(@actions) >= $minactions;
	return 0 unless !defined($maxactions) || $roleactions <= $maxactions;

	return 1 if $role_config{$template}{template_forcevalid};

	if (defined($requireactions))
	{
		foreach my $action (split /,/, $requireactions)
		{
			return 0 unless grep { action_base($_) eq $action } @actions;
		}
	}

	if (defined($forbidstatus))
	{
		foreach my $status (split /,/, $forbidstatus)
		{
			return 0 if $expandedrole->{status}{$status};
		}
	}

	return 0 if $role_config{$template}{template_nobastard} && role_name($base_role, 0) ne role_name($base_role, 1);

	if (!$role_config{$template}{replaceactions})
	{
		foreach my $action1 (@templateactions)
		{
			foreach my $action2 (@actions)
			{
				# Don't allow to add an action the role already has, even for nontemplates
				return 0 if action_base($action1) eq action_base($action2);

				# Don't combine day actions and other actions - mostly a problem with kills, but easier to stop them all
				if ($action1 !~ /^auto|;1/ && $action2 !~ /^auto|;1/)
				{
					return 0 if $action1 =~ /^day/ && $action2 !~ /^day/;
					return 0 if $action1 !~ /^day/ && $action2 =~ /^day/;
				}
			}
		}
	}

	if ($role_config{$template}{template_nodayactions})
	{
		foreach my $action (@{ $expandedrole->{actions} })
		{
			return 0 if $action =~ /^day|^auto|^x/;
		}
	}

	if ($role_config{$template}{template_nokills})
	{
		foreach my $action (@{ $expandedrole->{actions} })
		{
			my $shortaction = action_base($action);
			my $replaceaction = $expandedrole->{status}{"replace$shortaction"} || $shortaction;
			foreach my $subaction (split /\s*[?\\]\s*/, $replaceaction)
			{
				$subaction =~ /^(\S+)/;
				return 0 if $action_config{$1}{is_kill};
			}
		}
	}

	return 1;
}

sub is_basic_role {
	my $testrole = shift;
	if ($role_config{$testrole}{setup} && !$role_config{$testrole}{theme})
	{
		return 1;
	}
	return 0;
}

sub is_real_role {
	my ($testrole, $namedonly) = @_;
	return 1 if $role_config{$testrole}{name};
	return 1 if $role_config{$testrole}{truename};
	return 1 if $role_config{$testrole}{setup} && !$namedonly;
	return 0;
}

sub lookup_role {
	my $rolename = shift;
	my $allow_double_role = 1;
	my $maxtime = shift || 0;

	die "Time limit exceeded for role lookup" if $maxtime && time > $maxtime;
	#::bot_log "TEST: lookup_role '$rolename', $maxtime (time=" . time . ")\n";
	
	# If it's an exact rolename, use it
	if (is_real_role(lc $rolename))
	{
		return lc $rolename;
	}

	# If it's a template role, try it
	if ($rolename =~ /^(.+)\+([^+]+)$/ && ($role_config{lc $2}{template} || $allow_double_role))
	{
		my $base = $1;
		my $template = lc $2;
		my $base_role = lookup_role($base, $maxtime);

		if (is_real_role($template) || $role_config{$template}{template})
		{
			my $valid_form = canonicalize_role("$base_role+$template", 1);
			my $unchecked_form = canonicalize_role("$base_role+$template", 0);
			return $valid_form if $valid_form eq $unchecked_form;
		}
	}
	
	# If it's a normal game role, use it
	foreach my $testrole (sort keys %role_config)
	{
		if (is_basic_role($testrole) && 
		    lc $rolename eq lc ($role_config{$testrole}{truename} || $role_config{$testrole}{name}))
		{
			return $testrole;
		}
	}
	
	# If it's an unusual role, use it
	foreach my $testrole (sort keys %role_config)
	{
		next if $role_config{$testrole}{template};
		if (lc $rolename eq lc ($role_config{$testrole}{truename} || $role_config{$testrole}{name}))
		{
			return $testrole;
		}
	}

	# If it's an item, use it (!)
	foreach my $testrole (sort keys %role_config)
	{
		next unless $role_config{$testrole}{item};
		if (lc $rolename eq lc $role_config{$testrole}{item_name})
		{
			return $testrole;
		}
	}
	
	# Check for templates
	foreach my $testrole (sort keys %role_config)
	{
		next unless $role_config{$testrole}{template} || ($allow_double_role && is_basic_role($testrole));
		my $pattern = role_name($testrole, 1);
		if ($role_config{$testrole}{template})
		{
			$pattern = quotemeta($role_config{$testrole}{truename} || $role_config{$testrole}{name} || "");

			next unless $pattern;
			next if $pattern eq '\\#NAME';

			# Replace the first occurrence of #NAME
			$pattern =~ s/\\#NAME/(.*)/;
			# Replace remaining occurrences of #NAME
			$pattern =~ s/\\#NAME/\\1/g;
		}
		else
		{
			$pattern = "$pattern (.*)";
		}
		
		# Check for pattern
		if ($rolename =~ /^$pattern$/i)
		{
			my $baserolename = $1;
			my $baserole = lookup_role($baserolename, $maxtime);
			next unless defined($baserole);

			die "Time limit exceeded for role lookup" if $maxtime && time > $maxtime;

			my $valid_form = canonicalize_role("$baserole+$testrole", 1);
			my $unchecked_form = canonicalize_role("$baserole+$testrole", 0);
			return $valid_form if $valid_form eq $unchecked_form;
		}
	}
	
	# Couldn't find it
	return undef;
}

sub nth {
	my $i = shift;
	
	return "${i}th" if $i >= 11 && $i <= 13;
	return "${i}st" if $i % 10 == 1;
	return "${i}nd" if $i % 10 == 2;
	return "${i}rd" if $i % 10 == 3;
	return "${i}th";
}

sub setrole {
	my ($connecstion, $command, $forum, $from, $to, $args) = @_;
	
	my $player = (split /!/, $from)[0];

	return 0 unless $players{$player};

	if ($phase ne 'setup' || !setup_rule('upick', $cur_setup))
	{
		notice($player, "You can only use this command during the setup of a upick game.");
		return 1;
	}

	if (length($args) > 40)
	{
		notice($player, "That name is too long, try something shorter.");
		return 1;
	}
	
	my $oldrolename = $player_data{$player}{safe}{status}{rolename};
	$player_data{$player}{safe}{status}{rolename} = $args;
	
	my $unassigned_players = 0;
	foreach my $play (@players)
	{
		$unassigned_players++ unless $player_data{$play}{safe}{status}{rolename};
	}
	
	mod_notice("$player ($player_data{$player}{team}) has requested role '$args'.");
	mod_notice("All players have now submitted role requests. Use 'baserole', 'addability', 'addstatus', and 'setdesc' to create roles, then 'begin' to start the game.") unless $unassigned_players;
	
	notice($player, "You have requested the role '$args'.");
	return 1;
}

sub redirect_action {
	my ($item, $target, $newtarget) = @_;

	return if $item->{type} =~ /\bnoblock\b|\blocked\b/;
	my $oldtarget = $item->{target} || $item->{targets}[0] || $target;
	if ($item->{player} eq $target)
	{
		$item->{targets}[0] = $newtarget if $item->{targets}[0] eq $oldtarget;
		$item->{target} = $newtarget if $item->{target} eq $oldtarget;
		::bot_log("REDIRECT $item->{player} $item->{action} $oldtarget -> $newtarget\n");
		mod_notice("$item->{player}'s $item->{action} was redirected from $oldtarget to $newtarget") if $oldtarget ne $newtarget;
	}
}

sub randomize_action {
	my ($item, $target, $newtargets) = @_;

	$newtargets = [] unless $newtargets;

	return if $item->{type} =~ /\bnoblock\b|\blocked\b/;

	my %newtargets = split /,/, get_status($target, 'randomizedto');

	if ($item->{player} eq $target && !$item->{randomized})
	{
		my $oldtarget = $item->{target} || $item->{targets}[0] || $target;
		my $newtarget = $newtargets{$oldtarget} || shift(@$newtargets) || $alive[rand @alive];
		$newtargets{$oldtarget} = $newtarget;
		$item->{targets}[0] = $newtarget if $item->{targets}[0] eq $oldtarget;
		$item->{target} = $newtarget if $item->{target} eq $oldtarget;
		$item->{randomized} = 1;

		::bot_log("RANDOMIZE $item->{player} $item->{action} $oldtarget -> $newtarget\n");
		mod_notice("$item->{player}'s $item->{action} was randomized from $oldtarget to $newtarget") if $oldtarget ne $newtarget;
	}

	set_temp_status($target, 'randomizedto', join(',', %newtargets));
}

sub enqueue_action {
	my ($player, $group, $action, $longaction, $xtype, $special, @targets) = @_;
	
	my $target = @targets ? $targets[0] : "";
	
	$action = get_status($player, "replace$action") || $action;
	my $firsttarget = 1;
	
	my $type = $action_config{$action}{type} || "";
	
	my $alias = $action;
	while ($action_config{$alias} && $action_config{$alias}{alias})
	{
		$alias = $action_config{$alias}{alias};
		$type = $action_config{$alias}{type} || "" if !$type && $action_config{$alias};
		#::bot_log "$action = $alias [$type]\n";
	}

	::bot_log "ENQUEUE $player ($group) $action [$xtype] @targets\n";
	
	foreach my $alltarget (($alias =~ /\#\*|\#t|\#m/i) ? @alive : "")
	{
		next if $alltarget eq $player;
		
		my @alts = split /\s+\?\s*/, $alias;
		my $alt = $alts[rand @alts];			
		my @subactions = split /\s*\\\s*/, $alt;
		
		subaction: foreach my $subaction (@subactions)
		{
			next subaction unless $firsttarget || $subaction =~ /\#\*|\#t|\#m/i;

			# mod_notice("Processing subaction '$subaction' of '$action' ($longaction)");
			
			if ($action_config{$subaction}{alias}) {
				my @alts = split /\s*(?<!#)\?\s*/, $action_config{$subaction}{alias};
				my $alt = $alts[rand @alts];			
				push @subactions, split /\s*\\\s*/, $alt;
				next subaction;
			}
			
			my ($act, @targetspec) = split /\s+/, $subaction;
			my @realtargets;
			my $selftarget = 0;

			my $numtargets = scalar(@{$action_config{$act}{targets} || []});

			@targetspec = map { "#" . $_ } 1..scalar(@targets) if @targets && !@targetspec;
			
			while (@targetspec < $numtargets)
			{
				my $default = get_status($player, "default") || '#?';
				::bot_log "DEFAULT to $default (no targets)\n";
				push @targetspec, $default;
			}
			
			if (@targetspec)
			{
				my @commandtargets = @{ get_status($player, 'targets') || [] };

				# Target specifier
				#  #1, #2, etc. = 1st argument, 2nd argument, etc.
				#  #S = self
				#  #B = buddy
				#  #? = random target other than the player
				#  #* = all living targets except the player (action is duplicated)
				#  #T = all living targets on the player's team except the player (action is duplicated)
				foreach my $t (@targetspec)
				{
					$t = lc $t;
					# Hack - if the target doesn't exist, use default
					if ($t =~ /^\#(\d)$/ && $1 > $#targets + 1)
					{
						my $default = get_status($player, "default") || '#?';
						::bot_log "DEFAULT to $default (bad target '$t')\n";
						$t = $default;
					}

					if ($t =~ /^\#s/i)
					{
						push @realtargets, $player;
						$selftarget = 1;
					}
					elsif ($t =~ /^\#b/i)
					{
						# ::bot_log "BUDDY $player $player_data{$player}{buddy}\n";
						push @realtargets, $player_data{$player}{buddy};
					}
					elsif ($t =~ /^\#r(\d)$/i)
					{
						next subaction unless scalar(@commandtargets) >= $1;
						push @realtargets, $commandtargets[$1 - 1];
					}
					elsif ($t =~ /^\#(\d)$/)
					{
						push @realtargets, $targets[$1 - 1];
					}
					elsif ($t eq '#?' || $t eq '#?m' || $t eq '#?t')
					{
						my $targetrestrict = $action_config{$act}{targets}[@realtargets];

						my @posstargets = grep { $_ ne $player } @players;
						@posstargets = grep { alive($_) } @posstargets if $targetrestrict =~ /\balive\b/;
						@posstargets = grep { !alive($_) } @posstargets if $targetrestrict =~ /\bdead\b/;
						@posstargets = grep { get_status($_, "marked:$player") || get_status($_, "markedfor:$act") } @posstargets if $t =~ /m/;
						@posstargets = grep { get_team($_) eq get_team($player) } @posstargets if $t =~ /t/;
						# mod_notice("Possible targets for ${player}'s $act: @posstargets");
						for my $prevtarget (@realtargets)
						{
							@posstargets = grep { $_ ne $prevtarget } @posstargets;
						}
						shuffle_list(\@posstargets);
						
						push @realtargets, (shift(@posstargets) || "none");
					}
					elsif ($t eq '#*')
					{
						push @realtargets, $alltarget;
					}
					elsif ($t =~ /^\#t/i)
					{
						next subaction unless get_player_team($alltarget) eq get_player_team($player);
						push @realtargets, $alltarget;
					}
					elsif ($t eq '#m')
					{
						next subaction unless get_status($alltarget, "marked:$player") || get_status($alltarget, "markedfor:$act");
						push @realtargets, $alltarget;
					}
					elsif ($players{$t})
					{
						push @realtargets, $t;
					}
					else
					{
						die "Bad target spec $t for action $action\n";
					}
				}
			}
			else
			{
				@realtargets = @targets;
			}
			
			my $status = ($action_config{$act}{status} ? get_status($player, $action_config{$act}{status}) : "");
			$status = $special if !$status && defined($special);
			
			my $subtype = $type || $action_config{$act}{type} || "nonkill";
			$subtype = "$subtype;notrigger,locked,noimmune" if $selftarget;
			
			::bot_log "  * $player $act" . ($status && length($status) <= 15 ? " ($status)" : "") . " [$subtype] @realtargets\n";
			
			next if $act eq 'none';
			next if grep { $_ eq 'none' } @realtargets;

			if ($action_config{$act}{alias}) {
				# Yikes! The subaction is another alias! Recurse.
				enqueue_action($player, $group, $act, $longaction, ($xtype ? "$subtype;$xtype" : $subtype), $special, @realtargets);
				next;
			}
			
			my $target2 = $target;
			$target2 = $realtargets[0] if $subtype =~ /\bmultitarget\b/;
			
			my $item = { player => $player, action => $act, longaction => $longaction, group => $group, targets => [@realtargets], target => $target2,
				status => $status, type => ($xtype ? "$subtype;$xtype" : $subtype) };

			randomize_action($item, $player) if get_status($player, 'randomized');
			my $redirect = get_status($player, 'redirected');
			$redirect = get_status($player, 'killredirected') || $redirect if $action_config{$act}{iskill};
			redirect_action($item, $player, $redirect) if $redirect;

			push @action_queue, $item;
		}
		
		$firsttarget = 0;
	}
}

sub enqueue_rapid_action {
	my ($player, $group, $action, $longaction, $xtype, $time, @targets) = @_;

	my @old_action_queue = @action_queue;
	@action_queue = ();
	enqueue_action($player, $group, $action, $longaction, $xtype, undef, @targets);
	resolve_actions();
	@action_queue = @old_action_queue;
	return unless $game_active;
	check_actions() if $phase eq 'night';
}

sub enqueue_action_timed {
	my ($player, $group, $action, $longaction, $xtype, $time, @targets) = @_;
	
	push @timed_action_timers, { timer => undef, player => $player, action => $action, targets => [@targets] };
	my $timerref = \$timed_action_timers[$#timed_action_timers]{timer};
	
	my $actsub = sub {
		enqueue_rapid_action($player, $group, $action, $longaction, $xtype, undef, @targets);
	};
	
	schedule($timerref, $time, $actsub);
}

sub drop_item {
	my ($player, $item_template, $death) = @_;

	$death = 0 unless $death;

	my $player_role = get_player_role($player);
	my @player_role_parts = split /\+/, recursive_expand_role($player_role);
	if (!grep { $_ eq $item_template } @player_role_parts) {
		return 0;
	}
	if (!$role_config{$item_template}{item}) {
		return 0;
	}

	my $name = $role_config{$item_template}{item_name};

	@player_role_parts = grep { $_ ne $item_template } @player_role_parts;
	my $charges = 1;

	my $chargestatus = $role_config{$item_template}{item_chargestatus};
	if ($chargestatus)
	{
		$charges = get_status($player, $chargestatus) || 0;
	}

	$charges = 0 if $death && $role_config{$item_template}{item_nodeathdrop};

	handle_trigger($player, get_status($player, "ondrop"));
	handle_trigger($player, get_status($player, "ondrop:$item_template"));

	transform_player($player, join('+', @player_role_parts));

	if ($charges > 0 || $role_config{$item_template}{item_nevervanish}) {
		push @items_on_ground, "$item_template;$charges";
		announce "$player dropped a $name.";
	}
	else {
		announce "$player dropped a spent $name.";
	}

	return 1;
}

sub take_item {
	my ($player, $item_template, $charges) = @_;

	my $name = $role_config{$item_template}{item_name};

	my $player_role = get_player_role($player);
	my @player_role_parts = split /\+/, recursive_expand_role($player_role);
	if (grep { $_ eq $item_template } @player_role_parts) {
		notice($player, "You already have a $name.");
		return 0;
	}
	if (!valid_template($item_template, $player_role)) {
		notice($player, "You can't take the $name.");
		return 0;
	}

	transform_player($player, canonicalize_role("$player_role+$item_template", 0));

	my $chargestatus = $role_config{$item_template}{item_chargestatus};
	if ($chargestatus)
	{
		set_status($player, $chargestatus, $charges);
	}

	announce "$player took the $name.";
	if (alive($player)) {
		send_help($player, 0);
	}

	return 1;
}

sub item_cost {
	my ($item_template) = @_;

	my $power = estimate_template_power($item_template);
	$power = 0 if $power < 0;
	my $cost = 100 + int(800 * $power + 0.5);
}

sub buy_item {
	my ($player, $item_template) = @_;

	my $name = $role_config{$item_template}{item_name};
	my $cost = item_cost($item_template);
	my $credits = get_status($player, "credits");

	my $player_role = get_player_role($player);
	my @player_role_parts = split /\+/, recursive_expand_role($player_role);
	if (grep { $_ eq $item_template } @player_role_parts) {
		notice($player, "You already have a $name.");
		return 0;
	}
	if (!valid_template($item_template, $player_role)) {
		notice($player, "You can't buy a $name.");
		return 0;
	}
	if ($cost > $credits) {
		notice($player, "A $name costs $cost credits but you only have $credits credits left.");
		return 0;
	}

	reduce_status($player, "credits", $cost);
	transform_player($player, canonicalize_role("$player_role+$item_template", 0));
	
	$credits = get_status($player, "credits");
	
	if (alive($player)) {
		notice($player, "You bought a $name for $cost credits. You have $credits credits left.");
		send_help($player, 0);
	}

	return 1;
}

sub apply_damage {
	my ($player, $damage, $source) = @_;

	increase_safe_status($player, "damage", $damage);

	if (get_status($player, "damage") >= (get_status($player, "hp") || 100))
	{
		my $msg = $messages{death}{killed} . '.';
		$msg =~ s/#PLAYER1/$player/;
		$msg =~ s/#TEXT1//;
		announce $msg;
		kill_player($player, $source);
	}
	elsif ($damage > 0) 
	{
		handle_trigger($player, get_status($player, 'ondamage'));
	}
}

sub convert_bestplayers_to_mafia_setup {
	my ($filename) = @_;

	foreach my $role (keys %role_config)
	{
		next unless $role =~ /^theme_mafia_/;
		delete $role_config{$role};
	}

	open FILE, "<", $filename;

	my %playernames;

	while (my $line = <FILE>)
	{
		chomp $line;
		my ($setup, $player, $rank, $score, $win, $loss, $draw, $adv, $role) = split /\s+/, $line;

		next if $role =~ /\+/;

		foreach my $pair (['m', 'mafia'], ['t', 'town'], ['sk', 'sk'], ['sv', 'survivor'], ['cult1', 'cult'])
		{
			$playernames{$pair->[0]} = $player if $setup eq $pair->[1] && !$playernames{$pair->[0]};
		}

		$playernames{$role} = $player if $role_config{$role}{setup} && !$playernames{$role};
	}

	foreach my $baserole (keys %playernames)
	{
		my $role = "theme_mafia_$baserole";

		$role_config{$role} = { %{ $role_config{$baserole} } };
		$role_config{$role}{name} = $playernames{$baserole};
		$role_config{$role}{truename} = role_name($baserole, 1);
		$role_config{$role}{alias} = $baserole;
		delete $role_config{$role}{actions};
		delete $role_config{$role}{status};
		$role_config{$role}{theme} = "mafiaplayers";
		$role_config{$role}{nonadaptive} = 1;
		$role_config{$role}{rarity} = 1;
		$role_config{$role}{secret} = 1;
		# foreach my $setting (qw[setup power]) {
		#	$role_config{$role}{$setting} = $role_config{$baserole}{$setting};
		# }
	}

	close FILE;
}
	
sub convert_fadeblue_roles {
	my $spec = shift;
	my $themex = shift || "";
	my ($startphase, $roles) = split /\\/, $spec, 2;
	
	my @outroles;
	
	$roles =~ s/\\\s*$//;
	
	my @teamspecs = split /\s+/, $roles;
	foreach my $teamspec (@teamspecs)
	{
		my ($team, $roles) = split /;/, $teamspec, 2;
		my @roles = split /,/, $roles;
		
		foreach my $role (@roles)
		{
			push @outroles, "$themex$role/$team";
		}
	}
	
	$startphase = 'night,nokill' if $startphase eq 'nokill';
	
	#::bot_log "IMPORTSETUP $startphase @outroles\n";
	return ($startphase, [@outroles]);
}

# Load a setup.ini from fadeblue's script.
sub import_fadeblue_setups {
	my $file = shift || "mafia/setup.ini";
	my $theme = shift || "normal";
	
	my $themex = ($theme eq 'normal' ? "" : "theme_${theme}_");
	
	my (%setup, %setup_extra);
	load_config_file($file, \%setup, \%setup_extra);

	# Get roles
	foreach my $rolebase (keys %{$setup{roles}})
	{
		my $role = $themex . $rolebase;

		# Skip roles that already exist
		next if exists $role_config{$role} && ($role_config{$role}{name} || $role_config{$role}{alias});

		#::bot_log "IMPORTROLE $role\n";
		
		$role_config{$role}{imported} = 1;
		
		my ($name, $actions, $status, $desc) = split /\\/, $setup{roles}{$role}, 4;
		
		# Name
		my ($displayname, $truename) = split /;/, $name, 2;
		$role_config{$role}{name} = $displayname;
		$role_config{$role}{truename} = $truename if $truename;
		
		# Actions
		$role_config{$role}{actions} = ($actions eq '.' ? [] : [split /\s+/, $actions]);
		
		# Status
		if ($status ne '.')
		{
			$role_config{$role}{status} = {};
			foreach my $item (split /\s+/, $status)
			{
				my ($status, $value) = split /;/, $item, 2;

				$value = '*' if !defined($value);
				$value =~ s/_/ /g;
				
				# Fadeblue's bot does 'failure' backwards
				$value = 100 - $value if $status eq 'failure';
				
				$role_config{$role}{status}{$status} = $value;
			}
			
			$role_config{$role}{groups} = [ split /,/, $role_config{$role}{status}{xgroup} ] if $role_config{$role}{status}{xgroup};
			delete $role_config{$role}{status}{xgroup};
		}
		
		# Description
		$role_config{$role}{roletext} = ($desc eq '.' ? "" : $desc);
			
		# Extra
		if ($setup_extra{roles}{$role})
		{
			my $extra = $setup_extra{roles}{$role};
#			my @teams;
			
			$extra =~ s/^".*";\s*//;
			foreach my $item (split /,\s+/, $extra)
			{
				my ($key, $value) = split /\s+/, $item, 2;
#				push(@teams, $value), next if $key eq 'team';
				$role_config{$role}{$key} = $value;
			}
			
#			$role_config{$role}{setup} = join(',', @teams);
		}
		
		# Theme
		$role_config{$role}{theme} = $theme;
	}

	# Get actions
	foreach my $action (keys %{$setup{actions}})
	{
		# Skip actions that already exist
		next if exists $action_config{$action};
		
		# Skip _order and _kill
		next if $action =~ /^_/;
		
		$action_config{$action}{imported} = 1;
		
		my $alias = $setup{actions}{$action};
		$action_config{$action}{alias} = $alias;
		
		my @targets = ();
		$action_config{$action}{is_kill} = 0;
		
		foreach my $targetspec (split /\s+(?:\\|\?)\s+/, $alias)
		{
			my ($action1, @specs) = split /\s+/, $targetspec;
			next unless exists $action_config{$action1};
			
			my @basetargets = @{$action_config{$action1}{targets}};
	
			$action_config{$action}{is_kill} = 1 if $action_config{$action1}{is_kill};
			
			if (@specs)
			{
				for (my $i = 1; $i <= scalar(@specs); $i++)
				{
					$targets[$1] = $basetargets[$i] if $specs[$i] =~ /^#(\d+)$/;
				}
			}
			else
			{
				for (my $i = 1; $i < scalar(@basetargets); $i++)
				{
					$targets[$i] = $basetargets[$i];
				}
			}
		}
		
		$action_config{$action}{targets} = [@targets];
		
		# ::bot_log "IMPORTACTION $action alias = \"$alias\", targets = [@targets], is_kill = $action_config{$action}{is_kill}\n";
	}

	# Get setups
	for (my $numplayers = 3; exists $setup{"${numplayers}p"}; $numplayers++)
	{
		my $specialsetup = ($theme eq 'normal' ? 'fadebot' : $theme);
		my $subsetup = $setup{"${numplayers}p"};
		my $numalts = $subsetup->{setups};
		
		$setup_config{$specialsetup}{"numalts${numplayers}"} = $numalts;
		
		for (my $i = 1; $i <= $numalts; $i++)
		{
			my ($startphase, $roles) = convert_fadeblue_roles($subsetup->{"s${i}"}, $themex);
			$setup_config{$specialsetup}{"roles${numplayers}_${i}"} = $roles;
			$setup_config{$specialsetup}{"start${numplayers}_${i}"} = $startphase;
		}
	}

	# Get special setups
	my @specialsetups = map { lc $_ } split /\s+/, $setup{special}{setups};
	foreach my $specialsetup (@specialsetups)
	{
		# Skip setups that already exist
		next if exists $setup_config{$specialsetup} && !$setup_config{$specialsetup}{fadebot};
		
		$setup_config{$specialsetup}{imported} = 1;
		
		my $subsetup = $setup{$specialsetup};
		my $numalts = $subsetup->{setups};
		
		my $numplayers = $subsetup->{players};
		$setup_config{$specialsetup}{players} = $numplayers;
		
		$setup_config{$specialsetup}{"numalts${numplayers}"} = $numalts;
		
		for (my $i = 1; $i <= $numalts; $i++)
		{
			my ($startphase, $roles) = convert_fadeblue_roles($subsetup->{"s${i}"}, $themex);
			$setup_config{$specialsetup}{"roles${numplayers}_${i}"} = $roles;
			$setup_config{$specialsetup}{"start${numplayers}_${i}"} = $startphase;
		}
		
		$setup_config{$specialsetup}{shirts} = [ split /\s+/, $subsetup->{shirts} ] if $subsetup->{shirts};
	}
}

sub export_roles {
	my $filename = shift;
	
	open FILE, '>', $filename;
	
	print FILE "[roles]\n";

	my %roles_by_setupgroup;

	foreach my $role (sort keys %role_config)
	{
		next unless $role_config{$role}{setup} || $role_config{$role}{name};

		my $setupgroup = count_role_as($role);
		my $theme = $role_config{$role}{theme} || 'normal';

		$setupgroup = "$theme: $setupgroup" unless $theme =~ /\bnormal\b/;

		if ($role =~ /\*/) {
			::bot_log("ERROR role_config should not contain '$role'\n");
			next;
		}

		push @{$roles_by_setupgroup{$setupgroup}}, $role;
	}
	
	foreach my $setupgroup (sort keys %roles_by_setupgroup)
	{
		print FILE "; Group - $setupgroup\n";

		foreach my $role (@{$roles_by_setupgroup{$setupgroup}})
		{
			my $setuprole = { 
				role => $role,
				team => 'town',
				alive => 0,
			};
		
			my $expandedrole = expand_setuprole($setuprole);

			my %status = %{$expandedrole->{status}};
			my @groups = @{$expandedrole->{groups}};
			my @actions = @{$expandedrole->{actions}};
			my $team = $expandedrole->{team};

			my ($name, $truename, $actions, $status, $desc);
			my $q;
			
			$name = $status{rolename};
			$truename = $status{roletruename};
			$name .= ';' . $truename if $name ne $truename;
			
			$actions = @actions ? (join ' ', @actions) : '.';
			
			my @status = map {
				my $value = $status{$_};
				$value = 100 - $value if $_ eq 'failure';
				$q = ($value eq '*' ? $_ : "$_;$value"); 
				$q =~ s/ /_/g; 
				!$value || $_ =~ /^roletext$|^rolename$|^roletruename$/ ? () : $q 
			} sort keys %status;

			@groups = grep { $_ ne $team } @groups;
			push @status, "xgroup;" . join(',', @groups) if @groups;
			$status = join(' ', @status) || '.';
			
			$desc = $status{roletext} || '.';

			my @extra;
			if ($role_config{$role})
			{
				if ($role_config{$role}{alias})
				{
					push @extra, "alias $role_config{$role}{alias}";
				}
				foreach my $item (qw(power rarity countas changeto minplayers minteam minmafia minsk minscum minrole theme setup))
				{
					push @extra, "$item $role_config{$role}{$item}" if $role_config{$role}{$item};
				}
				push @extra, "imported" if $role_config{$role}{imported};
			}
			print FILE ";;; $role: \"$truename\"; ", join(', ', @extra), "\n";
			print FILE "$role=$name\\$actions\\$status\\$desc\n";
		}

		print FILE "\n";

	}
	
	print FILE "[actions]\n";
	my @actionorder = sort { $action_config{$a}{priority} <=> $action_config{$b}{priority} } grep { $action_config{$_}{priority} } keys %action_config;
	print FILE "_order=@actionorder\n";
	my @iskill = sort grep { $action_config{$_}{is_kill} } keys %action_config;
	print FILE "_kill=@iskill\n";
	print FILE "\n";
	
	foreach my $action (sort keys %action_config)
	{
		my $targets = join(' ', @{$action_config{$action}{targets} || []}) || "none";
		my $help = $action_config{$action}{help} ? "\"$action_config{$action}{help}\"" : "";
		print FILE ";;; $action: $targets; $help\n";
		print FILE "$action=$action_config{$action}{alias}\n" if $action_config{$action}{alias};
	}
	
	close FILE;
}

sub export_xml_action {
	my ($action, $acttype, $expandedrole, $statusused, $p) = @_;

	our %xml_effect_cache;

	$p = "" unless $p;

	my $shortaction = $action;
	my ($auto, $time) = (0, "night");
	my $uses = '*';
	$auto = 1 if $shortaction =~ s/^auto//;
	$time = $1 if $shortaction =~s/^(day|x)//;
	$uses = $1 if $shortaction =~ s/;(\d+)$//;
	$shortaction =~ s/ .*$//;
	my $targets = @{$action_config{$shortaction}{targets} || []};

	$acttype = "NightAutoAction" if $auto && $time eq 'night';
	$acttype = "DayAutoAction" if $auto && $time eq 'day';
	$acttype = "DayAndNightAutoAction" if $auto && $time eq 'x';

	my $failure = $expandedrole->{status}{"failure$shortaction"} || $expandedrole->{status}{failure} || 0;
	$statusused->{"failure$shortaction"} = 1;
	$statusused->{failure} = 1;

	if ($action_config{$shortaction}{targets} && !$expandedrole->{status}{dayaction} && !$expandedrole->{status}{timer} &&
		!$expandedrole->{status}{"replace$shortaction"} &&
		($acttype eq "Action" || $acttype eq "GroupAction" || $acttype eq "TeamGrantedAction"))
	{
		my $special = $action_config{$shortaction}{status};
		my $value = $expandedrole->{status}{$special} || "";
		
		if ($xml_effect_cache{$action}{$value})
		{
			$statusused->{$special} = 1 if $special;
			print FILE <<END;
$p	<$acttype reference="$xml_effect_cache{$action}{$value}">
END
			print FILE <<END if $failure;
$p		<FailurePercent value="$failure"/>
END
			print FILE <<END;
$p	</$acttype>
END
			return;
		}
		elsif ($xml_effect_cache{$shortaction}{$value})
		{
			$statusused->{$special} = 1 if $special;
			print FILE <<END;
$p	<$acttype reference="$xml_effect_cache{$shortaction}{$value}">
END
			print FILE <<END if $time eq 'day' && !$auto;
$p		<Day/>
END
			print FILE <<END if $time eq 'x' && !$auto;
$p		<DayOrNight/>
END
			print FILE <<END if $uses ne '*';
$p		<Uses value="$uses"/>
END
			print FILE <<END if $failure;
$p		<FailurePercent value="$failure"/>
END
			print FILE <<END;
$p	</$acttype>
END
			return;
		}
	}

	print FILE <<END;
$p	<$acttype name="$shortaction">
END

	print FILE <<END if $time eq 'day' && !$auto;
$p		<Day/>
END
	print FILE <<END if $time eq 'x' && !$auto;
$p		<DayOrNight/>
END

	if ($acttype =~ /Effect/)
	{
		# Do nothing
	}
	elsif (!$targets)
	{
		print FILE <<END;
$p		<Targets/>
END
	}
	else
	{
		print FILE <<END;
$p		<Targets>
END
		foreach my $target (@{$action_config{$shortaction}{targets}})
		{
			my $type = "Any";
			if ($target =~ /alive/ && $target =~ /nonself/)
			{
				$type = "Alive";
			}
			elsif ($target =~ /alive/)
			{
				$type = "AnyAlive";
			}
			elsif ($target =~ /dead/)
			{
				$type = "Dead";
			}

			if ($auto)
			{
				my $default = $expandedrole->{status}{default} || '#?';
				$statusused->{default} = 1;

				if ($default eq '#?')
				{
					$type = "Random";
				}
				elsif ($default =~ /#b/i)
				{
					$type = "Buddy";
				}
				elsif ($default =~ /#s/i)
				{
					$type = "Self";
				}
			}

			print FILE <<END;
$p			<Target$type/>
END
		}
		print FILE <<END;
$p		</Targets>
END
		if ($action_config{$shortaction}{targets}[0] =~ /unique/)
		{
			print FILE <<END;
$p		<UniqueTargets/>
END
		}
	}

	print FILE <<END if $uses ne '*';
$p		<Uses value="$uses"/>
END

	print FILE <<END if $failure;
$p		<FailurePercent value="$failure"/>
END

	if ($time eq 'day' && ($expandedrole->{status}{dayaction} || "") eq 'public')
	{
		$statusused->{dayaction} = 1;
		print FILE <<END;
$p		<AnnounceUse/>
END
	}

	if ($time eq 'day' && $expandedrole->{status}{timer})
	{
		$statusused->{timer} = 1;
		print FILE <<END;
$p		<Delay value="$expandedrole->{status}{timer}"/>
END
	}

	my $effect = $expandedrole->{status}{"replace$shortaction"} || $shortaction;
	$effect = $action if $action =~ / /;
	$effect = $action_config{$effect}{alias} || $effect;
	$statusused->{"replace$shortaction"} = 1;

	my @triggeredeffects;

	if ($acttype =~ /Effects$/)
	{
	}
	elsif ($effect =~ /\s\?/)
	{
		print FILE <<END;
$p		<RandomEffects>
END
	}
	else
	{
		print FILE <<END;
$p		<Effects>
END
	}

	foreach my $randomeffect (split /\s+\?\s+/, $effect)
	{
		my $oldp = $p;
		if ($effect =~ /\s\?/)
		{
			print FILE <<END;
$p		<RandomEffect>
END
			$p .= "\t";
		}

		my $actualeffect = $randomeffect;
		$actualeffect = $action_config{$randomeffect}{alias} if $action_config{$randomeffect}{alias};

		foreach my $part (split /\s+\\\s+/, $actualeffect)
		{
			my ($subeffect, @targets) = split /\s+/, $part;

			if ($effect !~ /\s\?/ && $subeffect eq 'setstatus' && $expandedrole->{status}{set} =~ /^ontrigger,use:([^;]*)/ && length($p) < 4)
			{
				push @triggeredeffects, $1;
				next;
			}

			my $special = $action_config{$subeffect}{status};
			my $value = $expandedrole->{status}{$special} || "";

			if ($xml_effect_cache{$part}{$value} && $acttype !~ /Effect/)
			{
				$statusused->{$special} = 1 if $special;
				print FILE <<END;
$p		<Effect reference="$xml_effect_cache{$part}{$value}"/>
END
				next;
			}
			# if ($part eq $shortaction && $acttype !~ /Effect/)
			# {
			# 	$xml_effect_cache{$part}{$value} = $expandedrole->{role} . ":" . $shortaction;
			# }

			print FILE <<END;
$p		<Effect type="$subeffect">
END

			if ($action_config{$subeffect}{targets} && @{$action_config{$subeffect}{targets}})
			{
				print FILE <<END;
$p			<Players>
END

				for my $i (0 .. $#{$action_config{$subeffect}{targets}})
				{
					my $target = $targets[$i] || '#' . ($i+1);

					#  #1, #2, etc. = 1st argument, 2nd argument, etc.
					#  #S = self
					#  #B = buddy
					#  #? = random target other than the player
					#  #* = all living targets except the player (action is duplicated)
					#  #T = all living targets on the player's team except the player (action is duplicated)
					if ($target =~ /#(\d+)/ && $acttype =~ /Effect/)
					{
						if ($1 <= 1)
						{
							print FILE <<END;
$p				<TriggeringPlayer/>
END
						}
						else
						{
							print FILE <<END;
$p				<Random/>
END
						}
					}
					elsif ($target =~ /#r?(\d+)/i)
					{
						print FILE <<END;
$p				<Target index="$1"/>
END
					}
					elsif ($target =~ /#s/i)
					{
						print FILE <<END;
$p				<Self/>
END
					}
					elsif ($target =~ /#b/i)
					{
						print FILE <<END;
$p				<Buddy/>
END
					}
					elsif ($target =~ /#\?/)
					{
						print FILE <<END;
$p				<Random/>
END
					}
					elsif ($target =~ /#\*/)
					{
						print FILE <<END;
$p				<All/>
END
					}
					elsif ($target =~ /#T/)
					{
						print FILE <<END;
$p				<Team/>
END
					}
					else
					{
						print FILE <<END;
$p				<Special>$target</Special>
END
					}
				}
				print FILE <<END;
$p			</Players>
END
			}
			else
			{
				print FILE <<END;
$p			<Players/>
END
			}

			if ($special)
			{
				$statusused->{$special} = 1;

				if ($special eq 'give')
				{
					print FILE <<END;
$p			<Gifts>
END
					my @gifts = split /,/, $value;
					foreach my $gift (@gifts)
					{
						$gift =~ s/:/;/;
						next if length($p) >= 2;
						export_xml_action($gift, "Ability", $expandedrole, $statusused, "\t\t\t");
					}
					print FILE <<END;
$p			</Gifts>
END
				}
				elsif ($special eq 'infect' || $special eq 'curse')
				{
					my $role = $value;
					if (!$role || $role eq '*')
					{
						print FILE <<END;
$p			<CopyRole/>
END
					}
					elsif ($role =~ /^\+(.*)$/)
					{
						print FILE <<END;
$p			<AddTemplate template="$1"/>
END
					}
					else
					{
						# my $rolename = role_name($role, 1);
						print FILE <<END;
$p			<NewRole role="$role"/>
END
					}
				}
				elsif ($special eq 'recruit')
				{
					my ($role, $extra) = split /,/, $value, 2;

					if ($role eq '*')
					{
						print FILE <<END;
$p			<CopyRole/>
END
					}
					elsif ($role =~ /^\+(.*)$/)
					{
						print FILE <<END;
$p			<AddTemplate template="$1"/>
END
					}
					elsif ($role)
					{
						# my $rolename = role_name($role, 1);
						print FILE <<END;
$p			<NewRole role="$role"/>
END
					}
					print FILE <<END;
$p			<CopyTeam/>
END
					print FILE <<END if $shortaction eq 'recruit';
$p			<PrerequisiteTeam team="town"/>
END
					print FILE <<END if $extra =~ /dieonfail/;
$p			<DieOnFailure/>
END
					print FILE <<END if $shortaction eq 'recruit' && $extra !~ /nofollowerdeath/;
$p			<RecruitDiesWithLeader/>
END
				}
				elsif ($special eq 'mutate')
				{
					print FILE <<END if $value =~ /newteam/;
$p			<MutateNewTeam/>
END
					print FILE <<END if $value =~ /fixteam/;
$p			<TeamAppropriateRole/>
END
					print FILE <<END if $value =~ /norarity/;
$p			<MutateIgnoresRarity/>
END
					print FILE <<END if $value =~ /\btemplate:(\w+)\b/;
$p			<MutateTemplate template="$1"/>
END
					print FILE <<END if $value =~ /\bsaverole\b/;
$p			<SavePreMutationRole/>
END
				}
				elsif ($special eq 'set')
				{
					foreach my $pair (split ';', $value)
					{
						my ($status, $newvalue) = split /,/, $pair, 2;

						if ($status eq 'immunekill' && $newvalue eq '*')
						{
							print FILE <<END;
$p			<SetImmuneKill/>
END
						}
						elsif ($status eq 'immunenonkill' && $newvalue eq '*')
						{
							print FILE <<END;
$p			<SetImmuneNonkill/>
END
						}
						elsif ($status =~ /^immune(.*)$/ && $newvalue eq '*')
						{
							print FILE <<END;
$p			<SetImmune type="$1"/>
END
						}
						elsif ($status eq 'maxvote')
						{
							print FILE <<END;
$p			<SetVotes value="$newvalue"/>
END
						}
						elsif ($status eq 'revive' && $newvalue eq '*')
						{
							print FILE <<END;
$p			<SetReviveOnDeath/>
END
						}
						elsif ($status eq 'ontrigger' && $newvalue =~ /^use:(.*)$/ && length($p) < 6)
						{
							# Recurse
							my $newexpandedrole = { %$expandedrole };
							$newexpandedrole->{status} = { %{$newexpandedrole->{status}} };
							foreach my $pair (split /;/, $value)
							{
								my ($status, $newvalue) = split /,/, $pair, 2;
								$newexpandedrole->{status}{$status} = $newvalue;
							}
							export_xml_action($1, "SetTriggerAutoAction", $newexpandedrole, $statusused, "\t\t");
						}
						elsif ($status eq 'ontrigger' && $newvalue =~ /^action:(.*)$/ && length($p) < 6)
						{
							# Recurse
							my $newexpandedrole = { %$expandedrole };
							$newexpandedrole->{status} = { %{$newexpandedrole->{status}} };
							foreach my $pair (split /;/, $value)
							{
								my ($status, $newvalue) = split /,/, $pair, 2;
								$newexpandedrole->{status}{$status} = $newvalue;
							}
							export_xml_action($1, "SetTriggerEffect", $newexpandedrole, $statusused, "\t\t");
						}
						elsif ($status eq 'ontarget' && $newvalue =~ 'action:copyability #1')
						{
							print FILE <<END;
$p			<SetLearning/>
END
						}
						else
						{
							print FILE <<END;
$p			<SetStatus name="$status" value="$value"/>
END
						}
					}
				}
				elsif ($special eq 'set' && $value eq 'immunekill,*')
				{
					print FILE <<END;
$p			<SetImmuneKill/>
END
				}
				elsif ($special eq 'convert')
				{
					my ($preteam, $role, $postteam) = split /,/, $value, 3;
					# my $rolename = role_name($role, 1);

					print FILE <<END;
$p			<PrerequisiteTeam team="$preteam"/>
$p			<NewRole role="$role"/>
$p			<NewTeam team="$postteam"/>
END
				}
				else
				{
					print FILE <<END if $value;
$p			<\u$special value="$value"/>
END
				}
			}

			print FILE <<END;
$p		</Effect>
END
		}
		print FILE <<END if $p ne $oldp;
$p		</RandomEffect>
END
		$p = $oldp;
	}

	if ($acttype =~ /Effects$/)
	{
	}
	elsif ($effect =~ /\s\?/)
	{
		print FILE <<END;
$p		</RandomEffects>
END
	}
	else
	{
		print FILE <<END;
$p		</Effects>
END
	}

	foreach my $triggeredeffect (@triggeredeffects)
	{
		$statusused->{set} = 1;
		# Recurse
		my $newexpandedrole = { %$expandedrole };
		$newexpandedrole->{status} = { %{$newexpandedrole->{status}} };
		foreach my $pair (split /;/, $expandedrole->{status}{set})
		{
			my ($status, $newvalue) = split /,/, $pair, 2;
			$newexpandedrole->{status}{$status} = $newvalue;
		}
		export_xml_action($triggeredeffect, "TriggeredEffects", $newexpandedrole, $statusused, "\t\t");
		
		next;
	}

	print FILE <<END;
$p	</$acttype>
END

	if ($action_config{$shortaction}{targets} && !$failure && !$expandedrole->{status}{dayaction} && !$expandedrole->{status}{timer} &&
		!$expandedrole->{status}{"replace$shortaction"} &&
		length($p) <= 1 && ($acttype eq "Action" || $acttype eq "GroupAction"))
	{
		my $special = $action_config{$shortaction}{status};
		my $value = $expandedrole->{status}{$special} || "";
		$xml_effect_cache{$action}{$value} = $expandedrole->{role} . ":" . $shortaction;
	}
}

sub export_xml_roles {
	my $filename = shift;

	our %xml_effect_cache = ();

	open FILE, '>', $filename;
	print FILE "<Roles>\n";

	my %statusmap = (
		deathteam => "CardflipTeam",
		deathrole => "CardflipRole",
		disease => "DiseaseDeathPercent",
		immunekill => "ImmuneKill",
		immunenonkill => "ImmuneNonkill",
		inspect => "InspectTeam",
		inspectrole => "InspectRole",
		invisible => "Untrackable",
		maxvote => "Votes",
		recruited => "Recruited",
		reflect => "Reflective",
		revive => "ReviveOnDeath",
		weapon => "Weapon",
		wolf => "Werewolf",
	);

	my %statusvaluemap = (
		"onall=action:superbus #S #B" => "Twin",
		"onbuddydeath=action:suicide" => "Lovestruck",
		"onday=action:winonlynch #B" => "Lyncher",
		"onlynch=revive" => "Unlynchable",
		"onlynch=supersaint" => "SuperSaint",
		"onlynch=winsoft" => "Jester",
		"onpowerdeath1=inherit" => "BackupAnyRole",
		"ontarget=action:copyability #1" => "Learning",
	);

	my %triggermap = (
		onall => "DayAndNightEffect",
		onbuddydeath => "BuddyDeathEffect",
		onday => "DayEffect",
		onday1 => "FirstDayEffect",
		ondeath => "AnyDeathEffect",
		ongrave => "DeathEffect",
		onlynch => "LynchEffect",
		onrevive => "ReviveEffect",
		ontarget => "RetributiveEffect",
		ontrigger => "TriggerEffect",
		onnight => "NightEffect",
	);

	foreach my $role ( sort { 
			defined($role_config{$b}{setup}) <=> defined($role_config{$a}{setup}) ||
			(($role_config{$b}{theme} || "normal") =~ /normal/) <=> (($role_config{$a}{theme} || "normal") =~ /normal/) ||
			($role_config{$a}{theme} || "normal") cmp ($role_config{$b}{theme} || "normal") ||
			($role_config{$a}{rarity} || 1) <=> ($role_config{$b}{rarity} || 1) || 
			role_name($a, 1) cmp role_name($b, 1) 
		} keys %role_config)
	{
		next unless is_real_role($role);
		#next unless $role_config{$role}{setup};
		#next unless ($role_config{$role}{theme} || "normal") =~ /normal/;
		next if $role_config{$role}{template};

		my $expandedrole = expand_setuprole($role);
		$expandedrole->{role} = $role;

		my $truename = role_name($role, 1);
		my $name = role_name($role, 0);

		my %statusused;
		$statusused{rolename} = 1;
		$statusused{roletext} = 1;
		$statusused{roletruename} = 1;

		print FILE <<END;
<Role id="$role" name="$truename">
END
		print FILE <<END if $truename ne $name;
	<DisplayName name="$name"/>
END
		
		foreach my $action (@{$expandedrole->{actions}})
		{
			export_xml_action($action, "Ability", $expandedrole, \%statusused);
		}

		my @groupactions = split /,/, ($expandedrole->{status}{groupactions} || "");
		$statusused{groupactions} = 1;
		
		foreach my $groupaction (@groupactions)
		{
			export_xml_action($groupaction, "GroupAbility", $expandedrole, \%statusused);
		}

		foreach my $status (sort { defined($triggermap{$b}) <=> defined($triggermap{$a}) || $a cmp $b } keys %{$expandedrole->{status}})
		{
			next if $statusused{$status};
			my $value = $expandedrole->{status}{$status};

			if ($status eq 'evolveto' || $status =~ /^tag/ || $status =~ /^teamaltrole/ || $status eq 'backupactions' ||
				($status =~ /^failure/ && $value eq '0'))
			{
				# Do nothing
			}
			elsif ($status =~ /^onroledeath1:(.*)$/ && $value eq 'transform' && $expandedrole->{status}{transform} =~ /^(\w+)=($1)$/)
			{
				my ($oldrole, $backup) = ($1, $2);
				my $alias = $role_config{$role}{alias} || $role;
				$alias =~ s/$oldrole/$backup/;
				my $newrole = canonicalize_role($alias, 1);
				$statusused{transform} = 1;
				# my $backup = role_name($1, 1);
				print FILE <<END;
	<Backup trigger="$backup" role="$newrole"/>
END
			}
			elsif ($status =~ /^onroledeath1:(.*)$/ && $value eq "transform:$1")
			{
				# my $backup = role_name($1, 1);
				print FILE <<END;
	<Backup trigger="$1" role="$1"/>
END
			}
			elsif ($status eq 'onday' && $value eq 'action' && $expandedrole->{status}{auto} eq "transform ? none ? none" && $expandedrole->{status}{transform} eq "template_nm=nm2")
			{
				my $transformrole = $role_config{$role}{alias};
				$transformrole =~ s/\+template_nm//;
				$statusused{auto} = 1;
				$statusused{transform} = 1;
				# my $amnesiac = role_name($transformrole, 1);
				print FILE <<END;
	<AmnesiacRole role="$transformrole"/>
END
			}
			elsif ($status eq 'onday' && $value eq 'action' && $expandedrole->{status}{auto} eq "transform ? none ? none" && $expandedrole->{status}{transform} =~ /^$role=(\w+)\+nm2,(.*)$/)
			{
				my $transformrole = $1;
				my $transformteam = $2;
				$statusused{auto} = 1;
				$statusused{transform} = 1;
				# my $amnesiac = role_name($transformrole, 1);
				print FILE <<END;
	<AmnesiacRole role="$transformrole" team="$transformteam"/>
END
			}
			elsif ($status eq 'replacenone')
			{
				export_xml_action($value, "DefaultAction", $expandedrole, \%statusused);
			}
			elsif ($status eq 'onall' && $value eq 'action:setstatus #*' && $expandedrole->{status}{set} =~ /^act(\w+),\*/)
			{
				$statusused{set} = 1;
				# Recurse
				my $newexpandedrole = { %$expandedrole };
				$newexpandedrole->{status} = { %{$newexpandedrole->{status}} };
				foreach my $pair (split /;/, $expandedrole->{status}{set})
				{
					my ($status, $newvalue) = split /,/, $pair, 2;
					$newexpandedrole->{status}{$status} = $newvalue;
				}
				export_xml_action($1, "AllGrantedAction", $newexpandedrole, \%statusused);
			}
			elsif ($status eq 'onall' && $value eq 'action:setstatus #T' && $expandedrole->{status}{set} =~ /^act(\w+),\*/)
			{
				$statusused{set} = 1;
				# Recurse
				my $newexpandedrole = { %$expandedrole };
				$newexpandedrole->{status} = { %{$newexpandedrole->{status}} };
				foreach my $pair (split /;/, $expandedrole->{status}{set})
				{
					my ($status, $newvalue) = split /,/, $pair, 2;
					$newexpandedrole->{status}{$status} = $newvalue;
				}
				export_xml_action($1, "TeamGrantedAction", $newexpandedrole, \%statusused);
			}
			elsif ($status eq 'onall' && $value eq 'action:setstatus #T' && $expandedrole->{status}{set} =~ /^act(\w+),0$/)
			{
				$statusused{set} = 1;
				print FILE <<END;
	<TeamDeniedAbility name="$1"/>
END
			}
			elsif ($status eq 'ondusk' && $value eq 'action:setstatus #T' && $expandedrole->{status}{set} =~ /^immunekill,\*$/)
			{
				$statusused{set} = 1;
				print FILE <<END;
	<TeamImmuneNightkill/>
END
			}
			elsif ($status eq 'onall' && $value eq 'action:setstatus #T' && $expandedrole->{status}{set} =~ /^immunekill,\*$/)
			{
				$statusused{set} = 1;
				print FILE <<END;
	<TeamImmuneKill/>
END
			}
			elsif ($status eq 'onall' && $value eq 'action:setstatus #T' && $expandedrole->{status}{set} =~ /^immunenonkill,\*$/)
			{
				$statusused{set} = 1;
				print FILE <<END;
	<TeamImmuneNonkill/>
END
			}
			elsif ($status eq 'onall' && $value eq 'action:setstatus #T' && $expandedrole->{status}{set} =~ /^invisible,\*$/)
			{
				$statusused{set} = 1;
				print FILE <<END;
	<TeamUntrackable/>
END
			}
			elsif ($status eq 'onall' && $value eq 'action:setstatus #T' && $expandedrole->{status}{set} =~ /^immune(\w+),\*$/)
			{
				$statusused{set} = 1;
				print FILE <<END;
	<TeamImmune type="$1"/>
END
			}
			elsif ($status eq 'onlynch' && $value =~ /^transform:(.*)$/)
			{
				my ($role, $team) = split /,/, $1, 2;
				# my $rolename = role_name($role, 1);
				if ($team)
				{
					print FILE <<END;
	<LynchChangeRole role="$role" team="$team"/>
END
				}
				else
				{
					print FILE <<END;
	<LynchChangeRole role="$role"/>
END
				}
			}
			elsif ($status eq 'revive' && $value =~ /^transform:(.*)$/)
			{
				my ($newrole, $team) = split /,/, $1, 2;
				print FILE <<END;
	<ReviveOnDeath/>
	<ReviveEffect>
END
				if ($team)
				{
					print FILE <<END;
		<Transform role="$newrole"/>
END
				}
				else
				{
					print FILE <<END;
		<Transform role="$newrole" team="$team"/>
END
				}
				print FILE <<END;
	</ReviveEffect>
END
			}
			elsif ($status eq 'ontrigger' && $value =~ /^use:(.*)$/)
			{
				export_xml_action($1, "TriggerAutoAction", $expandedrole, \%statusused);
			}
			elsif ($statusvaluemap{"$status=$value"})
			{
				print FILE <<END;
	<$statusvaluemap{"$status=$value"}/>
END
			}
			elsif ($triggermap{$status} && $value =~ /^action:(.*)$/)
			{
				export_xml_action($1, $triggermap{$status}, $expandedrole, \%statusused);
			}
			elsif ($triggermap{$status} && $value eq 'action' && $expandedrole->{status}{auto})
			{
				$statusused{auto} = 1;
				export_xml_action($expandedrole->{status}{auto}, $triggermap{$status}, $expandedrole, \%statusused);
			}
			elsif ($triggermap{$status} && $value =~ /^transform(?::(.*))?$/)
			{
				my ($newrole, $team) = split /,/, $1, 2;
				unless ($newrole)
				{
					($newrole, $team) = split /,/, $expandedrole->{status}{transform}, 2;
					$statusused{transform} = 1;
				}

				$newrole =~ s/^$role=//;

				# my $rolename = role_name($role, 1);

				print FILE <<END;
	<$triggermap{$status}>
END
				if ($team)
				{
					print FILE <<END;
		<Transform role="$newrole"/>
END
				}
				else
				{
					print FILE <<END;
		<Transform role="$newrole" team="$team"/>
END
				}
				print FILE <<END;
	</$triggermap{$status}>
END
			}				
			elsif ($statusmap{$status})
			{
				if ($value ne '*')
				{
					print FILE <<END;
	<$statusmap{$status} value="$value"/>
END
				}
				else
				{
					print FILE <<END;
	<$statusmap{$status}/>
END
				}
			}
			elsif ($status =~ /^immune(.*)$/ && $value eq '*')
			{
				print FILE <<END;
	<Immune type="$1"/>
END
			}
			elsif ($value ne '*')
			{
				print FILE <<END;
	<Status name="$status" value="$value"/>
END
			}
			else
			{
				print FILE <<END;
	<Status name="$status"/>
END
			}
		}

		print FILE <<END;
</Role>
END
	}

	print FILE "</Roles>\n";
	close FILE;
}

sub create_action_help_file {
	my $filename = shift;
	
	open FILE, '>', $filename;
	
	foreach my $action (sort keys %action_config)
	{
		my $targets = " [player]" x scalar(@{$action_config{$action}{targets} || []});
		my $synthdesc = "No description.";
		if ($action_config{$action}{alias}) {
			my @subactions;
			my $random;
			if ($action_config{$action}{alias} =~ /\s+\?\s+/) {
				@subactions = split /\s+\?\s+/, $action_config{$action}{alias};
				map { s/\s+.*$// } @subactions;
				$random = 1;
			} else {
				@subactions = split /\s+\\\s+/, $action_config{$action}{alias};
				map { s/\s+.*$// } @subactions;
				$random = 0;
			}
			if (@subactions > 1) {
				if ($random) {
					$synthdesc = 'Performs one of ' . join(', ', @subactions[0 .. $#subactions - 1]) . ' or ' . $subactions[$#subactions] . ' at random.';
				} else {
					$synthdesc = 'Performs ' . join(', ', @subactions[0 .. $#subactions - 1]) . ' and ' . $subactions[$#subactions] . '.';
				}
			}
			else {
				$synthdesc = 'This is an alias for ' . $action_config{$action}{alias} . '.';
			}
		}
		
		my $help = $action_config{$action}{help} || "$action$targets: $synthdesc";
		print FILE "$help\n";
	}
	
	close FILE;	
}

sub create_rolename_file {
	my $filename = shift;
	open FILE, '>', $filename;
	
	foreach my $role (sort keys %role_config)
	{
		next if $role =~ /\*/;

		my $rolename = role_name($role, 1);
		next unless $rolename;
		next if $rolename eq '<$role>';
		print FILE "$role $rolename\n";
	}
	
	close FILE;	
}

sub create_roleclass_file {
	my $filename = shift;
	open FILE, '>', $filename;

	foreach my $role (sort keys %role_config)
	{
		my $class = $role_config{$role}{countas};
		next unless $class;
		print FILE "$role $class\n";
	}

	close FILE;
}

sub create_rolepm_file {
	my $filename = shift;
	open FILE, '>', $filename;

	my %setups_by_theme;

	foreach my $setup (sort keys %setup_config) {
		next if $setup_config{$setup}{hidden};
		next if $setup_config{$setup}{players};

		my $theme = $setup_config{$setup}{theme} || "normal";

		push @{$setups_by_theme{$theme}}, $setup;
	}

	foreach my $theme ("normal", grep { $_ ne "normal" } sort keys %setups_by_theme) {
		print FILE "[size=16]=== ", join(", ", @{$setups_by_theme{$theme}}), " ===[/size]\n";

		foreach my $role (sort { 
				($role_config{$a}{rarity} || 1) <=> ($role_config{$b}{rarity} || 1) ||
				role_name($a, 1) cmp role_name($b, 1)
			} keys %role_config) {
			my $roletheme = $role_config{$role}{theme} || "normal";
			next unless $roletheme =~ /\b$theme\b/;
			next unless $role_config{$role}{setup};
			next if role_is_secret($role);
			next if $role =~ /^\*/;

			my $role_help = role_help_text($role, "forum");

			print FILE $role_help, "\n";
		}

		print FILE "\n";
	}

	close FILE;
	return "Created";
}

sub create_evolution_dot_file {
	open FILE, ">", "roles.dot";
	autoflush FILE 1;

	print FILE "digraph \"Roles\" {\n";

	foreach my $role (keys %role_config)
	{
		next if $role_config{$role}{template};
		next if $role_config{$role}{imported};
		next unless is_real_role($role);
		next unless ($role_config{$role}{theme} || "normal") =~ /\bnormal\b/;

		print FILE "\"" . role_name($role, 1) . "\\n$role\" [fontsize=8 shape=\"box\"];\n";

		foreach my $evolve (get_evolution($role))
		{
			next unless $evolve;
			next if $evolve eq $role;
			print FILE "\"" . role_name($role, 1) . "\\n$role\" -> \"" . role_name($evolve, 1) . "\\n$evolve\";\n";
		}
	}

	print FILE "}\n";

	close FILE;
}

# This is automatically called after all files are loaded
sub postload {
	if (!%messages)
	{
		load_config_file("mafia/messages.ini", \%messages);
	}
	
	import_fadeblue_setups("mafia/setup.ini", "normal");

	open FILE, "<", "mafia/funnynames";
	@funny_roles = <FILE>;
	close FILE;
	map { chomp $_ } @funny_roles;

	$phase = "" unless defined($phase);
	update_voiced_players();
}

sub join_handler {
	my ($nick) = @_;

	update_voiced_players();

	# notice($::owner, "Join: $nick");
}

sub nick_handler {
	my ($oldnick, $newnick) = @_;

	update_voiced_players();

	# notice($::owner, "Nick: $oldnick -> $newnick");
}

sub add_handlers {
	::add_event_handler('join', \&join_handler);
	::add_event_handler('nick', \&nick_handler);
}

1;
