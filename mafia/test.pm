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
our (%players, %moderators, %player_masks, %players_by_mask);
our (@action_queue, @resolved_actions);
our ($phases_without_kill);
our ($day, $phase);
our ($last_votecount_time);
our (@timed_action_timers);
our ($signuptimer);
our (%reset_voters, %stop_voters);
our ($cur_setup);
our ($mafia_cmd, $mafiachannel, $resolvemode, $messagemode);
our (%action_config);
our ($game_active, $line_counter, $lynch_votes, $nokill_phase, $nonrandom_assignment);
our ($gameid, $gamelogfile);

our @message_queue;

our $just_testing;
our @test_scheduled_events;
our @test_winners;
our $test_schedule_croak;
our $test_noflush;

sub flush_scheduled_events {
	my $count++;
	while (@test_scheduled_events)
	{	
		$test_schedule_croak = ($count >= 100);

		my $event = shift @test_scheduled_events;
		&$event;

		return if ++$count > 1000;
	}
	$test_schedule_croak = 0;
}

sub construct_test_setup {
	my (@args) = @_;

	$setup_config{test}{roles} = [reverse @args];
	$setup_config{test}{players} = scalar (@args);
}

sub launch_test_setup {
	my ($nick, @args) = @_;

	construct_test_setup(@args);
	start_test_setup($nick);
	flush_scheduled_events();
	$test_noflush = 1;
}

sub end_test_setup {
	$test_noflush = 0;
	@message_queue = ();
	stop_game();
	@test_scheduled_events = ();
}

sub do_tests {
	my ($connection, $nick) = @_;

	my @errors;

	notice($nick, "Running self-tests...");

	$just_testing = 1;

	# The tests
	eval {
		# A nonkill doesn't stop an SK from winning
		::bot_log("TEST win-1\n");
		launch_test_setup($nick, 'sk/sk', 'd', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-1a" if $game_active;
		push @errors, "win-1b" unless @test_winners == 1;
		push @errors, "win-1c" unless $test_winners[0] eq 'a';
		end_test_setup();

		# A nonkill mystery doesn't stop an SK from winning
		::bot_log("TEST win-2\n");
		launch_test_setup($nick, 'sk/sk', 'dmy', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-2a" if $game_active;
		push @errors, "win-2b" unless @test_winners == 1;
		push @errors, "win-2c" unless $test_winners[0] eq 'a';
		end_test_setup();

		# A kill stops an SK from winning
		::bot_log("TEST win-3\n");
		launch_test_setup($nick, 'sk/sk', 'v', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-3a" unless $game_active;
		end_test_setup();

		# A kill mystery stops an SK from winning
		::bot_log("TEST win-4\n");
		launch_test_setup($nick, 'sk/sk', 'vmy', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-4a" unless $game_active;
		end_test_setup();

		# Two SKs can win together if neither can kill
		::bot_log("TEST win-5\n");
		launch_test_setup($nick, 't/sk', 't/sk2', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-5a" if $game_active;
		push @errors, "win-5b" unless @test_winners == 2;
		push @errors, "win-5c" unless $test_winners[0] eq 'a';
		push @errors, "win-5d" unless $test_winners[1] eq 'b';
		end_test_setup();

		# Mafias can always kill, so can't win together
		::bot_log("TEST win-6\n");
		launch_test_setup($nick, 't/mafia', 't/mafia2', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-6a" unless $game_active;
		end_test_setup();

		# An SK can win together with a survivor
		::bot_log("TEST win-7\n");
		launch_test_setup($nick, 'sk/sk', 'sv/survivor', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-7a" if $game_active;
		push @errors, "win-7b" unless @test_winners == 2;
		push @errors, "win-7c" unless $test_winners[0] eq 'a';
		push @errors, "win-7d" unless $test_winners[1] eq 'b';
		end_test_setup();

		# An SK can win together with a survivor even if the survivor can kill
		::bot_log("TEST win-8\n");
		launch_test_setup($nick, 'sk/sk', 'mup/survivor', 't');
		set_votes('a', 'c');
		set_votes('b', 'c');
		push @errors, "win-8a" if $game_active;
		push @errors, "win-8b" unless @test_winners == 2;
		push @errors, "win-8c" unless $test_winners[0] eq 'a';
		push @errors, "win-8d" unless $test_winners[1] eq 'b';
		end_test_setup();

		# Targeting Green Goo goos you
		::bot_log("TEST trigger-1\n");
		launch_test_setup($nick, 'goo', 'd', 'sk/sk');
		next_phase();
		action($connection, 'protect', '', 'b', '', 'a');
		action($connection, 'none', '', 'c', '', '');
		flush_scheduled_events();
		push @errors, "trigger-1a" unless get_player_role('b') eq 'goo';
		end_test_setup();

		# Killing Blue Goo goos you
		::bot_log("TEST trigger-2\n");
		launch_test_setup($nick, 'bluegoo', 'sk/sk', 't', 't');
		next_phase();
		action($connection, 'kill', '', 'b', '', 'a');
		flush_scheduled_events();
		push @errors, "trigger-2a" unless get_player_role('b') eq 'bluegoo';
		end_test_setup();

		# Redirecting to a PGO causes a trigger
		::bot_log("TEST trigger-3\n");
		launch_test_setup($nick, 'd', 'pgo', 'red', 't', 'sk/sk');
		next_phase();
		action($connection, 'protect', '', 'a', '', 'd');
		action($connection, 'redirect', '', 'c', '', 'a b');
		flush_scheduled_events();
		push @errors, "trigger-3a" if alive('a');
		end_test_setup();

		# Targeting a twin affects the wrong player, unless that player is dead
		::bot_log("TEST twin-1\n");
		launch_test_setup($nick, 'twin', 'sk/sk', 'asc', 't', 't');
		$player_data{'a'}{buddy} = 'c';	
		next_phase();
		action($connection, 'kill', '', 'b', '', 'a');
		flush_scheduled_events();
		push @errors, "twin-1a" unless alive('a');
		push @errors, "twin-1b" if alive('c');
		next_phase();
		action($connection, 'kill', '', 'b', '', 'a');
		flush_scheduled_events();
		push @errors, "twin-1c" if alive('a');
		end_test_setup();

		# Immunities apply to the player affected, not the player targeted
		::bot_log("TEST twin-2\n");
		launch_test_setup($nick, 'twin', 'sk/sk', 'tik', 't', 't');
		$player_data{'a'}{buddy} = 'c';	
		next_phase();
		action($connection, 'kill', '', 'b', '', 'a');
		flush_scheduled_events();
		push @errors, "twin-2a" unless alive('a');
		push @errors, "twin-2b" unless alive('c');
		next_phase();
		action($connection, 'kill', '', 'b', '', 'c');
		flush_scheduled_events();
		push @errors, "twin-2c" if alive('a');
		push @errors, "twin-2d" unless alive('c');
		end_test_setup();

		# Reflex abilities ignore twinship
		::bot_log("TEST twin-3\n");
		launch_test_setup($nick, 'twin', 'd', 'pgo', 't', 'sk/sk');
		$player_data{'a'}{buddy} = 'b';
		next_phase();
		action($connection, 'protect', '', 'b', '', 'c');
		flush_scheduled_events();
		push @errors, "twin-3a" unless alive('a');
		push @errors, "twin-3b" if alive('b');
		end_test_setup();

		# You can roleblock a redirecter
		::bot_log("TEST redirectblock-1\n");
		launch_test_setup($nick, 'red/sk', 'rb', 'v', 't', 't');
		next_phase();
		action($connection, 'redirect', '', 'a', '', 'c e');
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'kill', '', 'c', '', 'd');
		flush_scheduled_events();
		push @errors, "redirectblock-1a" if alive('d');
		end_test_setup();

		# You can redirect a roleblocker
		::bot_log("TEST redirectblock-2\n");
		launch_test_setup($nick, 'red/sk', 'rb', 'v', 't', 't');
		next_phase();
		action($connection, 'redirect', '', 'a', '', 'b c');
		action($connection, 'block', '', 'b', '', 'd');
		action($connection, 'kill', '', 'c', '', 'd');
		flush_scheduled_events();
		push @errors, "redirectblock-2a" unless alive('d');
		end_test_setup();

		# You can roleblock a reflecter
		::bot_log("TEST reflectblock-1\n");
		launch_test_setup($nick, 'refl', 'rb/sk', 'v', 't', 't');
		next_phase();
		action($connection, 'reflectshield', '', 'a', '', 'd');
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'kill', '', 'c', '', 'd');
		flush_scheduled_events();
		push @errors, "reflectblock-1a" if alive('d');
		push @errors, "reflectblock-1b" unless alive('c');
		end_test_setup();

		# You can reflect a roleblocker
		::bot_log("TEST reflectblock-2\n");
		launch_test_setup($nick, 'refl', 'rb/sk', 'v', 't', 't');
		next_phase();
		action($connection, 'reflectshield', '', 'a', '', 'c');
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'kill', '', 'c', '', 'd');
		flush_scheduled_events();
		push @errors, "reflectblock-2a" if alive('d');
		end_test_setup();

		# You can redirect a reflecter away from another player
		::bot_log("TEST reflectredirect-1\n");
		launch_test_setup($nick, 'refl', 'red/sk', 'v', 't', 't');
		next_phase();
		action($connection, 'reflectshield', '', 'a', '', 'd');
		action($connection, 'redirect', '', 'b', '', 'a e');
		action($connection, 'kill', '', 'c', '', 'd');
		flush_scheduled_events();
		push @errors, "reflectredirect-1a" unless alive('c');
		push @errors, "reflectredirect-1b" if alive('d');
		end_test_setup();

		# You can redirect a reflecter to another player
		::bot_log("TEST reflectredirect-2\n");
		launch_test_setup($nick, 'refl', 'red/sk', 'v', 't', 't');
		next_phase();
		action($connection, 'reflectshield', '', 'a', '', 'e');
		action($connection, 'redirect', '', 'b', '', 'a d');
		action($connection, 'kill', '', 'c', '', 'd');
		flush_scheduled_events();
		push @errors, "reflectredirect-2a" if alive('c');
		push @errors, "reflectredirect-2b" unless alive('d');
		end_test_setup();

		# You can roleblock a copycat who copies someone else
		::bot_log("TEST copyblock-1\n");
		launch_test_setup($nick, 'copy', 'rb/sk', 'v', 'tik', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'c e');
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'kill', '', 'c', '', 'd');
		resolve_actions();
		push @errors, "copyblock-1a" unless alive('e');
		push @errors, "copyblock-1b" unless scalar(@message_queue) == 1;
		push @errors, "copyblock-1c" unless $message_queue[0][0] eq 'a';
		push @errors, "copyblock-1d" unless $message_queue[0][1] eq 'You have been blocked.';
		end_test_setup();

		# You can roleblock a copycat who copies you to someone else
		::bot_log("TEST copyblock-2\n");
		launch_test_setup($nick, 'copy', 'rb/sk', 'v', 'tik', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'b c');
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'kill', '', 'c', '', 'e');
		resolve_actions();
		push @errors, "copyblock-2a" if alive('e');
		push @errors, "copyblock-2b" unless scalar(@message_queue) == 1;
		push @errors, "copyblock-2c" unless $message_queue[0][0] eq 'a';
		push @errors, "copyblock-2d" unless $message_queue[0][1] eq 'You have been blocked.';
		end_test_setup();

		# You can block someone who is trying to copy a third-party roleblock to you
		::bot_log("TEST copyblock-3\n");
		launch_test_setup($nick, 'copy', 'merc/sk', 'rb', 't', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'c b');
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'block', '', 'c', '', 'e');
		resolve_actions();
		push @errors, "copyblock-3a" unless scalar(@message_queue) == 1;
		push @errors, "copyblock-3b" unless $message_queue[0][0] eq 'a';
		push @errors, "copyblock-3c" unless $message_queue[0][1] eq 'You have been blocked.';
		end_test_setup();

		# You can block someone who is trying to copy you to yourself
		::bot_log("TEST copyblock-4\n");
		launch_test_setup($nick, 'copy', 'merc/sk', 'rb', 't', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'b b');
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'block', '', 'c', '', 'e');
		resolve_actions();
		push @errors, "copyblock-4a" unless scalar(@message_queue) == 1;
		push @errors, "copyblock-4b" unless $message_queue[0][0] eq 'a';
		push @errors, "copyblock-4c" unless $message_queue[0][1] eq 'You have been blocked.';
		end_test_setup();

		# You can copy a roleblock
		::bot_log("TEST copyblock-5\n");
		launch_test_setup($nick, 'copy', 'rb/sk', 'v', 'tik', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'b c');
		action($connection, 'block', '', 'b', '', 'd');
		action($connection, 'kill', '', 'c', '', 'e');
		resolve_actions();
		push @errors, "copyblock-5a" unless alive('e');
		push @errors, "copyblock-5b" unless scalar(@message_queue) == 1;
		push @errors, "copyblock-5c" unless $message_queue[0][0] eq 'c';
		push @errors, "copyblock-5d" unless $message_queue[0][1] eq 'You have been blocked.';
		end_test_setup();

		# You can't roleblock an action copied by a trigger
		::bot_log("TEST copyblock-6\n");
		launch_test_setup($nick, 'mirr', 'rb/sk', 'v', 't', 't');
		next_phase();
		action($connection, 'block', '', 'b', '', 'a');
		action($connection, 'kill', '', 'c', '', 'a');
		resolve_actions();
		push @errors, "copyblock-6a" if alive('a');
		push @errors, "copyblock-6b" if alive('c');
		push @errors, "copyblock-6c" unless alive('b');
		end_test_setup();

		# You can roleblock a copycat who copies someone with no action to a third party
		::bot_log("TEST copyblock-7\n");
		launch_test_setup($nick, 'copy', 'rb/sk', 't', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'c d');
		action($connection, 'block', '', 'b', '', 'a');
		resolve_actions();
		push @errors, "copyblock-7a" unless scalar(@message_queue) == 1;
		push @errors, "copyblock-7b" unless $message_queue[0][0] eq 'a';
		push @errors, "copyblock-7c" unless $message_queue[0][1] eq 'You have been blocked.';
		end_test_setup();

		# You can roleblock a copycat who copies someone with no action to you
		::bot_log("TEST copyblock-8\n");
		launch_test_setup($nick, 'copy', 'rb/sk', 't', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'c b');
		action($connection, 'block', '', 'b', '', 'a');
		resolve_actions();
		push @errors, "copyblock-8a" unless scalar(@message_queue) == 1;
		push @errors, "copyblock-8b" unless $message_queue[0][0] eq 'a';
		push @errors, "copyblock-8c" unless $message_queue[0][1] eq 'You have been blocked.';
		end_test_setup();

		# You can copy a hide
		::bot_log("TEST copyhide-1\n");
		launch_test_setup($nick, 'copy', 'cow/sk', 'v', 't');
		next_phase();
		action($connection, 'copy', '', 'a', '', 'b d');
		action($connection, 'hide', '', 'b', '', '');
		action($connection, 'kill', '', 'c', '', 'a');
		resolve_actions();
		push @errors, "copyhide-1a" unless alive('a');
		end_test_setup();

		# You can hide from a kill
		::bot_log("TEST hide-1\n");
		launch_test_setup($nick, 'cow/sk', 'v', 't', 't');
		next_phase();
		action($connection, 'hide', '', 'a', '', '');
		action($connection, 'kill', '', 'b', '', 'a');
		resolve_actions();
		push @errors, "hide-1a" unless alive('a');
		end_test_setup();

		# You can hide from a block
		::bot_log("TEST hide-2\n");
		launch_test_setup($nick, 'cow/sk', 'rb', 't', 't');
		next_phase();
		action($connection, 'hide', '', 'a', '', '');
		action($connection, 'block', '', 'b', '', 'a');
		resolve_actions();
		push @errors, "hide-2a" unless scalar(@message_queue) == 0;
		end_test_setup();

		# You can hide even if nonkill-immune
		::bot_log("TEST hide-3\n");
		launch_test_setup($nick, 'sk/sk', 'cow+template_asc', 't', 't');
		next_phase();
		action($connection, 'hide', '', 'b', '', '');
		action($connection, 'kill', '', 'a', '', 'b');
		resolve_actions();
		push @errors, "hide-3a" unless alive('b');
		end_test_setup();

		# You can redirect to an ascetic
		::bot_log("TEST redirect-1\n");
		launch_test_setup($nick, 'sk/sk', 'red', 'asc', 't');
		next_phase();
		action($connection, 'kill', '', 'a', '', 'd');
		action($connection, 'redirect', '', 'b', '', 'a c');
		resolve_actions();
		push @errors, "redirect-1a" unless alive('d');
		push @errors, "redirect-2a" if alive('c');
		end_test_setup();

		# Eradicating a lovestruck townie's lover kills the lovestruck townie
		::bot_log("TEST eradicate-1\n");
		launch_test_setup($nick, 'erad1/sk', 'lover', 't', 't', 't');
		$player_data{'b'}{buddy} = 'c';
		action($connection, 'eradicate', '', 'a', '', 'c');
		resolve_actions();
		push @errors, "eradicate-1a" if alive('b');
		push @errors, "eradicate-1b" if alive('c');
		end_test_setup();

		# Recruit and kill on the same night leaves the player town
		::bot_log("TEST recruit-1\n");
		launch_test_setup($nick, 'cult1/cult', 'v', 't', 't', 't');
		next_phase();
		action($connection, 'recruit', '', 'a', '', 'c');
		action($connection, 'kill', '', 'b', '', 'c');
		resolve_actions();
		push @errors, "recruit-1a" unless get_player_role('c') eq 't';
		push @errors, "recruit-1b" unless get_player_team('c') eq 'town';
		end_test_setup();

		# Killing a cult leader stops the recruit
		::bot_log("TEST recruit-2\n");
		launch_test_setup($nick, 'cult1/cult', 'v', 't', 't', 't');
		next_phase();
		action($connection, 'recruit', '', 'a', '', 'c');
		action($connection, 'kill', '', 'b', '', 'a');
		resolve_actions();
		push @errors, "recruit-2a" unless get_player_role('c') eq 't';
		push @errors, "recruit-2b" unless get_player_team('c') eq 'town';
		end_test_setup();

		# Canonicalization tests
		::bot_log("TEST canonicalize-1\n");
		push @errors, "canonicalize-1a" if canonicalize_role('dkill+mut2', 1) ne 'dkill+mut2';
		push @errors, "canonicalize-1b" if canonicalize_role('twin+goo', 1) ne 'twin+goo';

		# Census should work with mystery roles
		::bot_log("TEST census-1\n");
		launch_test_setup($nick, 'dmy', 't', 't/sk');
		action_census('a', 'actprotect');
		push @errors, "census-1a" unless $message_queue[0][0] eq 'a';
		push @errors, "census-1b" unless $message_queue[0][1] eq 'There is 1 Mystery Doctor alive.';
		flush_message_queue();
		action_census('a', 'actmystery');
		push @errors, "census-1c" unless $message_queue[0][0] eq 'a';
		push @errors, "census-1d" unless $message_queue[0][1] eq 'There is 1 Mystery Doctor alive.';
		flush_message_queue();
		end_test_setup();

		::bot_log("TEST end\n");
	};

	$just_testing = 0;

	if ($@)
	{
		notice($nick, "Error running tests: $@");
	}
	notice($nick, "Testing finished with " . scalar(@errors) . " errors.");
	for (my $i = 0; $i < 4 && $i <= $#errors; $i++)
	{
		notice($nick, "Error in test '$errors[$i]'");
	}
}
