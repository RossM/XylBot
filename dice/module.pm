package dice;

use strict;
use warnings;
no warnings 'redefine';

our @rolls;
our @fixeddice;

our %aliases;

# Roll $dice dice of $sides sides each, and return the total.
# If a third argument is supplied, total only that many of the highest dice.
sub roll {
	my ($dice, $sides, $best) = @_;
	my $total = 0;
	
	$dice = 1 if $dice < 1;
	$sides = 6 if $sides < 1;
	$best = $dice if !defined $best;
	
	my @cur_rolls;
	
	for (my $i = 0; $i < $dice; $i++)
	{
		my $roll = int(rand($sides))+1;
		
		# Fix the result. This is not recommended.
		if (@fixeddice)
		{
			my $fixedroll = shift @fixeddice;
			my $orig_fixedroll = $fixedroll;
			
			push @fixeddice, $fixedroll if $fixedroll =~ /\*$/;
			
			if ($fixedroll =~ s/^(\d+)%:// && int(rand(100)) < $1)
			{
				goto dontfix;
			}
			if ($fixedroll =~ s/^d(\d+):// && $sides != $1)
			{
				goto dontfix;
			}
			if ($fixedroll =~ s/^(\S*):// && lc $1 ne lc $::cur_fromnick)
			{
				unshift @fixeddice, $orig_fixedroll unless $orig_fixedroll =~ /\*$/;
				goto dontfix;
			}
			
			if ($fixedroll =~ /^(\d+)/)
			{
				$roll = $1;
			}
			elsif ($fixedroll =~ /^\+(\d+)/)
			{
				$roll += $1;
			}
			elsif ($fixedroll =~ /^\-(\d+)/)
			{
				$roll -= $1;
			}
			elsif ($fixedroll =~ /^>(\d*)/)
			{
				my $extra = $1 || 1;
				for (my $j = 0; $j < $extra; $j++)
				{
					my $newroll = int(rand($sides))+1;
					$roll = $newroll if $roll < $newroll;
				}
			}
			elsif ($fixedroll =~ /^<(\d*)/)
			{
				my $extra = $1 || 1;
				for (my $j = 0; $j < $extra; $j++)
				{
					my $newroll = int(rand($sides))+1;
					$roll = $newroll if $roll > $newroll;
				}
			}
			
			$roll = $sides if $roll > $sides; # In case of screwy fixed dice
			$roll = 1 if $roll < 1;
		}
	    dontfix:
		
		push @rolls, $roll;
		push @cur_rolls, $roll;
	}
	
	@cur_rolls = sort {$b <=> $a} @cur_rolls;
	
	for (my $i = 0; $i < $best; $i++)
	{
		$total += $cur_rolls[$i];
	}
	
	return $total;
}

sub table_roll {
	my ($table, $dice, $sides, $recurse, $extra) = @_;

	$recurse = 1 if !defined($recurse);

	if ($recurse > 10) {
		return "Recursion too deep at '$table'";
	}

	my $index = roll($dice, $sides);
	my $file;

	if (-e "dice/tables/$table") {
		$file = "dice/tables/$table";
	}
	else {
		return "Bad table '$table'";
	}

	my $result = "Missing entry $index for '$table'";

	open TABLE, '<', $file;

	while (my $line = <TABLE>) {
		chomp $line;
		if ($line =~ /^(\d+)(?:,(\d+))? (.*)$/) {
			my $min = $1;
			my $max = defined($2) ? $2 : $1;
			if ($index >= $min && $index <= $max) {
				$result = $3;
				last;
			}
		}
	}

	close TABLE;

	$result =~ s/\[\s*(?:([^]]*?)\s*:)?\s*(\d*)d(\d+)\s*(?:\s*x\s*(\d+))?(?:\s*:\s*([^]]+))?\s*\]/
		my $mult = defined($4) ? $4 : 1;
		my $newtable = $extra ? "$1-$extra" : $1;
		$1 ? table_roll($newtable, $2, $3, $recurse + 1, $5) : roll($2, $3) * $mult/eg;

	return $result;
}

# Implement the !roll command.
#
# The arguments can contain pretty much anything. Regular expressions are used to check for modifiers.
# The basic dice roll should be of the form dN, Nd, NdN, NdN+N, NdN*N, or similar.
#
# If the arguments include 'best' or 'best N', only the N best (1 by default) dice are totalled and
# displayed.
#
# If 'dice' is supplied, the individual die rolls made to find the result are printed. If more than
# 20 dice were rolled, only the first 20 are printed.
#
# If 'N times' is supplied, for N <= 4, the entire roll is repeated the given number of times. If
# 'sum' is also included, a grand total is included afterwards.
#
# If 'crit' is supplied, we assume this is a weapon attack, with 20 indicating a critical threat;
# if 'crit N' is supplied N or greater is a critical threat. If the 'autoconfirm' argument is
# supplied we automatically check whether the threat is a critical hit or not.
#
# If 'vs N', 'dc N', or 'ac N' is supplied we check the result against the given number and print
# an indication of success or failure. If 'crit' is supplied or 'ac N' is used, we assume a weapon
# attack. If 'save' is supplied, we assume a saving throw. If neither is supplied and 'dc N' is
# used, the degree of success or failure is printed. For weapon attacks and saving throws, 20 is
# an automatic success and 1 is an automatic failure (assuming d20s).
#
# If 'dam' or 'dr' is supplied we give a minimum result of 1 before dr.
#
# If 'dr N' or 'res N' is supplied we reduce the final result, but not to below zero. The amount
# of reduction is displayed.
#
# Users can define aliases, which are simple textual substitutions on the dice string. For example
# an alias of 'reflex' to 'save 1d20+3' causes 'roll reflex+2' to roll 1d20+5 as a saving throw.
# Aliases are specific to a nickname, and are persistent even if the bot is stopped and restarted.
# All current aliases are stored in './dice/aliases'.
#
# The random number generator used can be fixed for testing purposes. This is not recommended.
# Fixing the RNG is a privileged command.
sub command_roll {
	my ($connection, $command, $forum, $from, $to, $args) = @_;
	
	my $player = $from;
	$player =~ s/!.*//;
	$player = lc $player;
	
	if ($args =~ /for\s*(\S+)/)
	{
		my $newplayer = lc $1;
		$player = $newplayer if exists $aliases{$newplayer};
	}
	
	foreach my $player2 ($player, ":global:") {
		foreach my $alias (keys %{$aliases{$player2}})
		{
			my $text = $aliases{$player2}{$alias};
			my $qalias = quotemeta $alias;
			$args =~ s/\b$qalias\b/($text)/gi;
		}
	}

	if (@fixeddice)
	{
		::bot_log "FIXED ";
	}
	::bot_log "ROLL $args\n";

	my @oldfixeddice;
	my $doshuffle = 0;

	if ($args =~ /\bshuffle:(\d+),(\d+)/)
	{
		@oldfixeddice = @fixeddice;
		@fixeddice = ();
		$doshuffle = 1;
		for (my $roll = 1; $roll <= $2; $roll++) {
			for (my $times = 1; $times <= $1; $times++) {
				push @fixeddice, $roll;
			}
		}
		for my $i (0..$#fixeddice) {
			my $i2 = int(rand($#fixeddice + 1 - $i)) + $i;
			my $temp = $fixeddice[$i];
			$fixeddice[$i] = $fixeddice[$i2];
			$fixeddice[$i2] = $temp;
		}
	}

	my @rollstr = split /\s+(?:and|plus)\s+/, $args;
	my $grand_total = 0;
	my $num_rolls = 0;
	
	my $isdamage = ($args =~ /\bdam(?:a|\b)/i || $args =~ /\bdr\s*\d+/i);
	my $total_resistance = 0;
	if ($args =~ /\b(?:dr|res\w*)\s*(\d+)/i)
	{
		$total_resistance = $1;
	}
			
	foreach my $rollstr (@rollstr)
	{
		my $times = 1;
		
		if ($rollstr =~ s/(\d+)\s*ti\w*//i)
		{
			$times = $1;
			if ($times > 6)
			{
				$times = 6;
			}
		}
			
		if ($rollstr =~ /\[\s*([^]]*?)\s*:\s*(\d*)d(\d+|%)\s*\]/) {
			my ($table, $dice, $sides) = ($1, $2, $3);
			for (my $loop = 0; $loop < $times && $num_rolls < 6; $loop++)
			{		
				$num_rolls++;
				::say_or_notice("Result: " . table_roll($table, $dice, $sides));
			}
				
		}
		elsif ($rollstr =~ /(\d+|\b)d(\d+|\%|\b)(?:\s*[x*]\s*(\d+))?/)
		{
			my $dice = ($1 ne "" ? $1 : 1);
			my $sides = ($2 eq '%' ? 100 : $2 ne "" ? $2 : 6);
			my $mult = defined $3 ? $3 : 1;
			my $bonus = 0;
			my $best = $dice;
			my $nohit = 0;
	
			while ($rollstr =~ s/([+-])\s*(\d+)/#/)
			{
				$bonus += ($1 eq '-' ? -$2 : $2);
			}
			
			if ($rollstr =~ /\bbest\b\s*(\d+)?/)
			{
				$best = $1 || 1;
			}
			
			if ($dice > 1000)
			{
				::say_or_notice("Too many dice! No more than 1000, please.");
				goto done;
			}
	
			for (my $loop = 0; $loop < $times && $num_rolls < 6; $loop++)
			{		
				@rolls = ();
				$num_rolls++;
				
				my $target = undef;
				my $increasedfrom;
				my $resistance = 0;
				
				my $total = roll($dice, $sides, $best) * $mult + $bonus;
	
				if ($isdamage && $total < 1)
				{
					$increasedfrom = $total;
					$total = 1;
				}
				else
				{
					$increasedfrom = undef;
				}
	
				# Apply damage resistance
				if ($total_resistance > 0)
				{
					$resistance = $total_resistance;
					$resistance = $total if $resistance > $total;
					$resistance = 0 if $resistance < 0;
					$total -= $resistance;
					$total_resistance -= $resistance;
				}
				
				$grand_total += $total;
				
				my $result = "Result of " . ($best == $dice ? "" : "best ${best} of ") . "${dice}d${sides}" . ($mult != 1 ? "*$mult" : "") . 
					($bonus ? sprintf("%+i", $bonus) : "") . ($doshuffle ? " (shuffled)" : "") . ": $total";
	
				my $is_critical = 0;
				
				$result .= " damage" if $isdamage;
				
				# Check for possible critical threat
				if ($rollstr =~ /\bcr\w*(?:\s*=?\s*(\d+))?/i)
				{
					my $critbase = $1 || $sides;
					if ($rolls[0] >= $critbase)
					{
						$is_critical = 1;
					}
				}
				
				# Check for target number
				if ($rollstr =~ /\b(vs|dc|ac)\s*(\d+)/i)
				{
					$target = $2;
					my $type = $1;
					my $isattroll = ($type =~ /ac/i || $rollstr =~ /\bcr/);
					
					$is_critical = 1 if $isattroll && $rolls[0] >= $sides;
					
					$result .= " (";
					
					my $autohit = ($isattroll || $rollstr =~ /\bsave\b/i);
					my $hitmsg = $isattroll ? ($is_critical ? "critical threat!" : "hit") : "success";
					my $missmsg = $isattroll ? "miss" : "failure";
					
					if ($autohit && $rolls[0] >= $sides)
					{
						$result .= "automatic " . ($is_critical ? "hit, " : "") . $hitmsg;
					}
					elsif ($autohit && $rolls[0] <= 1)
					{
						$result .= "automatic " . $missmsg;
						$nohit = 1;
					}
					elsif ($total >= $target)
					{
						$result .= $hitmsg;
					}
					else
					{
						$result .= $missmsg;
						$nohit = 1;
					}
					
					if ($type =~ /dc/i && !$autohit)
					{
						my $diff = abs($total - $target);
						$result .= " by $diff";
					}
					
					$result .= ")";
				}
				
				# Check for critical threat or critical hit
				if ($is_critical && !$nohit)
				{
					if ($rollstr =~ /\bautoconfirm\b/ && defined($target))
					{
						my $confirmtotal = roll($dice, $sides, $best) * $mult + $bonus;
						
						if ($confirmtotal >= $sides || $confirmtotal >= $target)
						{
							$result .= ". Result of critical confirm roll: $confirmtotal. Critical hit!";
						}
						else
						{
							$result .= ". Result of critical confirm roll: $confirmtotal, not confirmed";
						}
					}
					elsif (!defined($target))
					{
						$result .= ". Critical threat!"
					}
				}
				
				# Display damage resisted
				if ($resistance)
				{
					$result .= " ($resistance resisted)";
				}
				
				# Display increase to minimum
				if (defined $increasedfrom)
				{
					$result .= " (increased from $increasedfrom)";
				}
				
				# Display actual dice
				if ($args =~ /\bdice\b/i)
				{
					if (scalar @rolls <= 20)
					{
						$result .= ', dice were ' . join(' ', @rolls);
					}
					else
					{
						$result .= ', dice were ' . join(' ', @rolls[0..19]) . " ...";
					}
				}
		
				::say_or_notice($result);
				
				::bot_log "DICE @rolls\n";
			}
			
		}
	}
	
	if ($num_rolls > 1 && ($isdamage || $args =~ /\b(?:sum|total|plus)\b/i))
	{
		::say_or_notice("Grand total: $grand_total" . ($isdamage ? " damage" : ""));
	}
	
	if ($num_rolls == 0)
	{
		::say_or_notice("Oops! You didn't tell me what to roll...");
	}

done:
	if ($doshuffle) {
		@fixeddice = @oldfixeddice;
	}

	return 1;
}

sub load_aliases {
	my $line;

	for my $file ("dice/aliases", "dice/globalaliases") {
		open ALIASES, "<", $file;
	
		while ($line = <ALIASES>)
		{
			$line =~ s/\s*$//;
		
			my ($player, $alias, $text) = split(/\s+/, $line, 3);
		
			$aliases{$player}{$alias} = $text;
		}
	
		close ALIASES;
	}
	
	::bot_log "Loaded roll aliases\n";
}

sub save_aliases {
	open ALIASES, ">", "dice/aliases";
	
	foreach my $player (keys %aliases)
	{
		foreach my $alias (keys %{$aliases{$player}})
		{
			my $text = $aliases{$player}{$alias};
			print ALIASES "$player $alias $text\n";
		}
	}
	
	close ALIASES;
}
	
sub command_setroll {
	my ($connection, $command, $forum, $from, $to, $args) = @_;

	my $player = $from;
	$player =~ s/!.*//;
	$player = lc $player;

	my ($alias, $text) = split(/\s+/, $args, 2);
	
	if (defined($text))
	{
		$aliases{$player}{$alias} = $text;
		::notice("Alias set.");
	}
	else
	{
		delete $aliases{$player}{$alias};
		::notice("Alias removed.");
	}
	
	save_aliases();
	return 1;
}	

# Fix rolls.
# Syntax: fixroll roll1 roll2 roll3 ...
# For each roll:
#   NN = give value NN
#  +NN = increase value by NN
#  -NN = decrease value by NN
#   >N = roll N extra times, take highest
#   <N = roll N extra times, take lowest
# If a fix is preceded by dNN: it will only fix the result for NN sided dice.
# If a fix is preceded by nick: it will only fix the result for that player.
# If a fix is preceded by NN%: it will only fix the result NN% of the time.
# If a fix is followed by * it will be repeated until fixroll is used again.
sub command_fixroll {
	my ($connection, $command, $forum, $from, $to, $args, $level) = @_;

	my $player = $from;
	$player =~ s/!.*//;
	$player = lc $player;

	# return unless $player eq lc $::owner;
	return unless $level >= 500;
	
	@fixeddice = split /\s+/, $args;
	
	::notice("Fixed dice set.");
	return 1;
}

sub add_commands  {
	::add_command_any "roll", \&command_roll, "roll <dice> [vs [ac|dc] N [save]] [crit N [autoconfirm]] [dr N]: Rolls dice. " .
		"The 'vs' option displays success or failure. " .
		"The 'save' option automatically fails on a 1 and succeeds on a 20. " .
		"The 'crit' option checks for critical hits. " .
		"The 'autoconfirm' option automatically checks for confirmation for criticals. " .
		"The 'dr' option reduces the result. " .
		"See also setroll.";
	::add_command_any "setroll", \&command_setroll, "setroll <alias> [text]: Creates an alias for the roll command, which can be used as a shorthand. If no " .
		"text is provided, clears an existing alias. Aliases are nick-specific.";
	::add_command_private "fixroll", \&command_fixroll, "fixroll [rol11] [roll2] ...: This command does not exist. fnord.";
}

load_aliases();

1;
