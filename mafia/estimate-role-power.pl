#!/usr/bin/perl -W

use Carp;

my %bad_setups = (
	moderated => 1,
	upick => 1,
	momir => 1,
	evomomir => 1,
	chainsaw => 1,
	dethy => 1,
	texas10 => 1,
	vengeful => 1,
	# These two setups have no power roles
	assassin => 1,
	lyncher => 1,
	# Replay tends to skew results
	replay => 1,
	# Smalltown has significantly different play
	smalltown => 1,
	"smalltown+" => 1,
);

use constant USE_MULTIROLE => 0;

open FILE, "<", "game.log";

while (my $line = <FILE>)
{
	chomp $line;
	if ($line =~ /^start/)
	{
		my (undef, $gameid, undef, undef, $setup, $players) = split / /, $line;
		$gameid = $gameid + 0;

		$game{$gameid}{setup} = $setup;
		$game{$gameid}{players} = $players;
	}
	if ($line =~ /^player/)
	{
		my (undef, $gameid, $player, $mask) = split / /, $line;

		$game{$gameid}{fake} = 1 if $mask eq 'fake';
	}
	if ($line =~ /^result/)
	{
		my (undef, $gameid, $player, $result, $startteam, $startrole, $endteam, $endrole, undef, undef) = split / /, $line;

		$gameid = $gameid + 0;

		my $score = 0;
		$score = 1 if $result eq 'win';
		$score = -1 if $result eq 'lose';

		$game{$gameid}{playercount}++;
		$game{$gameid}{teamcount}{$startteam}++;

		if (USE_MULTIROLE)
		{
			foreach my $subrole (split /\+/, $startrole)
			{
				push @{$game{$gameid}{teamroles}{$startteam}}, $subrole;
				push @{$game{$gameid}{teamscores}{$startteam}}, $score;
			}
		}
		else
		{
			push @{$game{$gameid}{teamroles}{$startteam}}, $startrole;
			push @{$game{$gameid}{teamscores}{$startteam}}, $score;
		}

		$role_count{$startrole}++;
		$start_role_count{$startrole}++;
	}
}

close FILE;

@games = map { $game{$_} } sort { $a <=> $b } grep { $game{$_}{playercount} && !$game{$_}{fake} } keys %game;

print "Read " . scalar(@games) . " games with " . scalar(keys %role_count) . " unique roles\n";

use constant USE_SCUM_COUNTS => 0;
use constant USE_TOWNIES => 1;
use constant USE_BASE => 0;

use constant USE_SIZE_FACTOR => 0;

foreach my $game (@games)
{
	my $townscore = 0;
	$townscore += $_ foreach @{$game->{teamscores}{town}};
	$townscore = 1 if $townscore > 0;
	$townscore = -1 if $townscore < 0;

	if (USE_SCUM_COUNTS)
	{
		foreach my $team (keys %{$game->{teamroles}})
		{
			next if $team eq 'town';
	
			my $scumcode = "scum-" . $team;
			my $count = 0;
			$scumcode =~ s/\d+$//;

			foreach my $role (@{$game->{teamroles}{$team}})
			{
				push @{$game->{teamroles}{town}}, $scumcode . (++$count);
				push @{$game->{teamscores}{town}}, $townscore;
			}

			if ($scumcode eq "scum-cult") {
				for (1 .. $game->{playercount}) {
					push @{$game->{teamroles}{town}}, "cult-bonus";
					push @{$game->{teamscores}{town}}, $townscore;
				}
			}
		}
	}

	if (USE_BASE)
	{
		push @{$game->{teamroles}{town}}, "base-town";
		push @{$game->{teamscores}{town}}, $townscore;
	}
}

@games = map {
	my $game = $_;
	map {
		my $newgame = { %$game };
		my $keyteam = $_;
		$newgame->{keyteam} = $keyteam;
		my $totscore = 0;
		foreach my $score (@{$newgame->{teamscores}{town}}) {
			$totscore += $score;
		}
		$totscore = -1 if $totscore < 0;
		$totscore = 1 if $totscore > 0;
		if ($keyteam ne 'town') {
			$newgame->{teamscores}{$keyteam} = [(-$totscore) x $newgame->{teamcount}{$keyteam}];
			$newgame->{keyscore} = -$totscore;
		}
		else {
			$newgame->{keyscore} = $totscore;
		}
		$newgame;
	} keys %{$game->{teamcount}};
} @games;

foreach my $game (@games)
{
	my @teams = sort keys %{$game->{teamcount}};
	my $keyteam = $game->{keyteam};
	my $setupcode = join(' ', map { ($_, $game->{teamcount}{$_}) } @teams) . " ; $keyteam";
	$game->{setupcode} = $setupcode;
}

%setupcode_count = ();
$setupcode_count{$_->{setupcode}}++ foreach @games;
%start_setupcode_count = %setupcode_count;
@start_games = grep { good_game($_, 1) } @games;

use constant MINROLECOUNT => 3;
use constant MINWINCOUNT => 1;
use constant MINLOSSCOUNT => 1;
use constant MINSETUPCOUNT => 1;
use constant MINPLAYERS => 4;

use constant MINROLECOUNT_FOR_OUTPUT => 15;

sub good_game
{	
	my $game = shift;
	my $ignoreroles = shift;

	return 0 unless $game->{setup};
	return 0 if $bad_setups{$game->{setup}};
	return 0 unless $setupcode_count{$game->{setupcode}} >= MINSETUPCOUNT;
	return 0 unless $game->{players} >= MINPLAYERS;
	return 0 unless ($game->{teamcount}{town} || 0) >= 2;

	my $keyteam = $game->{keyteam};
	return 0 unless $game->{teamcount}{$keyteam};

	return 1 if $ignoreroles;

	foreach my $team (keys %{$game->{teamroles}})
	{
		if ($team eq $keyteam)
		{
			foreach my $role (@{$game->{teamroles}{$team}})
			{
				# return 0 unless $role =~ /^t$|^v$|^rb$|^d$|^c$|^base|^scum/;
				return 0 unless ($role_count{$role} || 0) >= MINROLECOUNT;
				return 0 unless ($role_wins{$role} || 0) >= MINWINCOUNT;
				return 0 unless ($role_losses{$role} || 0) >= MINLOSSCOUNT;
			}
		}
	}

	return 1;
}

do
{
	$old_game_count = @games;

	print STDERR "Considering $old_game_count games\n";

	%role_count = %role_wins = %role_losses = ();
	foreach my $game (@games)
	{
		%seen = ();
		my $team = $game->{keyteam};
		for my $role (@{$game->{teamroles}{$team}})
		{
			$role_count{$role}++;

			next if $seen{$team}{$role};
			$seen{$team}{$role}++;

			$role_wins{$role}++ if $game->{keyscore} > 0;
			$role_losses{$role}++ if $game->{keyscore} < 0;
		}
	}

	%setupcode_count = ();
	$setupcode_count{$_->{setupcode}}++ foreach @games;

	# Eliminate games with roles that haven't appeared much
	@games = grep { good_game($_) } @games;
} while ($old_game_count != @games);

print "Using " . scalar(@games) . " games with " . scalar(keys %role_count) . " unique roles\n";

sub setup_power
{
	my $setupcode = shift;

	my ($teams, $keyteam) = split / ; /, $setupcode, 2;
	my %teams = split / /, $teams;
	my $numplayers = 0;
	foreach $team (keys %teams) {
		$numplayers += $teams{$team};
	}
	my $power = 0;
	{
		foreach my $team (qw[mafia mafia1 mafia2 sk sk1 sk2 sk3 sk4 wolf])
		{
			$power += $teams{$team} * 3.00 - 1.60 if $teams{$team};
		}
		$power += $teams{cult} * (1.4 + 0.6 * $numplayers) if $teams{cult};
		foreach my $team (qw[survivor survivor1 survivor2 survivor3])
		{
			$power += $teams{$team} * -0.5 if $teams{$team};
		}
	}
	$power += $teams{town} * -0.9;
	$power += 2.3;

	if ($keyteam =~ /mafia|wolf/) {
		$power = 0.05 * ($numplayers - $teams{$keyteam}) + 0.20 * $power;
	}
	elsif ($keyteam !~ /town/) {
		$power = 1;
	}

	return $power;
}

sub setup_win_factor
{
	my $setupcode = shift;

	my ($teams, $keyteam) = split / ; /, $setupcode, 2;
	my %teams = split / /, $teams;
	my $winfactor = 0;

	foreach my $team (qw[mafia mafia1 mafia2 wolf cult])
	{
		$winfactor += 1 if $teams{$team};
	}
	foreach my $team (qw[sk sk1 sk2 sk3 sk4])
	{
		$winfactor += 0.5 if $teams{$team};
	}
	$winfactor = 1 if $winfactor < 1;
	return $winfactor;
}

foreach my $setupcode (keys %setupcode_count)
{
	my ($teams, $keyteam) = split / ; /, $setupcode, 2;
	my %teams = split / /, $teams;

	$setup_power{$setupcode} = setup_power($setupcode);
	$setup_win_factor{$setupcode} = setup_win_factor($setupcode);
	$setup_powerdev{$setupcode} = 0.1 * $teams{town};

	my $players = 0;
	$players += $teams{$_} foreach (keys %teams);
	$setup_players{$setupcode} = $players;
}

# Get average power
my $town_count_total = 0;
my $town_power_total = 0;
foreach my $game (@games)
{
	$town_count_total += $game->{teamcount}{$game->{keyteam}};
	$town_power_total += $setup_power{$game->{setupcode}};
}
$average_power = $town_power_total / $town_count_total;

foreach my $role (keys %role_count)
{
	$role_power{$role} = $average_power;
	$role_power{$role} = 0 if $role =~ m[/];
}
$role_power{'t'} = 0;
$role_power{'m'} = 0;
$role_power{'sk'} = 1;

use constant MAX_POWER_DIFFERENCE => 0;
use constant POWER_DIFFERENCE_BASE => 0.85;

for my $iteration (1..250)
{
	print STDERR "." if $iteration % 10 == 0;
	my $anneal = 8 / ($iteration + 10);
	my $anneal2 = $anneal;
	$anneal = 0.01 if $anneal < 0.1;

	foreach my $game (@games)
	{
		my $total_power = 0;
		my $keyteam = $game->{keyteam};
		for my $role (@{$game->{teamroles}{$keyteam}})
		{
			$total_power += $role_power{$role};
		}

		my $setup_power = $setup_power{$game->{setupcode}};
		my $setup_win_factor = $setup_win_factor{$game->{setupcode}};
		my $setup_powerdev = $setup_powerdev{$game->{setupcode}};
		my $extra_power = ($total_power - $setup_power) / $setup_powerdev;
		my $sizefactor = USE_SIZE_FACTOR ? $game->{players} / 5 : 1;
		my $weightloss = -$anneal * $sizefactor * POWER_DIFFERENCE_BASE / (POWER_DIFFERENCE_BASE - ($extra_power <=   MAX_POWER_DIFFERENCE  ? $extra_power :   MAX_POWER_DIFFERENCE));
		my $weightwin =   $anneal * $sizefactor * POWER_DIFFERENCE_BASE / (POWER_DIFFERENCE_BASE + ($extra_power >= -(MAX_POWER_DIFFERENCE) ? $extra_power : -(MAX_POWER_DIFFERENCE))) * $setup_win_factor;

		for my $role (@{$game->{teamroles}{$keyteam}})
		{
			next if $role eq 't' && !USE_TOWNIES;
			next if $role eq 'm/mafia';
			if ($game->{keyscore} > 0) {
				$role_power{$role} += $weightwin * 20 / $role_count{$role};
				$role_power{$role} = 2 if $role_power{$role} > 2;
			}
			elsif ($game->{keyscore} < 0) {
				$role_power{$role} += $weightloss * 20 / $role_count{$role};
				$role_power{$role} = -1 if $role_power{$role} < -1;
			}
		}
	}
}
print STDERR "\n";

foreach my $game (@games)
{
	my $total_power = 0;
	my $keyteam = $game->{keyteam};
	for my $role (@{$game->{teamroles}{$keyteam}})
	{
		$total_power += $role_power{$role};
	}

	$game->{total_power} = $total_power;
}

foreach my $role (keys %start_role_count)
{
	$role_count{$role} = 0 unless defined($role_count{$role});
	$role_power{$role} = "0" unless defined($role_power{$role});
}
foreach my $game (@start_games)
{
	$game->{skipped} = !defined($game->{total_power});
	$game->{total_power} = "0" unless defined($game->{total_power});
	$setup_power{$game->{setupcode}} = "0" unless defined($setup_power{$game->{setupcode}});
}

print map { "SETUP $_ ($setupcode_count{$_}/$start_setupcode_count{$_}) [$setup_power{$_} +- $setup_powerdev{$_}]\n" } sort { $setup_players{$a} <=> $setup_players{$b} || $setup_power{$a} <=> $setup_power{$b} || $a cmp $b } keys %setupcode_count;
print map { sprintf "ROLE $_ ($role_count{$_}/*) [%.2f]\n", $role_power{$_} } sort grep { !$start_role_count{$_} } keys %role_count;
print map { sprintf "ROLE $_ ($role_count{$_}/$start_role_count{$_}) [%.2f]\n", $role_power{$_} } sort grep { $start_role_count{$_} >= 3 } keys %start_role_count;
print map { sprintf "%s $_->{setup} : $_->{setupcode} : %s : $_->{keyscore} [%.2f / %.2f]\n", ($_->{skipped} ? "SKIP" : "GAME"), join(' ', map { $role_count{$_} > 0 ? $_ : "$_*" } @{$_->{teamroles}{$_->{keyteam}}}), $_->{total_power}, $setup_power{$_->{setupcode}}} @start_games;

exit 0 if USE_SCUM_COUNTS or USE_BASE or USE_MULTIROLE;

open OUT, ">", "rolepower.dat";
foreach my $role (sort keys %role_count)
{
	print OUT "$role seencount $start_role_count{$role}\n" if $start_role_count{$role} >= 3;

	next unless $role_count{$role} >= MINROLECOUNT_FOR_OUTPUT;

	if (USE_MULTIROLE)
	{
		print OUT "$role multirolepower $role_power{$role} multirolechangecount $role_count{$role}\n";
	}
	else
	{
		print OUT "$role power $role_power{$role} changecount $role_count{$role}\n";
	}
}
close OUT;
