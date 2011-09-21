package base;

use strict;
use warnings;
no warnings 'redefine';

sub add_commands  {
	::add_command_any "time", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		my $fromnick = (split /!/, $from)[0];
		my $bottime = scalar(localtime);
		::notice("It is currently $bottime UTC");
		return 1;
	}, "Returns the current time on the bot's clock.";
	::add_command_any "auth", sub {
                my ($self, $command, $forum, $from, $to, $args) = @_;
                my $fromnick = (split /!/, $from)[0];
                my (undef, $username, $password) = split m{/}, "$::password/";
                ::bot_log "AUTH from $fromnick\n";
                ::say('nickserv@services.globalgamers.net', "auth $username $password");
                $::cur_connection->mode($::nick, '+'.'x', $::nick);
                return 1;
        }, 500, "Causes the bot to auth with nickserv if it has not done so.";
	::add_command_any "quit", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		my $fromnick = (split /!/, $from)[0];
		::bot_log "QUIT from $fromnick\n";
		$self->quit($args ? $args : "Quitting");
		$::quitting = 1;
		return 1;
	}, 500, "quit [message]: Causes the bot to quit, possibly with a message. This is a privileged command.";
	::add_command_any "upgrade", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		my $fromnick = (split /!/, $from)[0];
		::bot_log "RELOAD from $fromnick\n";
		&::do_reload;
		::notice("Reloaded.");
		return 1;
	}, 500, "upgrade: Causes the bot to reload itself. This a privileged command.";
	::add_command_public "dance", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		if ($args && $args =~ /[.!?,]|xyl|then/) {
			my $weight = int(rand(20)) + 3;
			my $user = $from;
			$user =~ s/!.*$//;
			::action("smacks $user with a $weight-lb trout");
			return;
		}
		::action($args ? "does a little $args dance" : "does a little dance");
		return 1;
	}, "dance [style]: Causes the bot to perform a dance.";
	::add_command_public "slap", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		return 0 unless $args;
		::action("slaps $args with a small trout");
		return 1;
	}, "slap <person>: Causes the bot to slap someone.";
	::add_command_public "gumby", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		return 0 unless $args;
		
		my $target = $args;
		
		my $owner = quotemeta $::owner;
		my $nick = quotemeta $::nick;
		
		if ($target =~ /self/i || $target =~ /bot/i || $target =~ /$owner/i || $target =~ /$nick/i || $target =~ /owner/i || $target =~ /Xyl/i || $target =~ /Uprising/i)
		{
			$target = $from;
			$target =~ s/!.*$//;
		}
		
		::action("puts on some spike-toed boots and proceeds to vigorously kick $target in the nuts over and over and over and over and over and over and over...");
		return 1;
	}, "gumby <person>: Causes the bot to attack someone with extreme hostility.";
	::add_command_any "loadmodule", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		my $fromnick = (split /!/, $from)[0];
		print "LOADMODULE from $fromnick\n";
		::load_module($args);
		return 1;
	}, 500, "loadmodule <module>: Loads an optional module. This is a privileged command.";
	::add_command_any "forceloadmodule", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		my $fromnick = (split /!/, $from)[0];
		print "LOADMODULE from $fromnick\n";
		delete $::module_loaded{$args};
		::load_module($args);
		return 1;
	}, 500, "forceloadmodule <module>: Loads an optional module, even if it's already loaded. This is a privileged command.";
	::add_command_any "showcommands", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;
		my @commands = sort(keys %::commands, keys %::commands_public);
		
		::say_or_notice("Available commands: @commands");
		return 1;
	}, "showcommands: Displays the available in-channel commands. Commands only usable by /msg are not displayed. To get help on a specific command, type '/msg " . $::nick . " help <command>'.";
	::add_command_any "help", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;

		$args =~ s/\s+/ /g;
		if (!exists $::command_help{lc $args})
		{
			::notice("Sorry, no help is available for that topic.");
			return 1;
		}
		
		foreach my $line (split /\n/, $::command_help{lc $args})
		{
			::notice($line);
		}

		return 1;
	}, "help <command>: Gets information on a command.";
	::add_command_any "join", sub {
		my ($self, $command, $forum, $from, $to, $args) = @_;

		my $fromnick = (split /!/, $from)[0];
		my $channel = $args;
		print "JOIN $args from $fromnick\n";

		$self->join($channel);
		return 1;
	}, 400, "join <channel>: Causes the bot to join a new channel. This is a privileged command.";
	::add_command_any "part", sub {
		my ($self, $command, $forum, $from, $to, $args, $level) = @_;

		my $fromnick = (split /!/, $from)[0];
		my $channel = $args || $to;
		print "PART $channel from $fromnick\n";

		$self->part($channel);
		$::joined_channels{$channel} = 1;
		return 1;
	}, 400, "part [channel]: Causes the bot to leave a channel. This is a privileged command.";
	::add_command_any "set", sub {
		my ($self, $command, $forum, $from, $to, $args, $level) = @_;

		my ($var, $value) = split(/\s+/, $args, 2);
		
		if ($var =~ /^requirename$/i)
		{
			$::require_name = ($value =~ /^t|^1|^o/ ? 1 : 0);
			::notice("requirename set to " . ($::require_name ? "on" : "off"))
		}
		else
		{
			::notice("Unrecognized variable.");
		}
		
		return 1;
	}, 400, "set <variable> <value>: Sets an internal variable. This is a privileged command.";
	
	::add_command_any "checklevel", sub {
		my ($self, $command, $forum, $from, $to, $args, $level) = @_;
		
		::notice("You are level $level.");
	};
	::add_command_public "up", sub {
		my ($self, $command, $forum, $from, $to, $args, $level) = @_;

		if ($level >= 400)
		{
			my $who = $from;
			$who =~ s/!.*//;
			$self->mode($to, "+o", $who);
		}
	};
	::add_command_any "killghost", sub {
		my ($self, $command, $forum, $from, $to, $args, $level) = @_;

		if ($level >= 400)
		{
			::say("ChanServ", "ghost $args");
		}
	};
}

1;
