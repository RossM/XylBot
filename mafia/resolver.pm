package mafia;

use strict;
use warnings;
no warnings 'redefine', 'qw';
use sort 'stable';
use Carp qw(cluck);

our ($phase, $day);
our (@players, %players, %player_masks, %players_by_mask, @alive, @moderators, %moderators);
our (%action_config, %group_data, %player_data);
our (@action_queue, @resolved_actions);

our ($resolvemode);

our (%messages);

our ($resolving, $lynching);

sub check_bodyguard {
	my ($player, $target, $dokill) = @_;

	my $guard = get_status($target, 'guarded_by');

	if ($guard && $dokill)
	{
		my $guardmode = get_status($guard, 'guard') || 'ab';

		if ($guardmode =~ /b/ && alive($guard))
		{
			my $msg = $messages{death}{killed} . '.';
			$msg =~ s/#PLAYER1/$guard/;
			$msg =~ s/#TEXT1//;
			announce $msg;
			kill_player($guard, $player);
		}

		if ($guardmode =~ /a/ && alive($player))
		{
			my $msg = $messages{death}{killed} . '.';
			$msg =~ s/#PLAYER1/$player/;
			$msg =~ s/#TEXT1//;
			announce $msg;
			kill_player($player, $guard);
		}
	}
	
	return $guard;
}

sub immune_to_action {
	my ($target, $action, $reduce, $type) = @_;
	
	$type = $action_config{$action}{type} || "nonkill" unless $type;

	# Locked actions are unaffected by immunity
	return if $type =~ /\bnoimmune\b/;
	
	my @shields = ($action, 'all');
	push @shields, 'nonkill' unless $type =~ /\bkill\b|\bsuper\b|\bresurrect\b/;
	push @shields, 'kill' if $type =~ /\bkill\b/;
	push @shields, 'resurrect' if $type =~ /\bresurrect\b/;

	foreach my $shield (@shields)
	{
		my $pct = get_status($target, "resist$shield") || 0;
		if ($reduce && $pct > 0 && rand(100) < $pct) {
			return $shield;
		}
	}
	
	foreach my $shield (@shields)
	{
		if (get_status($target, "immune$shield"))
		{
			reduce_status($target, "immune$shield") if $reduce;
			return $shield;
		}
	}
	return "";
}

# Check if a player has a shielding action queued
sub is_shield_queued {
	foreach my $item (@action_queue)
	{
		my $action = $item->{action};
		
		return 1 if ($action_config{$action}{resolvedelay} || "") eq 'shield';
	}
	return 0;
}		

sub action_failed {
	my $item = shift;
	
	my $player = $item->{player};
	my $action = $item->{action};
	my $type = $item->{type} || $action_config{$action}{type} || "nonkill";

	if ($type =~ /\blinked\b/)
	{
		set_temp_status($player, 'linkfailed', 1);
	}
}

sub resolve_one_action {
	my $item = shift;
	
	my $player = $item->{player};
	my $action = $item->{action};
	my $longaction = $item->{longaction};
	my $group = $item->{group};
	my @targets = @{$item->{targets}};
	my $target = $item->{target};
	my $status = $item->{status};
	my $type = $item->{type} || $action_config{$action}{type} || "nonkill";
	
	my $desc = "$player $action" . ($status ? ( length($status) <= 15 ? " ($status)" : " (...)") : "") . " [$type] @targets" . 
		($item->{target} ne ($targets[0] || "") ? " (" . $item->{target} . ")" : "");
	my $desc2 = "$player $action" . (@targets ? " @targets" : "");
	
	my $checkalive = $action_config{$action}{checkalive} || "";
	
	if ($group && $group_data{$group}{has_used_action} && $group_data{$group}{has_used_action} ne $player)
	{
		return;
	}
	$group_data{$group}{has_used_action} = $player if $group;
	
	return if ($targets[0] || "") eq 'none';

	my $actdesc = ($type =~ /\bauto\b/ ? "Automatic action" : "Action");
	my $verbosity = 2;
	$verbosity = 1 if $type =~ /\bauto\b/ && $type =~ /\bnoblock\b/;
	
	# Bussing affects everything except target-locked actions
	if ($type !~ /\blocked\b/)
	{
		for (my $i = 0; $i < @targets; $i++)
		{
			my $bussee = get_status($targets[$i], "bussed");
			next unless $bussee;

			# Don't bus self-targeted actions
			if ($targets[$i] eq $player)
			{
				set_temp_status($targets[$i], "bussed2", "");
				next;
			}
	
			# Set a status so that inspect abilities can lie about the target
			set_temp_status($bussee, "bussed2", $targets[$i]);
	
			mod_notice("$target was bussed with $bussee");

			# Switch target
			$target = $bussee if $target eq $targets[$i];
			$targets[$i] = $bussee;
		}
	}
	
	push @resolved_actions, $item;
	
	# Check for roleblock
	if (get_status($player, "blocked") && $type !~ /\bnoblock\b/)
	{
		my $msg = $messages{action}{block};
		
		if (!get_status($player, "recieved_blocked_message"))
		{
			increase_temp_status($player, "recieved_blocked_message");
			enqueue_message($player, $msg);
		}
		::bot_log "RESOLVE BLOCKED $desc\n";
		mod_notice("$actdesc failed ($player was blocked): $desc2") if $verbosity >= 2;
		action_failed($item);
		return;
	}

	# Check for disable
	if (get_status($player, "disabled") && $type =~ /\bauto\b/)
	{
		::bot_log "RESOLVE DISABLED $desc\n";
		mod_notice("$actdesc failed ($player is disabled): $desc2") if $verbosity >= 2;
		action_failed($item);
		return;
	}
	
	# Check for failed link
	if ($type =~ /\blinked\b/ && get_status($player, 'linkfailed'))
	{
		::bot_log "RESOLVE LINKFAIL $desc\n";
		mod_notice("$actdesc failed (a linked action failed): $desc2") if $verbosity >= 2;
		return;
	}
	
	$item->{resolved} = 1;

	# Check for reflect/hidden on the declared target
	# Unblockable (triggered) actions do not have a declared target, so don't let them be reflected/hidden
	if ($target && $type !~ /\bnoblock\b/)
	{
		# Check for reflective target
		if ($type !~ /\bnoreflect\b/ && get_status($target, 'reflect') && get_status($target, 'reflect_by') ne $player)
		{
			reduce_status($target, 'reflect', 1);
			::bot_log "REFLECT $desc\n";
			mod_notice("$actdesc reflected off $target: $desc2") if $verbosity >= 2;
			for (my $i = 0; $i < @targets; $i++)
			{
				$item->{targets}[$i] = $targets[$i] = $player if $targets[$i] eq $target;
			}
			$target = $player;
		}
		
		# Check for hidden status, but don't block other subactions by the same player who caused the hide
		# Also, hidden status never prevents actions targeting the player themself (if they got reflected, for instance)
		if (get_status($target, 'hidden') && get_status($target, 'hidden_by') ne $player && $target ne $player)
		{
			reduce_status($target, 'hidden', 1);
			::bot_log "RESOLVE HIDDEN $desc\n";
			mod_notice("$actdesc failed ($target is hidden): $desc2") if $verbosity >= 2;
			action_failed($item);
			return;
		}
	}
	
	# Check for protect/guard, and for if the actual target is dead
	my $realtargets = $action_config{$action}{realtargets} || scalar(@{$action_config{$action}{targets} || []});
	$realtargets = scalar(@targets) if $realtargets > scalar(@targets);
	foreach my $target (@targets[0 .. $realtargets - 1])
	{	
		my $guard;
		if ($type =~ /\bkill\b/ && ($guard = check_bodyguard($player, $target, 1)))
		{
			::bot_log "RESOLVE GUARDED $guard : $desc\n";
			mod_notice("$actdesc failed ($target was guarded by $guard): $desc2") if $verbosity >= 2;
			action_failed($item);
			return;
		}
	
		if (my $shield = immune_to_action($target, $action, 1, $type))
		{
			::bot_log "RESOLVE IMMUNE $shield : $desc\n";
			mod_notice("$actdesc failed ($target is immune to $shield actions): $desc2") if $verbosity >= 2;
			action_failed($item);
			return;
		}
		
		if ($checkalive =~ /target/ && $type !~ /resurrect/ && !alive($target))
		{
			::bot_log "RESOLVE DEAD $desc\n";
			mod_notice("$actdesc failed (the target $target is dead): $desc2") if $verbosity >= 2;
			action_failed($item);
			return;
		}
	}

	if ($checkalive =~ /player/ && !alive($player))
	{
		::bot_log "RESOLVE DEAD $desc\n";
		mod_notice("$actdesc failed (the user $player is dead): $desc2") if $verbosity >= 2;
		action_failed($item);
		return;
	}

	# Note the "current action"
	$player_data{$player}{cur_action} = $longaction;
	$player_data{$player}{cur_action_type} = $type;
	
	::bot_log "RESOLVE OK $desc\n";
	mod_notice("$actdesc resolved: $desc2") if $verbosity >= 1;

	if (!$mafia::{"action_$action"}) 
	{
		notice($player, "Oops! Your action '$action' can't be resolved because it doesn't have a handler. Please report this problem to " . $::owner . ".");
		mod_notice("($player) Oops! Your action '$action' can't be resolved because it doesn't have a handler. Please report this problem to " . $::owner . ".");
		notice($player, "Bug details: role " . get_player_role($player), ", action $longaction, part $action, type $type, status $status, targets @targets");
		mod_notice($player, "Bug details: role " . get_player_role($player), ", action $longaction, part $action, type $type, status $status, targets @targets");
		return;
	}
	
	# Eval for error trapping
	eval {
		# Automatically invoke the proper handler
		&{$mafia::{"action_$action"}}($player, $status, @targets);
	};
	if ($@)
	{
		::bot_log "ERROR resolving $desc: $@";
		my $err = $@;
		$err =~ s/\n$//;
		notice($player, "Oops! Due to a bug, your action may have failed to resolve. Please report this problem to " . $::owner .  ".");
		notice($player, "The error was: $err");
		mod_notice("The following error was encountered while executing the action '$action': $err");
		notice($player, "Bug details: role " . get_player_role($player), ", action $longaction, part $action, type $type, status $status, targets @targets");
		mod_notice($player, "Bug details: role " . get_player_role($player), ", action $longaction, part $action, type $type, status $status, targets @targets");
	}
}

sub blockable_action_in_queue {
	my ($player) = @_;

	foreach my $action (@action_queue)
	{
		next if $action->{type} =~ /\bnoblock\b/;
		return 1 if $action->{player} eq $player;
	}

	return 0;
}

sub paradox_resolver {
    resolve_iteration:
	while (1)
	{
		my %delayed_players = ();
		my %shielded_by = ();
		
		# Find all players who might be affected by special actions
		# Special (aka resolvedelay) actions are those that might affect the target of
		# another action, or prevent it from happening.
		# Actions that create a shield are not special; they change the result of the
		# action, but don't actually block it. The exception is actions that can protect
		# against other special actions (such as immuneall and reflect).
		# There are three types of resolvedelay:
		#  'normal' means that targets of the action are delayed.
		#  'redirect' is like 'normal' but has special interactions with shields.
		#  'shield' means that other players targeting the target of the action are delayed.
		#  'immediate' means that the action should occur immediately when it is at the front of the queue.
		# In the case of multiple shields, the first one in the queue is not delayed.
		# WARNING: This will cause the results to be dependent on the order actions are submitted
		# if more than one reflecter picks the same target.

		# First step: If the first item in the queue is 'immediate', resolve it.
		if (@action_queue > 0 && ($action_config{$action_queue[0]{action}}{resolvedelay} || "") eq 'immediate')
		{
			# Handle retributive action
			next resolve_iteration if handle_retributive_actions($action_queue[0]);
			
			my $item = shift @action_queue;
			resolve_one_action($item);
			next resolve_iteration;
		}
		
		# Second step: Find all players affected by shielding actions.
		foreach my $item (@action_queue)
		{
			my $player = $item->{player};
			my $action = $item->{action};
			my @targets = @{$item->{targets}};
			my $resolvedelay = $action_config{$action}{resolvedelay} || "";
			
			my $shield_queued = is_shield_queued();
			
			if ($resolvedelay =~ /^shield/)
			{
				for my $target (@targets)
				{
					next if $shielded_by{$target};
					$shielded_by{$target} = $player;
				}
			}
			
			# Redirects targeting a reflecter can cause the new target to be shielded
			# This can be made arbitrarily hideous by the presence of other redirecters
			# redirecting this redirecter, so if any shielding action is in the queue we
			# assume that a redirection may cause a shield.
			if ($resolvedelay =~ /^redirect/ && $shield_queued)
			{
				my $target = $targets[1];
					
				next if $shielded_by{$target};
				$shielded_by{$target} = $player;
			}
		}
		
		# Third step: Mark as delayed all players affected by delaying actions, or with
		# actions targeting a shielded player. Shielded players are still marked as being
		# delayed, because the shielder might be blocked.
		foreach my $item (@action_queue)
		{
			my $player = $item->{player};
			my $action = $item->{action};
			my @targets = @{$item->{targets}};
			my $type = $item->{type};
			my $resolvedelay = $action_config{$action}{resolvedelay} || "";
			
			# Acting on someone who did nothing can't block you...
			next if $resolvedelay =~ /^redirect/ && !blockable_action_in_queue($targets[0]);
					
			if ($resolvedelay =~ /^normal|^redirect/)
			{
				for my $target (@targets)
				{
					# Check for a shield
					if ($shielded_by{$target} && $shielded_by{$target} ne $player)
					{
						$delayed_players{$player}++;
					}
					
					# Acting on yourself can't block you
					next if $target eq $player;

					# Don't block if the player is immune or reflective
					next if get_status($target, 'reflect');
					next if get_status($target, 'hidden');
					next if immune_to_action($target, $action, 0, $type);
					next if check_bodyguard($player, $target, 0);
					
					$delayed_players{$target}++;
				}
			}
		}
		
		# If there are no delayed players, we're done with paradox resolution and go on to normal resolution.
		# last resolve_iteration if not %delayed_players;
		
		# Fourth step: Resolve special actions by players who can't be affected
		foreach my $item (@action_queue)
		{
			my $player = $item->{player};
			my $action = $item->{action};
			
			if ($action_config{$action}{resolvedelay} && !$delayed_players{$player})
			{
				# Handle retributive action
				next resolve_iteration if handle_retributive_actions($item);

				my $saveitem = $item;
				@action_queue = grep { $_ != $item } @action_queue;
				resolve_one_action($saveitem);
				
				# We resolve one action and then restart.
				# This is because that action might have created new actions (e.g., if it was copy).
				next resolve_iteration;
			}
		}
		
		# Fifth step: Resolve the first action, even if it is by a delayed player.
		foreach my $item (@action_queue)
		{
			my $player = $item->{player};
			my $action = $item->{action};
			
			if ($action_config{$action}{resolvedelay})
			{
				# Handle retributive action
				next resolve_iteration if handle_retributive_actions($item);

				my $saveitem = $item;
				@action_queue = grep { $_ != $item } @action_queue;
				if ($item->{player} eq $action_queue[0]{player})
				{
					;
				}
				elsif (action_priority($item) >= action_priority($action_queue[0]))
				{
					::bot_log "PARADOX BREAK (order)\n";
					mod_notice("Oops! It seems those silly players have created a serious paradox, I have two conflicting ${action}s to resolve. Oh well, let's forge ahead by resolving ${player}'s action first.");
				}
				else
				{
					::bot_log "PARADOX BREAK (priority)\n";
					mod_notice("There could be a paradox here, but $action beats $action_queue[0]{action} so I'll resolve ${player}'s action first.");
				}
				resolve_one_action($saveitem);
				
				# We resolve one action and then restart.
				# This is because that action might have created new actions (e.g., if it was copy).
				next resolve_iteration;
			}
		}
		
		# If no actions were resolved, we have a paradox. All remaining special actions are removed from the queue.
		# This does not count as a block, and no message is sent.
		my @new_action_queue;
		foreach my $item (@action_queue)
		{
			my $player = $item->{player};
			my $action = $item->{action};
			my @targets = @{$item->{targets}};
			
			if ($action_config{$action}{resolvedelay})
			{
				::bot_log "PARADOX $player $action @targets\n";
				mod_notice("There's a paradox here I can't resolve. Dropping ${player}'s $action on the floor and moving on.");
			}
			else
			{
				push @new_action_queue, $item;
			}
		}
		@action_queue = @new_action_queue;
		last resolve_iteration;
	}
}

sub action_priority {
	my ($item) = @_;
	return $action_config{$item->{action}}{priority};
}

sub sort_actions {
	@action_queue = sort { action_priority($a) <=> action_priority($b)} @action_queue;
}

sub handle_retributive_actions {
	my ($action) = @_;

	my $didsomething = 0;
	our %did_trigger;

	#my @targets = $action->{target} ? ($action->{target}) : ();
	my @targets = @{$action->{targets}};
	foreach my $target (@targets)
	{
		next if $action->{type} =~ /\bnotrigger\b/;

		# Don't trigger if we're hidden from this action
		next if get_status($target, 'hidden');
		
		next if $did_trigger{$target}{$action->{player}};
		$did_trigger{$target}{$action->{player}} = 1;
		
		my $result = get_status($target, 'ontarget');
		handle_trigger($target, $result, $action->{longaction}, $action->{player});
		$didsomething = 1 if $result;

		$result = get_status($target, "ontarget:" . $action->{action});
		handle_trigger($target, $result, $action->{longaction}, $action->{player});
		$didsomething = 1 if $result;
	}

	sort_actions() if $didsomething;
	return $didsomething;
}

sub resolve_actions {
	# @resolved_actions = ();
	$resolving = 1;
	our %did_trigger = ();

	my %action_used;

	foreach my $action (@action_queue) {
		$action_used{$action->{player}} = 1;
	}

	::bot_log "BEGIN RESOLUTION $phase $day\n";
	
	# Mark all actions as used
	foreach my $player (@players)
	{
		my $action = $player_data{$player}{phase_action};
		
		# Enqueue a 'none' action so that replacenone works properly
		if ($phase eq 'night' && !$action && alive($player))
		{
			enqueue_action($player, "", "none", "", "");
		}
		
		next if !$action || $action eq 'none';
	}
	
	# Add a target to randomize actions, to help the resolver be sane
	foreach my $action (@action_queue)
	{
		push @{$action->{targets}}, $alive[rand @alive] if $action->{action} eq 'randomize';
	}

	# Sort the action list
	sort_actions();
	
	# XXX There are potential complications with special resolving group actions.
	
	if ($resolvemode eq 'paradox')
	{
		paradox_resolver();
	}

	# Handle retributive actions
	my @save_queue = @action_queue;
	foreach my $action (@save_queue)
	{
		handle_retributive_actions($action);
	}
	
	# Resolve the rest of the action queue in order
    	while (@action_queue)
	{
		my $item = shift @action_queue;
		resolve_one_action($item);
	}
	
	$resolving = 0;

	# Clear linkfail
	foreach my $player (@players) {
		set_temp_status($player, 'linkfailed', "");
	}
	
	flush_message_queue();
	check_winners() unless $lynching;
	update_voiced_players();
}


