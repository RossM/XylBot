#!/usr/bin/perl

use warnings;
use IO::Handle;

autoflush STDOUT;
autoflush STDERR;

our %game_nick_masks;
our %mask_nicks;
our %game_data;
our %game_player_data;
our %player_stats;
our %nick_stats;
our %game_stats;
our %canonical_case;
our %invalid_game;
our %game_setups;

our $earliesttime;

our $maxrank = 100;
our $scorescale = 1500;

our %timestart = (
	quarterly => time - 90 * 24 * 60 * 60,
	monthly => time - 30 * 24 * 60 * 60,
	weekly => time - 7 * 24 * 60 * 60,
	daily => time - 24 * 60 * 60,
);

our %valid_setups = (
normal => 1,
straight => 1,
mild => 1,
average => 1,
wacky => 1,
insane => 1,
unranked => 0,
oddrole => 1,
chosen => 1,
multirole => 1,
multichosen => 1,
mm => 1,
chaos => 1,
luigi => 1,
xylspecial => 1,
deliciouscake => 1,
australian => 1,
balanced => 1,
noreveal => 1,
cosmic => 1,
timespiral => 1,
upick => 0,
moderated => 0,
league => 1,
dethy => 0,
lyncher => 0,
kingmaker => 0,
assassin => 0,
momir => 0,
evomomir => 0,
mountainous => 1,
wtf => 0,
vengeful => 0,
raf => 0,
"momir-duel" => 0,
chainsaw => 0,
simenon => 0,
piec9 => 0,
basic12 => 0,
ss3 => 0,
smalltown => 1,
"smalltown+" => 1,
challenge => 1,
bonanza => 1,
"cosmic-smalltown" => 1,
ff6 => 1,
test => 0,
fadebot => 1, 
);

our %aliases = (
"Kevylin" => "Kevy",
);

our (%known_setups, %known_teams, %known_roles);
our %setup_maxplayers;

our %total;

print STDERR "Reading games...\n";

open GAME, "<", "game.log";

while (my $line = <GAME>)
{
	chomp $line;
	my ($type, $gameid, @params) = split /\s+/, $line;

	if ($type eq 'start')
	{
		my ($channel, $starttime, $setup, $players) = @params;
		
		$game_data{$gameid}{channel} = $channel;
		$game_data{$gameid}{starttime} = $starttime;
		$game_data{$gameid}{setup} = $setup;
		$game_data{$gameid}{players} = $players;

		$known_setups{$setup}++;
		
		$invalid_game{$gameid} = 1 unless $valid_setups{$setup};
		
		$earliest_time = $starttime if (!$earliest_time || $earliest_time > $starttime);

		$game_setups{$gameid} = ["$setup", "all"];
		push @{$game_setups{$gameid}}, "" unless $invalid_game{$gameid};
		foreach my $era (keys %timestart)
		{
			push @{$game_setups{$gameid}}, "$era" if $game_data{$gameid}{starttime} >= $timestart{$era};
			push @{$game_setups{$gameid}}, "$era$setup" if $game_data{$gameid}{starttime} >= $timestart{$era};
		}

		foreach my $setup2 (@{$game_setups{$gameid}})
		{
			$setup_maxplayers{$setup2} = $players if $players > ($setup_maxplayers{$setup2} || 0);
		}
	}
	elsif ($type eq 'player')
	{
		my ($nick, $mask) = @params;
		$game_nick_masks{$gameid}{$nick} = $mask;
		$mask_nicks{$mask}{lc $nick}++;
		$canonical_case{lc $nick} = $nick;
	}
	elsif ($type eq 'result')
	{
		my ($nick, $result, $startteam, $startrole, $endteam, $endrole, $liveness, $killer) = @params;
		my $player = $game_nick_masks{$gameid}{$nick};
		next unless $player;

		$game_player_data{$gameid}{$player}{result} = ($result eq 'win' ? 1 : ($result eq 'draw' ? 0.5 : 0));
		$game_player_data{$gameid}{$player}{startteam} = $startteam;
		$game_player_data{$gameid}{$player}{startrole} = $startrole;
		$game_player_data{$gameid}{$player}{endteam} = $endteam;
		$game_player_data{$gameid}{$player}{endrole} = $endrole;
		$game_player_data{$gameid}{$player}{liveness} = $liveness;
		$game_player_data{$gameid}{$player}{killer} = $killer;

		my $setup = $game_data{$gameid}{setup};
		my $players = $game_data{$gameid}{players};

		my $baseendteam = $endteam;
		$baseendteam =~ s/\d+$//;
		$baseendteam =~ s/-ally$//;
		
		$known_teams{$baseendteam}++;
		$known_roles{$startrole}++;
		
		foreach my $s (@{$game_setups{$gameid}})
		{
			foreach my $p ("all", $players)
			{
				foreach my $t ("all", $baseendteam)
				{
					my $suffix = "_${s}_${p}_${t}";
					$player_stats{$player}{games}{$suffix}++;
					$player_stats{$player}{wins}{$suffix}++ if $result eq 'win';
					$player_stats{$player}{losses}{$suffix}++ if $result eq 'lose';
					$player_stats{$player}{draws}{$suffix}++ if $result eq 'draw';
				
					$total{games}{$suffix}++;
					$total{wins}{$suffix}++ if $result eq 'win';
					$total{losses}{$suffix}++ if $result eq 'lose';
					$total{draws}{$suffix}++ if $result eq 'draw';
					$total{other}{$suffix}++ if $result ne 'win' && $result ne 'lose' && $result ne 'draw';

					$game_stats{$gameid}{"teamgames"}{"$suffix"}++;
					$game_stats{$gameid}{"teamwins"}{"$suffix"}++ if $result eq 'win';
					$game_stats{$gameid}{"teamlosses"}{"$suffix"}++ if $result eq 'lose';
					$game_stats{$gameid}{"teamdraws"}{"$suffix"}++ if $result eq 'draw';

					$suffix = "_${s}_${p}_${t}_${startrole}";
					$player_stats{$player}{rolegames}{$suffix}++;
					$player_stats{$player}{rolewins}{$suffix}++ if $result eq 'win';
					$player_stats{$player}{rolelosses}{$suffix}++ if $result eq 'lose';
					$player_stats{$player}{roledraws}{$suffix}++ if $result eq 'draw';
				
					$total{rolegames}{$suffix}++;
					$total{rolewins}{$suffix}++ if $result eq 'win';
					$total{rolelosses}{$suffix}++ if $result eq 'lose';
					$total{roledraws}{$suffix}++ if $result eq 'draw';
					$total{roleother}{$suffix}++ if $result ne 'win' && $result ne 'lose' && $result ne 'draw';
				}
			}
		}

		next if $invalid_game{$gameid};
		
		$player_stats{$player}{stats}{aliveatend}++ if $liveness eq 'alive';
		$player_stats{$player}{stats}{deadatend}++ if $liveness eq 'dead';
		$player_stats{$player}{stats}{changedteam}++ if $startteam ne $endteam;
		$player_stats{$player}{stats}{changedrole}++ if $startrole ne $endrole;
	}
	elsif ($type eq 'stats')
	{
		my ($nick, @stats) = @params;
		my $player = $game_nick_masks{$gameid}{$nick};
		next unless $player;
		
		# next if $invalid_game{$gameid};
		
		while (@stats)
		{
			my $stat = shift @stats;
			my $value = shift @stats;
			
			$player_stats{$player}{stats}{$stat} += $value;
		}
	}
	elsif ($type eq 'end')
	{
		my ($endtime) = @params;
		$game_data{$gameid}{endtime} = $endtime;
	}
	elsif ($type eq 'moderator')
	{
	}
	else
	{
		printf STDERR "Warning: Unknown line type '$type'\n";
	}
}

close GAME;

print "Stats from " . scalar(localtime($earliest_time)) . " to " . scalar(localtime(time)) . "\n\n";

print STDERR "Collecting per-game stats...\n";

# Collect per-game stats
foreach my $gameid (keys %game_stats)
{
	foreach my $key (keys %{$game_stats{$gameid}})
	{
		foreach my $subkey (keys %{$game_stats{$gameid}{$key}})
		{
			$total{$key}{$subkey}++ if $game_stats{$gameid}{$key}{$subkey};
		}
	}
}

print STDERR "Consolidating stats by common nick...\n";

# Find each mask's most common nick and consolidate stats
foreach my $mask (keys %mask_nicks)
{
	next if $mask eq 'fake';
	
	my @nicks = keys %{$mask_nicks{$mask}};
	@nicks = sort { $mask_nicks{$mask}{$b} <=> $mask_nicks{$mask}{$a} } @nicks;
	my $nick = $nicks[0];
	$nick = $aliases{$nick} if exists $aliases{$nick};

	$common_nick_by_mask{$mask} = $nick;
	
	foreach my $stat (keys %{$player_stats{$mask}})
	{
		foreach my $subkey (keys %{$player_stats{$mask}{$stat}})
		{
			$nick_stats{$nick}{$stat}{$subkey} += $player_stats{$mask}{$stat}{$subkey};
		}
	}
}

print STDERR "Eliminating stale records...\n";

# Eliminate players who haven't played recently
foreach my $nick (keys %nick_stats)
{
	delete $nick_stats{$nick} unless $nick_stats{$nick}{"games"}{"_quarterly_all_all"};
}

print STDERR "Calculating point factors...\n";

foreach my $setup (keys %known_setups)
{
	foreach my $players (2 .. $setup_maxplayers{$setup})
	{
		next unless $total{"games"}{"_${setup}_${players}_all"};
		my $games = $total{"games"}{"_${setup}_${players}_all"} / $players;
		foreach my $team (keys %known_teams)
		{
			my $suffix = "_${setup}_${players}_${team}";
			next unless $total{"games"}{"$suffix"};

			# This factor pulls the average wins of a group towards the average. This increases the effect of winning with a group that rarely comes up.
			my $baseplayerfactor = 1;
			my $baseplayers = $baseplayerfactor * $total{"games"}{"$suffix"} / $games;
			my $baseplayerwins = $baseplayers * (($total{"wins"}{"_${setup}_${players}_all"} || 0) + 0.5 * ($total{"draws"}{"_${setup}_${players}_all"} || 0)) / $total{"games"}{"_${setup}_${players}_all"};

			# Calculate the average win chance of a player for this setup, group, and number of players (modified by the fudge factor above)
			my $pavgwins = (($total{"wins"}{"$suffix"} || 0) + 0.5 * ($total{"draws"}{"$suffix"} || 0) + $baseplayerwins) / (($total{"games"}{"$suffix"} || 0) + $baseplayers);
			$total{"avgwins"}{"$suffix"} = $pavgwins;
				
			# Larger games are weighted more heavily
			my $importance = (($players - 1) / 5);

			$total{"pointswin"}{"$suffix"} = $pavgwins > 0 ? $importance / $pavgwins : 0;
			$total{"pointsloss"}{"$suffix"} = $pavgwins < 1 ? $importance / (1 - $pavgwins) : 0;
		}
	}
}

if (@ARGV && $ARGV[0] eq 'total')
{
	print "Totals:\n";
	foreach my $stat (sort keys %total)
	{
		foreach my $subkey (sort keys %{$total{$stat}})
		{
			print "$stat-$subkey $total{$stat}{$subkey}\n";
		}
	}
	exit 0;
}
	
print STDERR "Reading games again...\n";

open GAME, "<", "game.log";

while (my $line = <GAME>)
{
	chomp $line;
	my ($type, $gameid, @params) = split /\s+/, $line;

	if ($type eq 'result')
	{
		my ($nick, $result, $startteam, $startrole, $endteam, $endrole, $liveness, $killer) = @params;
		next unless $game_data{$gameid};
		my $player = $game_nick_masks{$gameid}{$nick};
		next unless $player;

		my $cnick = $common_nick_by_mask{$player};
		next unless $cnick;

		my $setup = $game_data{$gameid}{setup};
		my $players = $game_data{$gameid}{players};

		my $baseendteam = $endteam;
		$baseendteam =~ s/\d+$//;
		$baseendteam =~ s/-ally$//;
		
		my $key_suffix = "_${setup}_${players}_${baseendteam}";
		# print STDERR "Setup: $key_suffix\n";

		my $pointswin = $total{"pointswin"}{"$key_suffix"};
		my $pointsloss = $total{"pointsloss"}{"$key_suffix"};
		next unless $pointswin && $pointsloss;

		foreach my $s (@{$game_setups{$gameid}})
		{

			foreach my $p ("all", $players)
			{
				foreach my $t ("all", $baseendteam)
				{
					my $suffix = "_${s}_${p}_${t}";
					$nick_stats{$cnick}{scorewin}{$suffix} += $pointswin if $result eq 'win';
					$nick_stats{$cnick}{scoreloss}{$suffix} += $pointsloss if $result eq 'lose';
					if ($result eq 'draw') {
						$nick_stats{$cnick}{scorewin}{$suffix} += $pointswin * 0.5;
						$nick_stats{$cnick}{scoreloss}{$suffix} += $pointsloss * 0.5;
					}
				}
			}
		}
	}
}

close GAME;
print STDERR "Calculating scores...\n";

my $suffixresub = join('|', map { quotemeta $_ } keys %known_setups);
my $suffixre = qr/^_($suffixresub)_(\d+)_([^_]*)$/;
my $suffixresub2 = join('|', (map { quotemeta $_ } keys %known_setups), (map { quotemeta $_ } keys %timestart), "", "all");
my $suffixre2 = qr/^_($suffixresub2)_(\d+|all)_([^_]*)$/;

# Find each player's score
my $playercount;
foreach my $nick (keys %nick_stats)
{	
	next if @ARGV && lc $nick ne lc $ARGV[0];


	if (++$playercount % 10 == 0)
	{
		print STDERR ".";
	}

	my $n = $nick_stats{$nick};
	#print STDERR "Nick: $nick (" . scalar(keys(%{$n->{"games"}})) . " suffixes)\n";

	# Each player is given a number of games which they are assumed to have scored average in. This pulls the score of players who play few games towards the middle.
	my $basegames = 12;
	my $basescore = 0;
	foreach my $suffix (keys %{$n->{"games"}})
	{
		# my (undef, $setup, $players, $team) = split /_/, $suffix;
		#my ($setup, $players, $team) = $suffix =~ $suffixre2 or next;
				
		my $winpts = ($n->{scorewin}{$suffix} || 0) + ($basegames * $basescore / 50);
		my $losspts = ($n->{scoreloss}{$suffix} || 0) + ($basegames * (100 - $basescore) / 50);
		$n->{pointswin}{$suffix} = $winpts;
		$n->{pointsloss}{$suffix} = $losspts;
		$n->{score}{$suffix} = $scorescale * $winpts / ($winpts + $losspts);
	}
}
print STDERR "\n";

	# Find each player's best role
print STDERR "Calculating lucky roles...\n";

foreach my $nick (keys %nick_stats)
{	
	next if @ARGV && lc $nick ne lc $ARGV[0];

	if (++$playercount % 10 == 0)
	{
		print STDERR ".";
	}

	my $n = $nick_stats{$nick};
	my %bestrolescore;
	foreach my $suffixrole (keys %{$n->{"rolewins"}})
	{
		#next unless $n->{"rolewins"}{$suffixrole};

		$suffixrole =~ /^(_[^_]*_[^_]*_[^_]*)_(.*)$/;
		my ($suffix, $role) = ($1, $2);

		my $playerratio = $n->{"rolewins"}{$suffixrole} / $n->{"rolegames"}{$suffixrole};
		my $allratio = $total{"rolewins"}{$suffixrole} / $total{"rolegames"}{$suffixrole};
		my $rolescore = $playerratio / $allratio;

		if (!exists($bestrolescore{$suffix}) || $rolescore > $bestrolescore{$suffix})
		{
			$bestrolescore{$suffix} = $rolescore;
			$n->{bestrole}{$suffix} = $role;
		}
	}
}
print STDERR "\n";

if (@ARGV)
{
	my $nick = lc shift @ARGV;
	
	print "Individual stats for $nick:\n";
	foreach my $stat (sort keys (%{$nick_stats{$nick}}))
	{
		foreach my $subkey (sort keys %{$nick_stats{$nick}{$stat}})
		{
			print "$stat-$subkey $nick_stats{$nick}{$stat}{$subkey}\n";
		}
	}
	exit 0;
}

our @nicks = keys %nick_stats;
our @sortednicks;

# Top winners

print "Printing results...\n";

open TOPSCORE, '>', 'bestplayers.dat';

foreach my $setup ("", "all", sort(keys %timestart), sort(keys %known_setups))
{
	my $suffix = "_${setup}_all_all";
	@sortednicks = map { $nick_stats{$_}{"games"}{"${suffix}"} ? ($_) : () } @nicks;
	@sortednicks = sort { ($nick_stats{$b}{score}{$suffix} || 0) <=> ($nick_stats{$a}{score}{$suffix} || 0) ||
				lc $a cmp lc $b} @sortednicks;
				
	my $rank = 1;
	
	for (my $i = 0; $i < $maxrank && $i <= $#sortednicks; $i++)
	{
		my $nick = $sortednicks[$i];
		my $prevnick = $i ? $sortednicks[$i - 1] : "";
		print "?? $suffix\n" unless defined($nick_stats{$nick}{score}{$suffix});
		$rank = $i + 1 if !$i || $nick_stats{$nick}{score}{$suffix} < $nick_stats{$prevnick}{score}{$suffix};
		my $wins = $nick_stats{$nick}{wins}{$suffix} || 0;
		my $losses = $nick_stats{$nick}{losses}{$suffix} || 0;
		my $draws = $nick_stats{$nick}{draws}{$suffix} || 0;
		my $score = int($nick_stats{$nick}{score}{$suffix} + 0.5);
		my $cnick = $canonical_case{$nick};
		my $bestrole = $nick_stats{$nick}{bestrole}{$suffix};
		
		next if !$score;
		
		# Calculate the points to advance
		my $advscore = ($prevnick ? $nick_stats{$prevnick}{score}{$suffix} : $nick_stats{$nick}{score}{$suffix});
		my $winpts = $nick_stats{$nick}{pointswin}{$suffix};
		my $losspts = $nick_stats{$nick}{pointsloss}{$suffix};
		my $advpts = $losspts * $advscore / ($scorescale - $advscore) - $winpts;
		my $allwins = (($nick_stats{$nick}{wins}{$suffix} || 0) + 0.5 * ($nick_stats{$nick}{draws}{$suffix} || 0));
		# print STDERR "$nick has no wins for $suffix but a score of $score!\n" unless $wins;
		$allwins = 1 unless $wins;
		my $ptsperwin = $nick_stats{$nick}{scorewin}{$suffix} / $allwins;
		my $advwins = int($advpts / $ptsperwin + 0.999);
		
		print "#$rank: $cnick with $wins wins, $losses losses, and $draws draws; $advwins wins to advance\n" if $setup eq "";
		print "advscore=$advscore winpts=$winpts losspts=$losspts advpts=$advpts ptsperwin=$ptsperwin advwins=$advwins" if 0;
		# print STDERR "No bestrole for $cnick in $setup ($suffix)\n" unless $bestrole;
		$bestrole = 't' unless $bestrole;
		print TOPSCORE +($setup || "overall") . " $cnick $rank $score $wins $losses $draws $advwins $bestrole\n";
	}
}

foreach my $team (sort keys %known_teams)
{
	my $suffix = "__all_${team}";
	@sortednicks = map { $nick_stats{$_}{"games"}{"${suffix}"} ? ($_) : () } @nicks;
	@sortednicks = sort { ($nick_stats{$b}{score}{$suffix} || 0) <=> ($nick_stats{$a}{score}{$suffix} || 0) ||
				lc $a cmp lc $b} @sortednicks;
				
	my $rank = 1;
	
	for (my $i = 0; $i < $maxrank && $i <= $#sortednicks; $i++)
	{
		my $nick = $sortednicks[$i];
		my $prevnick = $i ? $sortednicks[$i - 1] : "";
		$rank = $i + 1 if !$i || $nick_stats{$nick}{score}{$suffix} < $nick_stats{$prevnick}{score}{$suffix};
		my $wins = $nick_stats{$nick}{wins}{$suffix} || 0;
		my $losses = $nick_stats{$nick}{losses}{$suffix} || 0;
		my $draws = $nick_stats{$nick}{draws}{$suffix} || 0;
		my $score = int($nick_stats{$nick}{score}{$suffix} + 0.5);
		my $cnick = $canonical_case{$nick};
		my $bestrole = $nick_stats{$nick}{bestrole}{$suffix};
		
		next if !$score;
		
		# Calculate the points to advance
		my $advscore = ($prevnick ? $nick_stats{$prevnick}{score}{$suffix} : $nick_stats{$nick}{score}{$suffix});
		my $winpts = $nick_stats{$nick}{pointswin}{$suffix};
		my $losspts = $nick_stats{$nick}{pointsloss}{$suffix};
		my $advpts = $losspts * $advscore / ($scorescale - $advscore) - $winpts;
		my $allwins = (($nick_stats{$nick}{wins}{$suffix} || 0) + 0.5 * ($nick_stats{$nick}{draws}{$suffix} || 0));
		print STDERR "$nick has no wins for $suffix but a score of $score!\n" unless $wins;
		$allwins = 1 unless $wins;
		my $ptsperwin = $nick_stats{$nick}{scorewin}{$suffix} / $allwins;
		my $advwins = int($advpts / $ptsperwin + 0.999);
		
		print STDERR "No bestrole for $cnick in $team ($suffix)\n" unless $bestrole;
		$bestrole = 't' unless $bestrole;
		print TOPSCORE +($team || "overall") . " $cnick $rank $score $wins $losses $draws $advwins $bestrole\n";
	}
}

close TOPSCORE;

# Interesting stats

open TEMPLATE, '<', "mafiastattemplate";
open RECORDS, '>', "records.dat";

sub record_type
{
	my ($stat, $subkey) = @_;

	return "action-$1" if $stat eq "stats" && $subkey =~ /^act(.*)/;
	return "target-$1" if $stat eq "stats" && $subkey =~ /^target1(.*)/;
	return "$stat-$1" if $subkey =~ /^__all_(.*)$/;
	return "$stat-$1" if $subkey =~ /^_(.+)_all_all$/;
	return $subkey if $stat eq "stats";
	return $stat;
}

while (my $line = <TEMPLATE>)
{
	chomp $line;
	my ($stat, $subkey, @output) = split /\|/, $line;
	
	next unless $stat;
	
	@sortednicks = sort { ($nick_stats{$b}{$stat}{$subkey} || 0) <=> ($nick_stats{$a}{$stat}{$subkey} || 0) } @nicks;
	
	next unless ($nick_stats{$sortednicks[0]}{$stat}{$subkey} || 0) >= 2;
#	next unless ($nick_stats{$sortednicks[0]}{$stat}{$subkey} || 0) > ($nick_stats{$sortednicks[1]}{$stat}{$subkey} || 0);
	
	for ($i = 0; $i <= $#output && ($nick_stats{$sortednicks[$i]}{$stat}{$subkey} || 0) >= 2; $i++)
	{
		my $nick = $sortednicks[$i];
		my $value = $nick_stats{$nick}{$stat}{$subkey};
		my $tribute = "[" . record_type($stat, $subkey) . "] " . $output[$i];
		my $cnick = $canonical_case{$nick};

#		last if $i < $#sortednicks && ($nick_stats{$sortednicks[$i]}{$stat}{$subkey} || 0) <= ($nick_stats{$sortednicks[$i + 1]}{$stat}{$subkey} || 0);
		
		my $gamepercent = sprintf "%i%%", 100 * $nick_stats{$nick}{$stat}{$subkey} / $nick_stats{$nick}{games}{__all_all};
		my $gameratio = sprintf "%.1f", $nick_stats{$nick}{games}{__all_all} / $nick_stats{$nick}{$stat}{$subkey};
		
		$tribute =~ s/PLAYER/$cnick/s;
		$tribute =~ s/VALUE/$value/s;
		$tribute =~ s/GAME%/$gamepercent/s;
		$tribute =~ s/RATIO/$gameratio/s;
		
		print RECORDS "$tribute ^ ";
	}
	print RECORDS "\n";
}

close TEMPLATE;
close RECORDS;
