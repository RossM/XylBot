package mafia;

use strict;
use warnings;
no warnings 'redefine', 'qw';
use sort 'stable';
use Carp qw(cluck);

our (%messages);
our (%role_config, %group_config, %setup_config);
our (%player_data, %role_data, %group_data);
our (@players, @alive);
our (@action_queue, @resolved_actions);
our ($phases_without_kill);
our ($day, $phase);
our (@recharge_timers);
our (@timed_action_timers);
our ($cur_setup);

our %action_config = (

	### 100 - Metaabilities ###

	copy => {
		priority => 101,
		targets => ["alive,nonself", "alive"],
		resolvedelay => 'redirect',
		status => 'copy',
		realtargets => 1,
		help => "copy [player] [newtarget]: Copies a player's night ability and chooses a new target. The ability will work as if you had used it yourself.",
	},
	release => {
		priority => 102,
		targets => [],
		resolvedelay => 'immediate',
		help => "release: All actions you have delayed take effect.",
	},
	cancel => {
		priority => 103,
		targets => [],
		resolvedelay => 'immediate',
		help => "cancel: Actions you have delayed are forgotten and never take effect.",
	},
	makehidden => {
		priority => 105,
		targets => ["alive,nonself"],
		resolvedelay => 'shield',
		help => "makehidden [player]: Makes another player untargetable for one night.",
	},
	hide => {
		alias => "makehidden #S",
		targets => [],
		type => "nonkill,locked,noimmune",
		help => "hide: Makes yourself untargetable for one night.",
	},
	shield => {
		alias => "makehidden",
		targets => ["alive,nonself"],
	},
	superbus => {
		priority => 106,
		targets => ["alive,nonself,unique", "alive,nonself,unique"],
		type => 'super',
		resolvedelay => 'shield',
		checkalive => 'target',
	},
	bus => {
		priority => 107,
		targets => ["alive,nonself,unique", "alive,nonself,unique"],
		resolvedelay => 'shield',
		checkalive => 'target',
		help => "bus [player1] [player2]: All actions this phase that would affect one target affect the other instead.",
	},
	reflectshield => {
		priority => 108,
		targets => ["alive,nonself"],
		resolvedelay => 'shield',
		type => 'nonkill,noreflect',
		help => "reflectshield [player]: Gives a player a reflection shield for the night. Any other night action targeting that player will bounce back on the player using it.",
	},
	timedsetstatus => {
		priority => 108.5,
		targets => ["alive,nonself"],
		status => 'timedset',
		# Adding a status can do pretty much anything, so for safety we assume it might set reflect/immune
		resolvedelay => 'shield',
		type => 'super',
		help => "timedsetstatus [player]: Sets a status on another player. The exact effects are role-dependent. This is not intended as a player-usable action.",
	},
	setstatus => {
		priority => 109,
		targets => ["alive,nonself"],
		status => 'set',
		# Adding a status can do pretty much anything, so for safety we assume it might set reflect/immune
		resolvedelay => 'shield',
		type => 'super',
		help => "setstatus [player]: Sets a status on another player. The exact effects are role-dependent. This is not intended as a player-usable action.",
	},
	increasestatus => {
		priority => 109.5,
		targets => ["alive,nonself"],
		status => 'increase',
		# Adding a status can do pretty much anything, so for safety we assume it might set reflect/immune
		resolvedelay => 'shield',
		type => 'super',
		help => "increasestatus [player]: Sets a status on another player. The exact effects are role-dependent. This is not intended as a player-usable action.",
	},
	trigger => { 
		priority => 109.5,
		targets => ["alive,nonself"],
		resolvedelay => 'immediate',
		help => "trigger [player]: Does something depending on the target's role.",
	},
	delay => {
		priority => 110,
		targets => ["alive,nonself"],
		resolvedelay => 'normal',
		help => "delay [player]: Delays a player's actions until the next night. Your target is not told they are blocked.",
	},
	block => {
		priority => 111,
		targets => ["alive,nonself"],
		resolvedelay => 'normal',
		help => "block [player]: Roleblocks a player, preventing them from using their night abilities.",
	},
	randomize => {
		priority => 112,
		targets => ["alive,nonself"],
		resolvedelay => 'redirect',
		realtargets => 1,
		help => "randomize [player]: Changes the target of another player's night action to a target selected at random.",
	},
	chaos => {
		priority => 112,
		targets => [],
		type => 'super',
		help => "chaos: Night actions have a 50% chance of affecting a random target.",
	},
	redirectkill => {
		priority => 113,
		targets => ["alive,nonself", "alive"],
		resolvedelay => 'redirect',
		realtargets => 1,
		help => "redirectkill [player] [newtarget]: Changes the target of another player's kill action to a target of your choice. Nonkill actions are unaffected.",
	},
	redirect => {
		priority => 114,
		targets => ["alive,nonself", "alive"],
		resolvedelay => 'redirect',
		realtargets => 1,
		help => "redirect [player] [newtarget]: Changes the target of another player's night action to a target of your choice.",
	},
	
	### 200 - Protection ###
	
	protect => {
		priority => 201,
		targets => ["alive,nonself"],
		resolvedelay => 'shield',
		help => "protect [player]: Gives another player immunity to a single kill action for that night.",
	},
	superprotect => {
		priority => 202,
		targets => ["alive,nonself"],
		resolvedelay => 'shield',
		type => 'super',
		help => "superprotect [player]: Gives another player total immunity to kill abilities this night. This even affects roles that are immune to normal protection.",
	},
	guard => {
		priority => 203,
		targets => ["alive,nonself"],
		resolvedelay => 'shield',
		status => 'guard',
		help => "guard [player]: Guard another player against attacks. If they would be killed, you and/or the attacker will be killed instead.",
	},

	### 250 - Special ###
	
	message => {
		priority => 250,
		targets => ["alive"],
		status => 'message',
		help => "message [player]: Sends a specific message to another player. This is normally used as part of theme roles.",
	},
	announce => {
		priority => 250.5,
		targets => ["alive"],
		status => 'announce',
		help => "announce [player]: Makes an announcement. This is normally used as part of theme roles.",
	},
	clearphaseaction => {
		priority => 251,
		targets => [],
		help => "clearphaseaction: Lets you use a second action this phase.",
	},

	### 300 - Self transformation ###
	
	morph => {
		priority => 302,
		targets => ["alive,nonself"],
		status => 'morphstatus',
		checkalive => "player",
		help => "morph [player]: Turns you into a perfect copy of another player except for your win condition. You retain this ability.",
	},
	channel => {
		alias => 'morph',
		targets => ["dead,nonself"],
		status => 'morphstatus',
		checkalive => "player",
		help => "channel [player]: Turns you into a perfect copy of a dead player except for your win condition. You retain this ability.",
	},
	transform => {
		priority => 303,
		targets => [],
		status => 'transform',
		help => "transform: You get a new role. The role you get depends on your current role.",
	},
	transform2 => {
		priority => 304,
		targets => ["alive,nonself"],
		status => 'transform',
		help => "transform2 [player]: You get a new role. The role you get depends on your current role.",
	},
	buddy => {
		priority => 305,
		targets => ["alive,nonself"],
		help => "buddy [player]: Your buddy becomes the chosen player.",
	},
	setbuddy => {
		priority => 306,
		targets => ["alive,nonself", "alive"],
		help => "setbuddy [player] [buddy]: Sets another player's buddy. This is not intended as a player-usable action.",
	},
	
	# 400 - Nonself transformation (prekill)

	# abilitycopy = 10
	giveability => {
		priority => 401,
		targets => ["alive,nonself"],
		status => 'give',
		checkalive => "target",
		help => "giveability [player]: Gives an ability chosen at random to another player. You learn what ability was given.",
	},
	gift => {
		alias => "giveability",
		targets => ["alive,nonself"],
	},
	copyabilityto => {
		priority => 402,
		targets => ["alive,nonself", "alive"],
		status => 'copyuses',
		help => "copyabilityto [player] [recipient: Gives a player the ability used by another player that night.",
	},
	copyability => {
		alias => "copyabilityto #1 #S",
		targets => ["alive,nonself"],
		help => "copyability [player]: Gives you the ability used by a player that night.",
	},
	steal => {
		priority => 403,
		targets => ["alive,nonself"],
		status => 'stealuses',
		checkalive => "target",
		help => "steal [player]: Steals a random ability from another player. The theft is permanent. (Group abilities can't be stolen.)",
	},
	stealdead => {
		priority => 404,
		targets => ["dead,nonself"],
		status => 'stealuses',
		help => "stealdead [player]: Steals a random ability from a dead player. The theft is permanent. (Group abilities can't be stolen.)",
	},
	stealitem => {
		priority => 403,
		targets => ["alive,nonself"],
		help => "stealitem [player]: Steals a random item from another playe. The theft is permanent.",
	},
	swap => {
		priority => 405,
		targets => ["alive,nonself,unique", "alive,nonself,unique"],
		help => "swap [player1] [player2]: Swaps two players' roles, but not teams. The swap is permanent.",
	},
	psych => {
		priority => 406,
		targets => ["alive,nonself"],
		status => 'convert',
		checkalive => "target",
		help => "psych [player]: If the target is a Serial Killer, converts them into a normal Townie.",
	},
	curse => {
		priority => 407,
		targets => ["alive,nonself"],
		status => 'curse',
		checkalive => "target",
		help => "curse [player]: Inflict a curse on another player.",
	},
	mark => {
		priority => 408,
		targets => ["alive,nonself"],
		help => "mark [player]: Sets a temporary mark on a player.",
	},
	unmark => {
		priority => 409,
		targets => ["alive,nonself"],
		help => "unmark [player]: Clears a temporary mark on a player.",
	},

	### 500 - Vote modification ###
	
	subvote => {
		priority => 500,
		targets => ["alive,nonself"],
		checkalive => "target",
		help => "subvote [player]: Takes away a player's vote the next day.",
	},
	addvote => {
		priority => 501,
		targets => ["alive,nonself"],
		checkalive => "target",
		help => "addvote [player]: Gives a player an extra vote the next day.",
	},
	motivate => {
		alias => "addvote",
		targets => ["alive,nonself"],
	},
	proclaim => {
		priority => 501,
		targets => ["alive,nonself"],
		checkalive => "target",
		help => "proclaim [player]: Gives a player an extra vote for the day. The player selected is announced publically.",
	},
	timedproclaim => {
		priority => 501,
		targets => ["alive,nonself"],
		checkalive => "target",
	},	
	voteblock => {
		alias => "subvote #1",
		targets => ["alive,nonself"],
	},
	# givevote = 25
	forcevote => {
		priority => 504,
		targets => ["alive,nonself", "alive,nolynch"],
		checkalive => "target",
		help => "forcevote [player] [votee]: Forces a player to vote as you wish. The target player cannot change their vote for the rest of the day.",
	},
	command => {
		alias => "forcevote",
		targets => ["alive,nonself", "alive,nolynch"],
	},
	
	### 600 - Status infliction ###
	
	poison => {
		priorty => 601,
		targets => ["alive,nonself"],
		is_kill => 1,
		status => 'poisontime',
		help => "poison [player]: Gives a player slow-action poison which will kill them later. Even players immune to normal kills can be killed by poison.",
	},
	disablebase => {
		priority => 602,
		targets => ["alive,nonself"],
		status => 'disabletime',
		help => "disablebase [player]: Temporarily removes all of a player's abilities and characteristics.",
	},
	timeddisable => {
		priority => 602.1,
		targets => ["alive,nonself"],
		status => 'disabletime',
		help => "timeddisable [player]: Temporarily removes all of a player's abilities and characteristics.",
	},
	winonlynch => {
		priority => 603,
		targets => ["alive,nonself"],
		help => "winonlynch [player]: You win if the target is lynched this turn.",
	},
	prime => {
		priority => 604,
		targets => ["alive,nonself"],
		help => "prime [player]: Douses a player in gasoline, killing them when the ignite action is used.",
	},
	stun => {
		priority => 605,
		targets => ["alive,nonself"],
		help => "stun [player]: The next action with timed recharge the target takes has its recharge time doubled.",
	},

	### 700 - Status removal ###
	
	antidote => {
		priority => 701,
		targets => ["alive,nonself"],
		help => "antidote [player]: Cures a player who has been poisoned. You can't cure yourself.",
	},
	defuse => {
		priority => 702,
		targets => ["alive,nonself"],
		checkalive => "player,target",
		help => "defuse [player]: Defuses a timebomb on another player. Defusing takes a short amount of time.",
	},
	
	### 800 - Miscellaneous ###
	
	friend => {
		priority => 801,
		targets => ["alive,nonself"],
		help => "friend [player]: Sends a player a message that tells them which team you are on.",
	},
	pardon => {
		priority => 802,
		targets => ["alive,nonself"],
		help => "pardon [player]: If the chosen player is lynched today, they will return to life.",
	},
	reload => {
		priority => 803,
		targets => [],
		help => "reload: Gives you full charges of all limited-use abilities.",
	},
	charge => {
		priority => 804,
		targets => [],
		status => "charge",
		help => "charge: Increase the damage of your next attack.",
	},
	safeclaim => {
		priority => 805,
		targets => [],
		free => 1,
		help => "safeclaim: Gives you a safe claim.",
	},
	
	### 900 - Kills ###
	
	suicide => {
		priority => 901,
		targets => [],
		checkalive => "player",
		help => "suicide: Kills you. Why would you want to do that?",
	},
	suicidebomb => {
		priority => 902,
		targets => ["alive,nonself"],
		type => 'kill',
		is_kill => 1,
		checkalive => "player",
		help => "suicidebomb [player]: Kills another player and yourself. If the player is immune to kills, only you will die.",
	},
	possess => {
		priority => 905,
		targets => ["alive,nonself"],
		checkalive => "target",
		help => "possess [player]: You die, but the target joins your team and gains this ability.",
	},
	decult => {
		priority => 906,
		targets => ["alive,nonself"],
		checkalive => "target",
		help => "decult [player]: If the target is a cultist, that player will peacefully leave the town.",
	},
	convert => {
		alias => "decult",
		targets => ["alive,nonself"],
	},
	"kill" => {
		priority => 907,
		targets => ["alive,nonself"],
		type => 'kill',
		is_kill => 1,
		checkalive => "target",
		help => "kill [player]: Kills another player. A doctor can prevent the kill, and some roles are immune.",
	},
	doom => {
		priority => 908,
		targets => ["alive,nonself"],
		type => 'kill',
		is_kill => 1,
		checkalive => "target",
		status => 'doompercent',
		help => "doom [player]: Increases a player's doom level. When a player is sufficiently doomed, they die.",
	},
	attack => {
		priority => 908,
		targets => ["alive,nonself"],
		type => 'kill',
		is_kill => 1,
		checkalive => "target",
		status => "weapondamage",
		help => "attack [player]: Deals damage to a player. When a player is sufficiently damaged, they die.",
		public => 1,
	},
	nuke => {
		priority => 908.5,
		targets => ["alive,nonself"],
		type => 'kill',
		is_kill => 1,
		checkalive => "player,target",
		status => "countdown",
		help => "nuke [player]: Calls down a nuclear strike which kills the target after a short delay. Also deals damage to all other players.",
	},
	mafiakill => {
		alias => "kill",
		targets => ["alive,nonself"],
		is_kill => 1,
		help => "mafiakill [player]: Kills another player. Only one mafia can use mafiakill each night. A doctor can prevent the kill, and some roles are immune.",
	},
	superkill => {
		priority => 909,
		targets => ["alive,nonself"],
		type => 'super',
		is_kill => 1,
		checkalive => "target",
		help => "superkill [player]: Kills another player, even if they have doctor protection or are immune to kills.",
	},
	timebomb => {
		priority => 910,
		targets => ["alive,nonself"],
		type => 'kill',
		is_kill => 1,
		checkalive => "target",
		help => "timebomb [player]: Kills another player after a short delay.",
	},
	reverseprotect => {
		priority => 911,
		targets => ["alive,nonself"],
		is_kill => 1,
		checkalive => "target",
		help => "reverseprotect [player]: Reverses a doctor protection on another player. If that player is protected tonight, they will die instead.",
	},
	shoot => {
		priority => 912,
		targets => ["alive"],
		is_kill => 1,
		help => "shoot [player]: Shoot a player in Ready-Aim-Fire.",
	},
	rock => {
		priority => 913,
		targets => [],
		is_kill => 1,
		help => "rock: Good ol' rock. Nothing beats rock.",
	},
	paper => {
		priority => 913,
		targets => [],
		is_kill => 1,
		help => "paper: Things look good on it.",
	},
	scissors => {
		priority => 913,
		targets => [],
		is_kill => 1,
		help => "scissors: Remember, always run with the pointy end forward.",
	},
	ignite => {
		priority => 913,
		targets => [],
		is_kill  => 1,
		help => "ignite: Sets a fire, which kills all primed players.",
	},
	apocalypse => {
		priority => 914,
		targets => [],
		is_kill => 1,
		status => 'doompercent',
		help => "apocalypse: Players die randomly.",
	},
	truthsay => {
		priority => 914,
		targets => ["alive, nonself"],
		checkalive => "target",
		help => "truthsay: Prevent players from dieing randomly to doomspeakers or banshees.",
	},
	
	### 950 - Nonself transformation ###
	
	recruit => {
		priority => 955,
		targets => ["alive,nonself"],
		status => 'recruit',
		checkalive => "player,target",
		help => "recruit [player]: Recruits another player into your cult. This ability only affects town-aligned players. If you are killed, the recruited players will die.",
	},
	enslave => {
		alias => "recruit",
		targets => ["alive,nonself"],
	},
	superrecruit => {
		priority => 956,
		targets => ["alive,nonself"],
		status => 'recruit',
		checkalive => "target",
		help => "superrecruit [player]: Recruits another player into your cult. This ability can affect any player. The recruited player does not die when you do.",
	},
	mutate => {
		priority => 957,
		targets => ["alive,nonself"],
		status => 'mutate',
		checkalive => "target",
		help => "mutate [player]: Transforms another player into a random role. (The player's team does not change.)",
	},
	selfmutate => {
		alias => "mutate #S",
		targets => [],
		type => "nonkill,locked,noimmune",
		status => 'mutate',
		help => "selfmutate: You get a new role at random. You retain this ability.",
	},
	infect => {
		priority => 958,
		targets => ["alive,nonself"],
		status => 'infect',
		checkalive => "target",
		is_kill => 1,
		help => "infect [player]: Infect another player with a fatal disease.",
	},
	silentinfect => {
		priority => 958,
		targets => ["alive,nonself"],
		status => 'infect',
		checkalive => "target",
		is_kill => 1,
		help => "silentinfect [player]: Infect another player with a condition. They do not learn they are infected.",
	},
	transformother => {
		priority => 959,
		targets => ["alive,nonself"],
		status => 'transform',
		checkalive => "target",
		help => "transformother [player]: Transform another player to a new role and possibly team.",
	},
	evolve => {
		priority => 960,
		targets => ["alive,nonself"],
		checkalive => "target",
		help => "evolve [player]: Changes a player's role to a more advanced form. The new role depends on the old role, and replaces the old role's abilities.",
	},
	restore => {
		priority => 961,
		targets => ["alive,nonself"],
		checkalive => "target",
		help => "restore [player]: Returns a player to their original role. This won't work on cultists.",
	},
	
	### 1000 - Resurrection ###
	
	resurrect => {
		priority => 1001,
		targets => ["dead,nonself"],
		type => 'resurrect',
		help => "resurrect [player]: Brings another player back from the dead. You cannot resurrect the same player twice.",
	},

	### 1100 - Inspection tampering ###

	frame => {
		priority => 1101,
		targets => ["alive,nonself"],
		help => "frame [player]: Makes another player show up as mafia to any cop investigations targeting them this night.",
	},
	clear => {
		priority => 1102,
		targets => ["alive,nonself"],
		help => "clear [player]: Makes another player show up as town to any cop investigations targeting them this night.",
	},
	destroybody => {
		priority => 1103,
		targets => ["dead,nonself"],
		help => "destroybody [player]: Prevents a dead player from being revived or autopsied.",
	},
	
	### 1200 - Inspections ###
	
	autopsy => {
		priority => 1201,
		targets => ["dead,nonself"],
		help => "autopsy [player]: Discovers who killed another player.",
	},
	"watch" => {
		priority => 1202,
		targets => ["alive,nonself"],
		status => 'track',
		help => "watch [player]: Determines whether a player used a night action this night.",
	},
	track => {
		priority => 1203,
		targets => ["alive,nonself"],
		status => 'track',
		help => "track [player]: Determines the target of a player's night action this night, if any.",
	},
	patrol => {
		priority => 1204,
		targets => ["alive,nonself"],
		status => 'track',
		help => "patrol [player]: Tells you who targeted the chosen player this night.",
	},
	inspect => {
		priority => 1205,
		targets => ["alive,nonself"],
		status => 'sanity',
		help => "inspect [player]: Determines some information about another player. Be careful, the information might not be true.",
	},
	inspectrole => {
		priority => 1206,
		targets => ["alive,nonself"],
		help => "inspectrole [player]: Determines another player's role name.",
	},
	census => {
		priority => 1206,
		targets => [],
		status => 'census',
		help => "census: Tells you how many players of some types are alive.",
	},
	eavesdrop => {
		priority => 1207,
		targets => ["alive,nonself"],
		help => "psi [player]: You recieve copies of all messages the target player recieves this phase.",
	},
	
	### No action (special) ###
	
	none => {
		targets => [],
	},

	### Aliases: Random actions ###
	
	mup => {
		alias => "none ? protect #1 ? inspect #1 ? kill #1",
		targets => ["alive,nonself"],
		is_kill => 1,
		help => "mup [player]: This has a 25% chance of protecting the target, a 25% chance of investigating, a 25% chance of killing, and a 25% chance of doing nothing.",
	},
	hack => {
		alias => "block #1 ? block #1 ? block #1 ? redirect #1 #? ? redirect #1 #1 ? redirect #1 #S ? copy #1 #? ? copy #1 #1 ? copy #1 #S",
		targets => ["alive,nonself"],
		help => "hack [player]: This hacks another player's action, which has an equal chance of blocking it, redirecting it, or copying it.",
	},

	### Aliases: Multiple actions ###

	mimic => {
		alias => "bus #1 #S",
		targets => ["alive,nonself"],
		help => "mimic [player]: Any actions targeting you affect your target, and vice versa.",
	},
	isolate => {
		alias => "block #1 \\ protect #1",
		targets => ["alive,nonself"],
		help => "isolate [player]: This both blocks a player and protects them from kills.",
	},
	kill2 => {
		alias => "kill #1 \\ kill #2",
		targets => ["alive,nonself,unique", "alive,nonself,unique"],
		type => 'kill,multitarget',
		is_kill => 1,
		help => "kill2 [player1] [player2]: Kills two players at the same time. The targets must be different and neither one can be yourself.",
	},
	abduct => {
		alias => "block #1 \\ makehidden #1",
		targets => ["alive,nonself"],
		help => "abduct [player]: Abducts a player, both blocking their night action and preventing them from being targeted by other night actions.",
	},
	negate => {
		alias => "block #1 \\ subvote #1",
		targets => ["alive,nonself"],
		help => "negate [player]: Blocks a player's action and prevents them from voting the next day.",
	},
	reveal => {
		alias => "friend #1 \\ inspect #1",
		targets => ["alive,nonself"],
		help => "reveal [player]: Determines another player's alignment, and reveals your alignment to that player.",
	},
	pry => {
		alias => "reveal",
		targets => ["alive,nonself"],
	},
	dematerialize => {
		alias => "hide \\ subvote #S",
		targets => [],
		help => "dematerialize: You cannot be affected by night actions, but lose your vote the next day.",
	},
	reanimate => {
		alias => "resurrect \\ recruit",
		targets => ["dead,nonself"],
		type => 'resurrect,linked',
		help => "reanimate [player]: Brings another player back from the dead and recruits them into your cult. Only protown players can be recruited. " .
			"You cannot reanimate the same player twice.",
	},
	reincarnate => {
		alias => "resurrect \\ mutate",
		targets => ["dead,nonself"],
		type => 'resurrect,linked',
		help => "reincarnate [player]: Brings another player back from the dead and gives them a new role at random. " .
			"You cannot reincarnate the same player twice.",
	},
	raise => {
		alias => "resurrect #1 \\ suicide",
		targets => ["dead,nonself"],
		help => "raise [player]: Returns another player from the dead in exchange for your own life. This ability works even if you are killed by someone else the night you use it.",
	},
	takevote => {
		alias => "subvote #1 \\ addvote #S",
		targets => ["alive,nonself"],
		type => 'nonkill,linked',
		checkalive => "target",
		help => "takevote [player]: Steals a vote from another player and gives it to you for the next day.",
	},
	stealvote => {
		alias => "takevote",
		targets => ["alive,nonself"],
		type => 'nonkill,linked',
	},
	absorb => {
		alias => "steal #1 \\ kill #1",
		targets => ["alive,nonself"],
		type => 'kill,linked',
		is_kill => 1,
		help => "absorb [player]: Kills another player, and steals one of their abilities.",
	},
	consume => {
		alias => "absorb",
		targets => ["alive,nonself"],
		is_kill => 1,
	},
	replicate => {
		alias => "morph #1 \\ kill #1",
		targets => ["alive,nonself"],
		type => 'kill,linked',
		is_kill => 1,
		help => "replicate [player]: Kills another player and turns you into an exact copy of them.",
	},
	trick => {
		alias => "swap #1 #? \\ kill #1",
		targets => ["alive,nonself"],
		type => 'kill,linked',
		is_kill => 1,
		help => "trick [player]: Switches a player's role with a random player, then kills them..",
	},
	drain => {
		alias => "kill #1 \\ giveability #S",
		targets => ["alive,nonself"],
		type => 'kill,linked',
		is_kill => 1,
		checkalive => "target",
		help => "drain [player]: Kills another player and gives you a random ability.",
	},
	eradicate => {
		alias => "disablebase #1 \\ superkill #1 \\ destroybody #1",
		targets => ["alive,nonself"],
		type => 'super,linked',
		status => 'disabletime',
		is_kill => 1,
		help => "eradicate [player]: Kills another player despite protection, and prevents them from ever returning to life.",
	},
	disable => {
		alias => "block #1 \\ disablebase #1",
		targets => ["alive,nonself"],
		resolvedelay => 'normal',
		status => 'disabletime',
		help => "disable [player]: Temporarily removes all of a player's abilities and characteristics, and blocks their night action.",
	},
	cpr => {
		alias => "protect #1 \\ reverseprotect #1",
		targets => ["alive,nonself"],
		is_kill => 1,
		help => "cpr [player]: If someone else tries to kill the target, they will survive. Otherwise they will die.",
	},
	wail => {
		alias => "block #1 \\ doom #1",
		targets => ["alive,nonself"],
		type => 'nonkill',
		is_kill => 1,
		help => "wail [player]: Roleblocks someone and increases their doom level. This can't be stopped by doctor protection.",
	},
	exorcise => {
		alias => "restore #1 \\ decult #1",
		targets => ["alive,nonself"],
		type => 'nonkill',
		help => "exorcise [player]: If the target is a cultist, they will die. Otherwise, they are returned to their original role and team.",
	},
	defile => {
		alias => "stealdead #1 \\ destroybody #1",
		targets => ["dead"],
		type => 'nonkill,linked',
		help => "defile [player]: Destroys a dead player's corpse and gives you one of their abilities.",
	},

	### Aliases: Fixed targets ###
	
	exchange => {
		alias => "swap #1 #S",
		targets => ["alive,nonself"],
		help => "exchange [player]: Exchanges your role with another player. The swap is permanent.",
	},
	attract => {
		alias => "redirect #1 #S",
		targets => ["alive,nonself"],
		help => "attract [player]: Changes the target of another player's night action to yourself.",
	},
	salvage => {
		alias => "giveability #S",
		targets => [],
		help => "salvage: Gives you a random one-shot night ability.",
	},
	karma => {
		alias => "copy #1 #1",
		targets => ["alive,nonself"],
		help => "karma [player]: Copies another player's night action to themself.",
	},
	halfkarma => {
		alias => "copy #1 #1 ? none",
		targets => ["alive,nonself"],
	},
	
	### Aliases: Multiple targets ###

	randomizeall => {
		alias => "randomize #*",
		targets => [],
		type => 'nonkill,multitarget,notrigger',
		help => "randomizeall: All night actions tonight will affect random targets.",
	},
	blockall => {
		alias => "block #*",
		targets => [],
		type => 'nonkill,multitarget,notrigger',
		help => "blockall: All night actions tonight will be prevented.",
	},
	giftall => {
		alias => "giveability #*",
		targets => [],
		type => 'nonkill,multitarget',
		help => "giftall: Each other player recieves a random ability.",
	},
	sacrifice => {
		alias => "superprotect #* \\ suicide",
		targets => [],
		type => 'super,notrigger',
		help => "sacrifice: You die, but all other kills tonight are prevented. Other night actions are unaffected.",
	},
	irradiate => {
		alias => "mutate #*",
		targets => [],
		type => 'super,notrigger',
		help => "irradiate: All other players recieve new roles at random.",
	},
	
	### Aliases: Random targets ###
	
	randomkill => {
		alias => "kill #?",
		targets => [],
		is_kill => 1,
		help => "randomkill: Kills a random player.",
	},
	shuffle => {
		alias => "swap #? #?",
		targets => [],
		help => "shuffle: Exchanges two random players' roles.",
	},
	cheat => {
		alias => "inspect #?",
		targets => [],
	},

	### Aliases: Automatic ###
	
	shadow => {
		alias => "clear #S \\ protect #S",
		targets => [],
		help => "shadow: You show up as town to any cop investigations, and you can't be killed unless two players try to kill you the same phase. (You can still be lynched.)",
	},
#	killresist => {
#		alias => "protect #S",
#		targets => [],
#		help => "killresist: You can't be killed unless two players try to kill you the same phase. (You can still be lynched.)",
#	},
#	extravote => {
#		alias => "addvote #S",
#		targets => [],
#		help => "extravote: You recieve an extra vote each day.",
#	},
	
	### Aliases: Placeholders ###
	
	mystery => {
		alias => "none",
		targets => ["alive,nonself"],
		is_kill => 1,
		help => "mystery [player]: You don't know what this does.",
	},
	special => {
		alias => "none",
		targets => ["alive,nonself"],
		is_kill => 1,
		help => "special [player]: This does something depending on your role.",
	},
);


sub get_mutation {
	my ($special, $target) = @_;
	
	my $theme = setup_rule('theme', $cur_setup) || 'normal';
	
	# Hack - upick gives roles from the normal theme
	$theme = 'normal' if setup_rule('upick', $cur_setup);

	# Hack - reduce liveness
	$group_data{get_player_team($target)}{alive}--;
	
	my $team = get_player_team_short($target);
	my $dofixteam = ($special =~ /fixteam/ || ($special =~ /newteam/ && $team =~ /^mafia$|^cult$/ && $group_data{get_player_team($target)}{alive} > 0));
	my $donewteam = !$dofixteam && $special =~ /newteam/;
	my @roles = map { 
		$role_config{$_}{setup} && 
		($role_config{$_}{theme} || 'normal') =~ /\b$theme\b/ &&
		!role_is_secret($_) &&
		(!$dofixteam || $role_config{$_}{setup} =~ /\b$team\b/) &&
		(!$donewteam || ($role_config{$_}{minmafia} || 0) <= ($group_data{mafia}{alive} || 0))
			? $_ : () 
	} keys %role_config;
	my $newrole;
	
	$group_data{get_player_team($target)}{alive}++;

	if (!@roles)
	{
		::bot_log "Error - no roles for mutation (special='$special', team='$team')\n";
		return;
	};
	
	do {
		$newrole = $roles[rand @roles];
	} while ($special !~ /norarity/ && $role_config{$newrole}{rarity} && rand($role_config{$newrole}{rarity}) > 1);
	
	my $newteam = get_player_team($target);
	if ($donewteam)
	{
		my @teams = map { $a = $_; $a =~ s!/.*$!!; $a } split /,/, $role_config{$newrole}{setup};
		$newteam = $teams[rand @teams];
		$newteam .= '0' if $newteam =~ /^sk|^survivor|^cult/;
	}
	
	if ($special =~ /\btemplate:(\w+)\b/)
	{
		$newrole .= "+$1";
	}

	if ($special =~ /\bsaverole\b/)
	{
		my $premutationrole = get_status($target, 'premutationrole');
		if (!$premutationrole)
		{
			$premutationrole = get_player_role($target);
			set_status($target, 'premutationrole', $premutationrole);
		}
		my @parts = recursive_expand_role($premutationrole);
		@parts = grep { $_ !~ /^\*/ } @parts;
		@parts = grep { !$role_config{$_}{status}{mutate} } @parts;
		$premutationrole = join('+', @parts);
		$newrole .= "+$premutationrole" if $premutationrole;
	}

	$newrole = canonicalize_role($newrole, 1, $newteam);
	
	return ($newrole, $newteam);
}	

sub compatible_teams {
	my ($team1, $team2) = @_;

	return 1 unless $team1 && $team2;

	my $re = join('|', map { $_ =~ s/\/.*$//; '\b' . quotemeta($_) . '\b' } split /,/, $team2);
	return scalar($team1 =~ /$re/);
}

sub get_evolution {
	my ($role, $debug) = @_;

	my @candidates;
	my %forcecandidate;

	our %evolution_cache;

	if ($evolution_cache{$role} && !$debug)
	{
		@candidates = @{$evolution_cache{$role}};

		return $role unless @candidates;
		return wantarray ? @candidates : @candidates[rand @candidates];
	}

	# Try removing bad templates
	my @roleparts = split /\+/, recursive_expand_role($role);
	foreach my $rolepart (@roleparts)
	{
		next unless $role_config{$rolepart}{template};
		my $candidate = join('+', grep { $_ ne $rolepart } @roleparts);
		push @candidates, canonicalize_role($candidate, 1);
	}

	# Look at the set evolutions
	@roleparts = split /\+/, $role;
	foreach my $rolepart (@roleparts)
	{
		my $evolveto = $role_config{$rolepart}{status}{evolveto};
		if ($evolveto)
		{
			my @evolveroles = split /,/, $evolveto;
			foreach my $evolverole (@evolveroles)
			{
				my $candidate = join('+', map { $_ eq $rolepart ? $evolverole : $_ } @roleparts);
				$candidate = canonicalize_role($candidate, 1);
				push @candidates, $candidate;
				$forcecandidate{$candidate}++;
			}
		}
	}

	# Look for a combination role
	foreach my $testrole (keys %role_config)
	{
		next unless $role_config{$testrole}{setup};
		next unless ($role_config{$testrole}{theme} || "normal") =~ /\bnormal\b/;

		my $candidate = "$role+$testrole";
		$candidate = canonicalize_role($candidate, 1);

		next if $role_config{$role} && $role_config{$candidate} && !compatible_teams($role_config{$role}{setup}, $role_config{$candidate}{setup});

		push @candidates, $candidate;
	}

	if ($role =~ /\+/)
	{
		my @parts = split /\+/, $role;
		my $parts = scalar(@parts);
		@candidates = grep { @parts = split /\+/, $_; scalar(@parts) <= $parts } @candidates;
	}
	else
	{
		@candidates = grep { $_ !~ /\+/ } @candidates;
	}

	return @candidates if $debug;

	my %rolepower;
	my $rolepower = role_power($role);
	my $targetpower = $rolepower + 0.8;
	foreach my $candidate (@candidates)
	{
		$rolepower{$candidate} = role_power($candidate);
	}

	# Eliminate roles that aren't more powerful
	@candidates = map { $rolepower{$_} > $rolepower ? $_ : ( $forcecandidate{$_} ? get_evolution($_) : () ) } @candidates;

	foreach my $candidate (@candidates)
	{
		$rolepower{$candidate} = role_power($candidate);
	}

	@candidates = grep { $rolepower{$_} > $rolepower } @candidates;

	# Eliminate duplicates
	my %count;
	@candidates = grep { ++$count{$_} <= 1 } @candidates;

	# Limit to 5 roles
	@candidates = sort { ($forcecandidate{$b} || 0) <=> ($forcecandidate{$a} || 0) || abs($rolepower{$a} - $targetpower) <=> abs($rolepower{$b} - $targetpower) } @candidates;
	@candidates = @candidates[0 .. 4] if @candidates > 5;

	$evolution_cache{$role} = \@candidates;

	return $role unless @candidates;
	return wantarray ? @candidates : @candidates[rand @candidates];
}

sub change_team {
	my ($player, $team) = @_;
	
	transform_player($player, undef, $team);
}

sub choose_random_ability {
	my ($player) = @_;
	
	my @actions = get_player_actions($player);
	@actions = grep { get_status($player, "act$_") } @actions;
	
	return undef if !@actions;
	return $actions[rand @actions];
}

sub give_ability {
	my ($player, $action, $uses) = @_;
	
	cluck("Can't give null action to $player"), return unless $action; 
	
	push @{$player_data{$player}{actions}}, $action unless grep { $_ eq $action } get_player_all_actions($player);
	
	$uses = '*' unless $uses =~ /^\d+$/;
	increase_status($player, "act$action", $uses);
	mod_notice("$player has gained the ability $action" . ($uses ne '*' ? " ($uses uses)" : ""));
}

sub remove_ability {
	my ($player, $action, $uses) = @_;
	
	reduce_status($player, "act$action", $uses);
}

sub dorecruit {
	my ($player, $newrole, $target) = @_;

	increase_safe_status($player, 'statsrecruits', 1);
	increase_safe_status($target, 'statsrecruited', 1);
	
	$newrole = get_player_role($target) unless $newrole;
	transform_player($target, $newrole, get_player_team($player), 0, $player);
	
	my $msg1 = $messages{action}{recruit1};
	$msg1 =~ s/a cult/the mafia/ if get_player_team($player) =~ /mafia/;
	$msg1 =~ s/a cult/their team/ if get_player_team($player) !~ /cult|mafia/;
	enqueue_message($target, $msg1, $player, $target);
	send_help($target, 1);
	
	my $msg2 = $messages{action}{recruit2};
	$msg2 =~ s/your cult/the mafia/ if get_player_team($player) =~ /mafia/;
	$msg2 =~ s/your cult/your team/ if get_player_team($player) !~ /cult|mafia/;
	enqueue_message($player, $msg2, $player, $target);
	
	$phases_without_kill = 0;
}

sub action_canceltimer { 		# Daz 8/5/11
	foreach my $timed (@timed_action_timers)
	{	
		unschedule(\$timed->{timer})
	}
}	
### Kills ###

sub action_kill {
	my ($player, undef, $target) = @_;
	
	# Handle the Traitor
	my $killrecruit = get_status($target, 'killrecruit');
	if ($killrecruit)
	{
		my ($newrole, $newteam) = split /,/, $killrecruit, 2;
		my $team = get_player_team_short($player);
		
		if ($team eq $newteam)
		{
			dorecruit($player, $newrole, $target);
			return;
		}
	}
		
	my $msg = $messages{death}{killed} . '.';
	$msg =~ s/#PLAYER1/$target/;
	$msg =~ s/#TEXT1//;
	announce $msg;
	kill_player($target, $player);
}

sub action_superkill {
	action_kill(@_);
}

sub action_doom {
	my ($player, $doompercent, $target) = @_;

	$doompercent = 50 unless $doompercent;
	
	increase_safe_status($target, "doomed", $doompercent);
	mod_notice("$target is now " . get_status($target, "doomed") . "% doomed.");
	
	if (get_status($target, "doomed") >= 100)
	{
		action_kill($player, "", $target);
	}
}

sub action_attack {
	my ($player, $weapondamage, $target) = @_;

	$weapondamage = 0 unless $weapondamage;

	my $weaponcharge = get_status($player, "weaponcharge");
	if ($weaponcharge) {
		$weapondamage += $weaponcharge;
		reduce_status($player, "weaponcharge", $weaponcharge);
	}

	my $maxshots = get_status($player, "weaponmaxshots");
	if ($maxshots && $maxshots > 0) {
		$weapondamage *= (1 + int(rand($maxshots)));
	}

	my $markmultiplier = get_status($player, "weaponmarkmultiplier");
	my $marked = 0;
	if ($markmultiplier && get_status($target, "marked:$player")) {
		$weapondamage *= $markmultiplier;
		reduce_status($target, "marked:$player", 1);
		$marked = 1;
	}
	
	my $critchance = get_status($player, "weaponcrit");
	if ($critchance && $markmultiplier && rand(100) < $critchance) {
		$weapondamage *= $markmultiplier;
		$marked = 1;
	}
	
	my $polarmultiplier = get_status($player, "weaponpolarmultiplier");
	if ($polarmultiplier) {
		my $polarized_by = get_status($target, "polarized_by");
		if ($polarized_by && $polarized_by ne $player) {
			$weapondamage *= $polarmultiplier;
		}
	}

	my $multiplier = get_status($player, "weaponmultiplier");
	if ($multiplier) {
		$weapondamage *= $multiplier;
	}
	
	$weapondamage = int($weapondamage);

	my $shield = get_status($target, "shield") || 0;
	$shield = $weapondamage if $shield > $weapondamage;
	$shield = 0 if $weapondamage < 0;

	# Shield is ablative
	if ($shield > 0 && $weapondamage > 0) {
		$weapondamage -= $shield;
		reduce_status($target, "shield", $shield);
		notice($target, "Your shield absorbed $shield damage.");
	}

	my $armor = get_status($target, "armor") || 0;
	$armor = $weapondamage if $armor > $weapondamage;
	$armor = 0 if $weapondamage < 0;

	# Armor is non-ablative
	if ($armor > 0 && $weapondamage > 0) {
		$weapondamage -= $armor;
	}

	my $curdamage = get_status($target, "damage") || 0;
	if ($weapondamage < 0 && $weapondamage + $curdamage < 0) {
		$weapondamage = -$curdamage;
	}

	my $weaponmsg = "";
	my $player_role = get_player_role($player);
	foreach my $role_part (split /\+/, recursive_expand_role($player_role)) {
		next unless $role_config{$role_part}{item};
		next unless $role_config{$role_part}{status}{weapon};
		$weaponmsg = $role_config{$role_part}{item_name};
		last;
	}

	my $silent = get_status($player, "weaponsilent") || 0;
	my $killed = ((get_status($target, "damage") || 0) + $weapondamage) >= (get_status($target, "hp") || 100);

	my $doompercent = get_status($player, "weapondoom") || 0;
	if ($weapondamage > 0 && $doompercent > 0) {
		increase_safe_status($target, "doomed", $doompercent);
		mod_notice("$target is now " . get_status($target, "doomed") . "% doomed.");
		if (get_status($target, "doomed") >= 100) {
			$killed = 1;
		}
	}

	if ($weapondamage > 0 || $killed) {
		my $message = "TARGET took DAMAGE damage from PLAYER.";
		$message = "TARGET took DAMAGE damage from PLAYER's $weaponmsg." if $weaponmsg;
		$message = get_status($player, "weaponmessage") || $message;
		$message = get_status($player, "weaponmarkmessage") || $message if $marked;
		$message = get_status($player, "weaponkillmessage") || $message if $killed;
		$message = get_status($player, "weaponmarkkillmessage") || $message if $marked && $killed;
		$message =~ s/PLAYER/$player/g;
		$message =~ s/DAMAGE/$weapondamage/g;
		$message =~ s/TARGET/$target/g;
		announce($message) unless $silent;

		if (get_status($player, 'weaponstun')) {
			increase_safe_status($target, "stunned", 1);
		}

		if (get_status($player, 'weaponmark')) {
			increase_safe_status($target, "marked:$player", 1);
		}

		my $weaponpulse = get_status($player, 'weaponpulse');
		if ($weaponpulse) {
			increase_safe_status($target, "pulsedamage", $weaponpulse);
		}

		if ($polarmultiplier) {
			set_safe_status($target, "polarized_by", $player);
		}

		my $vampiric = get_status($player, 'weaponvampire');
		if ($vampiric) {
			reduce_status($player, 'damage', int($vampiric * $weapondamage / 100));
		}

		apply_damage($target, $weapondamage, $player);

		if (alive($target) && get_status($target, "doomed") >= 100)
		{
			kill_player($target, $player);
		}
	}
	elsif ($weapondamage < 0) {
		my $message = "TARGET was healed DAMAGE damage by PLAYER.";
		$message = "TARGET was healed DAMAGE damage by PLAYER's $weaponmsg." if $weaponmsg;
		$message = get_status($player, "weaponhealmessage") || $message;
		$message =~ s/PLAYER/$player/g;
		$message =~ s/DAMAGE/-$weapondamage/g;
		$message =~ s/TARGET/$target/g;
		announce($message) unless $silent;

		reduce_status($target, "damage", -$weapondamage);

		# Any healing cures pulse damage
		reduce_status($target, "pulsedamage", '*');
	}
}

sub action_nuke {
	my ($player, $countdown, $target) = @_;

	$countdown = 30 unless $countdown;
	my $time = 0;
	my $timer;
	my $sub;

	$sub = sub {
		$countdown -= $time;

		return unless alive($player);

		if ($countdown <= 0) {
			announce "NUCLEAR STRIKE HITS!";

			action_kill($player, "", $target);

			foreach my $other (@alive) {
				apply_damage($other, 20, $player);
			}
		}
		else
		{
			announce "Nuclear strike in $countdown seconds!" if $countdown > 0;

			$time = int($countdown) % 10;
			$time = 10 if $time == 0;
			$time = $countdown if $countdown < 10;
			
			schedule(\$timer, $time, $sub);
		}
	};

	push @recharge_timers, \$timer;

	announce "$player called down a NUCLEAR STRIKE!";
	$sub->();
}

sub action_reverseprotect {
	my ($player, undef, $target) = @_;
	
	return unless get_status($target, 'immunekill') && get_status($target, 'immunekill') ne '*';
	
	action_kill($player, "", $target);
}

sub action_timebomb {
	my ($player, undef, $target) = @_;
	
	my $msg = $messages{action}{timebomb};
	$msg =~ s/#PLAYER2/$target/;
	announce $msg;
	kill_player($target, $player);
}

sub action_suicidebomb {
	my ($player, undef, $target) = @_;
	
	my $msg = $messages{action}{suicidebomb};
	$msg =~ s/#PLAYER1/$player/;
	$msg =~ s/#PLAYER2/$target/;
	announce $msg;
	
	if (get_status($target, 'immunekill'))
	{
		reduce_status($target, 'immunekill', 1);
	}
	else
	{
		kill_player($target, $player);
	}
	
	kill_player($player, "");
}

sub action_suicide {
	my ($player) = @_;
	
	my $msg = $messages{action}{suicide};
	$msg =~ s/#PLAYER1/$player/;
	announce $msg;
	
	# Suicides can't revive.
	reduce_status($player, 'revive', '*');
	kill_player($player, "");
}

sub action_decult {
	my ($player, undef, $target) = @_;

	return unless get_status($target, "recruited");
	
	my $msg = $messages{action}{decult};
	$msg =~ s/#PLAYER2/$target/;
	announce $msg;
	
	kill_player($target, $player);

	increase_safe_status($target, 'immuneresurrect', '*');
	increase_safe_status($target, 'immuneautopsy', '*');
}

sub action_shoot {
	my ($player, undef, $target) = @_;
	
	set_temp_status($player, 'shot', $target);
}

sub action_rock {
	my ($player, undef, $target) = @_;
	
	set_temp_status($player, 'rps', 'rock');
}

sub action_paper {
	my ($player, undef, $target) = @_;
	
	set_temp_status($player, 'rps', 'paper');
}

sub action_scissors {
	my ($player, undef, $target) = @_;
	
	set_temp_status($player, 'rps', 'scissors');
}

sub action_ignite {
	my ($player) = @_;
	
	my @targets = @alive;
	announce "A fire has broken out!";
	my $kills = 0;
	foreach my $target (@targets)
	{
		next unless get_status($target, "flammable");
		
		announce "$target has burned to death.";
		kill_player($target, $player);
		reduce_status($target, "flammable", '*');
		$kills++;
	}
	announce "Fortunately, no one was injured." unless $kills;
}

sub action_apocalypse {
	my ($player, $doompercent) = @_;

	my @targets = grep { $_ ne $player } @alive;

	for (1 .. 3)
	{
		my $target = $targets[rand @targets];
		next unless alive($target);

		action_doom($player, $doompercent, $target);
	}
}

### Protection ###

sub action_protect {
	my ($player, undef, $target) = @_;
	
	increase_temp_status($target, "immunekill", 1);
	increase_temp_status($target, "immuneinfect", 1);
}

sub action_guard {
	my ($player, undef, $target) = @_;
	
	increase_temp_status($target, "guarded_by", $player);
}

sub action_superprotect {
	my ($player, undef, $target) = @_;
	
	increase_temp_status($target, "immunekill", '*');
	increase_temp_status($target, "immunesuperkill", '*');
	increase_temp_status($target, "immuneinfect", '*');
}

sub action_hide {
	my ($player) = @_;
	
	increase_temp_status($player, 'hidden', '*');
	increase_temp_status($player, 'hidden_by', $player);
}

sub action_makehidden {
	my ($player, undef, $target) = @_;
	
	increase_temp_status($target, 'hidden', '*');
	increase_temp_status($target, 'hidden_by', $player);
}

sub action_reflectshield {
	my ($player, undef, $target) = @_;

	increase_temp_status($target, 'reflect', '*');
	increase_temp_status($target, 'reflect_by', $player);
}

sub action_timedsetstatus {
	my ($player, $set, $target) = @_;

	my @statusvalues = split /;/, $set;
	my $time = shift @statusvalues;

	my %oldvalue;

	foreach my $statusvalue (@statusvalues)
	{
		my ($status, $value) = split ',', $statusvalue, 2;
		$oldvalue{$status} = $player_data{$player}{temp}{status}{$status} || "";
		set_temp_status($target, $status, $value);
		my $level = get_status($target, "timedsetlevel:$status") || 0;
		increase_temp_status($target, "timedsetlevel:$status", 1);
		set_temp_status($target, "timedsetold:$status", $oldvalue{$status}) if $level == 0;
		
		if ($status =~ /^act(.*)/)
		{
			my $action = $1;
			push @{$player_data{$target}{actions}}, $action unless grep { $_ eq $action } get_player_all_actions($target);
		}
	}

	my $sub = sub {
		foreach my $status (keys %oldvalue) {
			my $level = get_status($target, "timedsetlevel:$status") || 0;
			reduce_status($target, "timedsetlevel:$status", 1);
			my $oldvalue = get_status($target, "timedsetold:$status");
			set_temp_status($target, $status, $oldvalue) if $level == 1;
		}
		mod_notice("${target}'s timed status expired.");
	};

	my $timer;
	push @recharge_timers, \$timer;
	schedule(\$timer, $time, $sub);
}

sub action_setstatus {
	my ($player, $set, $target) = @_;
	
	foreach my $statusvalue (split /;/, $set)
	{
		my ($status, $value) = split ',', $statusvalue, 2;
		set_temp_status($target, $status, $value);
		
		if ($status =~ /^act(.*)/)
		{
			my $action = $1;
			push @{$player_data{$target}{actions}}, $action unless grep { $_ eq $action } get_player_all_actions($target);
		}
	}
}

sub action_increasestatus {
	my ($player, $set, $target) = @_;
	
	foreach my $statusvalue (split /;/, $set)
	{
		my ($status, $value) = split ',', $statusvalue, 2;
		increase_status($target, $status, $value);
		
		if ($status =~ /^act(.*)/)
		{
			my $action = $1;
			push @{$player_data{$target}{actions}}, $action unless grep { $_ eq $action } get_player_all_actions($target);
		}
	}
}

sub action_mark {
	my ($player, undef, $target) = @_;
	set_temp_status($target, "marked:$player", 1);
}

sub action_unmark {
	my ($player, undef, $target) = @_;
	set_temp_status($target, "marked:$player", 0);
}

### Metaabilities ###

sub action_delay {
	my ($player, undef, $target) = @_;

	$player_data{$player}{delayed_actions} = [] unless $player_data{$player}{delayed_actions};

	my @save_queue = @action_queue;
	foreach my $action (@save_queue)
	{
		next unless $action->{player} eq $target;
		next if $action->{type} =~ /\bnoblock\b/;
		next if $action->{type} =~ /\bnodelay\b/;

		push @{$player_data{$player}{delayed_actions}}, $action;
		@action_queue = grep { $_ ne $action } @action_queue;

		::bot_log "  - $action->{player} $action->{action}" . ($action->{status} && length($action->{status}) <= 15 ? " ($action->{status})" : "") . " [$action->{type}] @{$action->{targets}}\n";
	}
}

sub action_trigger {
	my ($player, undef, $target) = @_;

	handle_trigger($target, get_status($target, 'ontrigger'));
	
	sort_actions();
}

sub action_release {
	my ($player, undef, $target) = @_;

	release_delayed_actions($player);
}

sub action_cancel {
	my ($player, undef, $target) = @_;

	return unless $player_data{$player}{delayed_actions};

	delete $player_data{$player}{delayed_actions};
}

sub action_block {
	my ($player, undef, $target) = @_;
	
	increase_temp_status($target, "blocked", '*');
}

sub action_disablebase {
	my ($player, $disabletime, $target) = @_;
	
	increase_safe_status($target, "disabled", $disabletime || 2);
	
	my $msg = $messages{action}{disable};
	$msg =~ s/temporarily/permanently/ if $disabletime eq '*';
	enqueue_message($target, $msg);
}

sub action_timeddisable {
	my ($player, $time, $target) = @_;

	increase_temp_status($target, "disabled", 1);
	if (get_status($target, "disabled") == 1) {
		my $msg = $messages{action}{disable};
		enqueue_message($target, $msg);
	}

	my $sub = sub {
		if (get_status($target, "disabled") == 1) {
			my $msg = $messages{action}{disable2};
			notice($target, $msg);
		}
		reduce_status($target, "disabled", 1);
	};

	my $timer;
	push @recharge_timers, \$timer;
	schedule(\$timer, $time, $sub);
}

sub action_stun {
	my ($player, undef, $target) = @_;

	increase_temp_status($target, "stunned", 1);
}

sub action_redirect {
	my ($player, undef, $target, $newtarget) = @_;
	
	foreach my $item (@action_queue)
	{
		redirect_action($item, $target, $newtarget);
	}

	set_temp_status($target, 'redirected', $newtarget);
}

sub action_redirectkill {
	my ($player, undef, $target, $newtarget) = @_;
	
	foreach my $item (@action_queue)
	{
		next unless $action_config{$item->{action}}{is_kill};
		redirect_action($item, $target, $newtarget);
	}

	set_temp_status($target, 'killredirected', $newtarget);
}

sub action_randomize {
	my ($player, undef, $target, @newtargets) = @_;
	
	foreach my $item (@action_queue)
	{
		randomize_action($item, $target, \@newtargets);
	}

	set_temp_status($target, 'randomized', '*');
}

sub action_chaos {
	my ($player) = @_;

	foreach my $target (@alive)
	{
		next if $target eq $player;
		next if rand() < 0.5;

		if (get_status($target, 'immunenonkill'))
		{
			reduce_status($target, 'immunenonkill', 1);
			next;
		}

		foreach my $item (@action_queue)
		{
			randomize_action($item, $target);
		}

		set_temp_status($target, 'randomized', '*');
	}
}
sub action_copy {
	my ($player, $status, $target, $newtarget) = @_;
	
	my @new_actions;
	
	foreach my $item (@resolved_actions, @action_queue)
	{
		my $player2 = $item->{player};
		my $action = $item->{action};
		my $group = $item->{group};
		my @targets = @{$item->{targets}};
		my $target2 = $item->{target};
		my $status2 = $item->{status};
		my $type = $item->{type};

		# Prevent a copy from affecting any action of equal or lower priority.
		# In particular, prevent a copy from affecting another copy (to prevent infinite loops).		
		next if $action_config{$action}{priority} <= $action_config{copy}{priority};

		# Unblockable actions can't be copied either
		next if $item->{type} =~ /\bnoblock\b/;
		
		if ($player_data{$player}{cur_action_type} =~ /\bnoblock\b/)
		{
			# The copied action is unblockable if the original was unblockable
			$type = $type ? ($type =~ /\bnoblock\b/ ? $type : "$type;noblock") : "noblock";
		}
		
		if ($player2 eq $target)
		{
			my @newtargets = @targets;
			
			my $user = ($status =~ /\bnoncontrol\b/) ? $player2 : $player;
			
			if (@newtargets > 0)
			{
				if ($targets[0] eq $target2)
				{
					$newtargets[0] = $newtarget;
				}
				elsif ($targets[0] eq $player2)
				{
					$newtargets[0] = $user;
				}
			}
			
			::bot_log "  * $user $action" . ($status && length($status) <= 15 ? " ($status2)" : "") . " [$type] @newtargets\n";
			
			push @new_actions, { player => $user, action => $action, group => "", targets => [@newtargets], status => $status2,
				type => $type, target => $newtarget };
		}
	}
	
	@action_queue = (@action_queue, @new_actions);
	
	sort_actions();
}

sub action_bus {
	my ($player, undef, $target1, $target2) = @_;

	my $bus1 = get_status($target1, "bussed") || $target1;
	my $bus2 = get_status($target2, "bussed") || $target2;
	
	set_temp_status($target1, "bussed", $bus2);
	set_temp_status($target2, "bussed", $bus1);
}

sub action_superbus {
	return action_bus(@_);
}

### Information ###

sub action_inspect {
	my ($player, $sanity, $target) = @_;
	
	my $inspect = get_status($target, 'inspect');
	my $result = $inspect || $player_data{$target}{team};
	$result =~ s/-ally//;
	$result =~ s/\d+$//;
	my $baseresult = $result;
	if ($result ne 'mafia' && $result ne 'town' && $sanity !~ /\bpm\b/)
	{
		$result = 'neutral';
	}
	
	$sanity = 'normal' unless $sanity;
#	::bot_log "INSPECT $player $target $sanity\n";
	if ($sanity =~ /\bnaive\b/)
	{
		$result = 'town';
	}
	elsif ($sanity =~ /\bparanoid\b/)
	{
		$result = 'mafia';
	}
	elsif ($sanity =~ /\binsane\b/)
	{
		$result = ($result eq 'town') ? 'mafia' : ($result eq 'mafia' ? 'town' : 'neutral');
	}
	elsif ($sanity =~ /\bstoned\b/)
	{
		$result = 'neutral';
	}
	elsif ($sanity =~ /\brandom\b/)
	{
		$result = (rand() < 0.5) ? 'mafia' : 'town';
	}
	elsif ($sanity =~ /\brole\b/)
	{
		my $rolename = get_status($target, 'inspectrole') || get_player_role_name($target);
		if ($rolename eq '*') {
			my $roleteam = get_status($target, 'inspect') || $player_data{$target}{team};
			$rolename = role_name(miller_role(get_player_role($target), $roleteam));
		}
		$result = ($rolename =~ /^[aeiou]/i ? "an $rolename" : "a $rolename");
	}
	elsif ($sanity =~ /\btruerole\b/)
	{
		my $rolename = get_player_role_truename($target);
		$result = ($rolename =~ /^[aeiou]/i ? "an $rolename" : "a $rolename");
	}
	elsif ($sanity =~ /\bweapon:(.*)\b/)
	{
		my $weapon = $1;
		$result = (get_player_weapon($target) eq $weapon ? "armed with a $weapon" : "not armed with a $weapon");
	}
	elsif ($sanity =~ /\bweapon\b/)
	{
		$result = (get_player_weapon($target) ? 'armed' : 'unarmed');
	}
	elsif ($sanity =~ /\bability:(.*)\b/)
	{
		my $ability = $1;
		$result = (get_status($target, "act$ability") ? "able to $ability" : "not able to $ability");
	}
	elsif ($sanity =~ /\bwolf\b/)
	{
		$result = (get_status($target, 'wolf') ? "a werewolf" : "not a werewolf");
	}
	elsif ($sanity =~ /\bcult\b/)
	{
		$result = ($baseresult eq 'cult' ? "in a cult" : "not in a cult");
	}

	if ($sanity =~ /\bpm\b/)
	{
		send_help($target, 1, $player, 1);
		increase_safe_status($player, 'statsinspects', 1);
		increase_safe_status($target, 'statsinspected', 1);
		return;
	}
	
	my $who = get_status($target, "bussed2") || $target;
	$who = "Someone" if $sanity =~ /\bnotarget\b/;
	
	my $msg = $messages{action}{inspect};
	enqueue_message($player, $msg, $player, $who, $result);
	
	increase_safe_status($player, 'statsinspects', 1);
	increase_safe_status($target, 'statsinspected', 1);
}

sub action_inspectrole {
	my ($player, undef, $target) = @_;

	action_inspect($player, "role", $target);
}

sub action_autopsy {
	my ($player, undef, $target) = @_;
	
	return if alive($target);
	
	my $killer = get_status($target, 'killedby');
	
	my $msg = ($killer ? $messages{action}{autopsy} : $messages{action}{autopsyfail});
	enqueue_message($player, $msg, $player, $target, $killer);
}
	
sub action_track {
	my ($player, $sanity, $target) = @_;
	
	#my @results = @{$player_data{$target}{cur_targets}};
	
	# Check the action queue for actual targets
	# This way, we get results after redirecters/randomizers
	my %results;
	foreach my $item (@action_queue, @resolved_actions)
	{
		next if $item->{type} =~ /\bnoblock\b/;
		my $player1 = $item->{player};
		my @targets = @{$item->{targets}};
		my $unblocked = ($item->{resolved} || !get_status($player1, 'blocked'));
		if ($player1 eq $target && !get_status($player1, 'invisible') && $unblocked && @targets)
		{
			foreach my $target (@targets)
			{
				$results{$target}++;
			}
		}
	}
	my @results = sort keys %results;
	
	my $result = join(' and ', @results);
	
	my $who = get_status($target, "bussed2") || $target;
	$who = 'Someone' if $sanity =~ /\bnotarget\b/;
	
	my $msg = ($result ? $messages{action}{track} : $messages{action}{trackfail});
	$msg =~ s/#PLAYER2/$who/;
	$msg =~ s/#TEXT3/$result/;
	enqueue_message($player, $msg, $player, $who, $result);
}

sub action_patrol {
	my ($player, $sanity, $target) = @_;
	
	#my @results = @{$player_data{$target}{cur_targets}};
	
	# Check the action queue for actual targets
	# This way, we get results after redirecters/randomizers
	my %results;
	foreach my $item (@action_queue, @resolved_actions)
	{
		next if $item->{type} =~ /\bnoblock\b/;
		my $player1 = $item->{player};
		my @targets = @{$item->{targets}};
		my $unblocked = ($item->{resolved} || !get_status($player1, 'blocked'));
		if (@targets && $target eq $targets[0] && $player1 ne $player && !get_status($player1, 'invisible') && $unblocked)
		{
			$results{$player1}++;
		}
	}
	my @results = sort keys %results;
	
	my $result = join(' and ', @results);
	
	my $who = get_status($target, "bussed2") || $target;
	$who = 'Someone' if $sanity =~ /\bnotarget\b/;

	my $msg = ($result ? "#PLAYER2 was targeted by #TEXT3." : "#PLAYER2 was not targeted by anyone.");
	enqueue_message($player, $msg, $player, $who, $result);
}

sub action_watch {
	my ($player, $sanity, $target) = @_;
	
	my $did_action = 0;
	foreach my $item (@action_queue, @resolved_actions)
	{
		next if $item->{type} =~ /\bnoblock\b/;
		my $player1 = $item->{player};
		my $action = $item->{action};
		my $unblocked = ($item->{resolved} || !get_status($player1, 'blocked'));
		if ($player1 eq $target && !get_status($player1, 'invisible') && $unblocked && $action ne 'none')
		{
			$did_action = 1;
			last;
		}
	}

	my $who = get_status($target, "bussed2") || $target;
	$who = 'Someone' if $sanity =~ /\bnotarget\b/;

	my $msg = ($did_action ? $messages{action}{watch} : $messages{action}{watchfail});
	enqueue_message($player, $msg, $player, $who);
}

sub action_eavesdrop {
	my ($player, undef, $target) = @_;
	
	set_temp_status($player, 'telepathy', $target);
}

### Status ###

sub action_frame {
	my ($player, undef, $target) = @_;
	
	increase_temp_status($target, 'inspect', 'mafia');
	increase_temp_status($target, 'inspectrole', 'Mafioso');
}

sub action_clear {
	my ($player, undef, $target) = @_;
	
	increase_temp_status($target, 'inspect', 'town');
	increase_temp_status($target, 'inspectrole', 'Townie');
}

sub action_destroybody {
	my ($player, undef, $target) = @_;

	increase_safe_status($target, 'immuneall', '*');
}

sub action_poison {
	my ($player, $time, $target) = @_;
	
	$time = 2 unless $time;
	set_safe_status($target, 'poisoned', $time);
}

sub action_antidote {
	my ($player, undef, $target) = @_;
	
	reduce_status($target, 'poisoned', '*');
}

sub action_prime {
	my ($player, undef, $target) = @_;
	
	set_safe_status($target, 'flammable', '*');
}

### Special ###

sub action_message {
	my ($player, $message, $target) = @_;

	enqueue_message($target, $message, $player);
}

sub action_announce {
	my ($player, $message, $target) = @_;
	$message =~ s/PLAYER/$player/g;
	$message =~ s/TARGET/$target/g;
	announce($message);
}

sub action_clearphaseaction {
	my ($player) = @_;

	$player_data{$player}{phase_action} = "";
}

### Transformation ###

sub action_transform {
	my ($player, $role) = @_;
	
	my ($newrole, $newteam) = split(/,/, $role, 2);
	
	transform_player($player, $newrole, $newteam);
	enqueue_message($player, $messages{action}{transform});
	send_help($player, 1);
}

sub action_buddy {
	my ($player, undef, $target) = @_;
	
	$player_data{$player}{buddy} = $target;
}

sub action_setbuddy {
	my ($player, undef, $target, $buddy) = @_;

	$player_data{$target}{buddy} = $buddy;
}

sub action_transform2 {
	my ($player, $role, $buddy) = @_;
	
	my ($newrole, $newteam) = split(/,/, $role, 2);
	
	transform_player($player, $newrole, $newteam);
	$player_data{$player}{buddy} = $buddy;
	enqueue_message($player, $messages{action}{transform});
	send_help($player, 1);
}

sub action_evolve {
	my ($player, undef, $target) = @_;
	
	my $oldrole = get_player_role($target);
	my $newrole = get_evolution($oldrole);
	
	if ($newrole ne $oldrole)
	{
		transform_player($target, $newrole);
		enqueue_message($target, $messages{action}{transform});
		send_help($target, 1);
	}
	elsif (get_status($target, 'transform'))
	{
		action_transform($target, get_status($target, 'transform'));
	}
}

sub action_recruit {
	my ($player, $special, $target) = @_;

	my ($newrole, $flags) = split /,/, $special, 2;
	$newrole = get_player_role($target) unless $newrole;
	$flags = "" unless $flags;
	
	if ($player_data{$target}{team} eq 'town')
	{
		dorecruit($player, $newrole, $target);
		set_safe_status($target, 'recruited', '*') unless $flags  =~ /\bnofollowerdeath\b/;
	}
	else
	{
		if ($flags =~ /\bdieonfail\b/)
		{
			my $msg = $messages{death}{killed} . '.';
			$msg =~ s/#PLAYER1/$player/;
			$msg =~ s/#TEXT1//;
			announce $msg;
			kill_player($player, $target);
		}
		else
		{
			my $msgfail = $messages{action}{recruitfail};
			enqueue_message($player, $msgfail);
		}
	}
}

sub action_superrecruit {
	my ($player, $newrole, $target) = @_;
	
	if ($player_data{$target}{team} ne get_player_team($player))
	{
		dorecruit($player, $newrole, $target);
	}
	else
	{
		my $msgfail = $messages{action}{recruitfail};
		enqueue_message($player, $msgfail);
	}
}

sub action_infect {
	my ($player, $role, $target) = @_;
	
	$role = get_player_role($player) unless $role;
	$role = get_player_role($player) if $role eq '*';
	
	if (get_player_role($target) ne $role)
	{
		transform_player($target, $role);
		
		my $msg1 = "You have been infected by a disease.";
		enqueue_message($target, $msg1, $player, $target);
		send_help($target, 1);
		
		$phases_without_kill = 0;
	}
}

sub action_curse {
	my ($player, $role, $target) = @_;
	
	$role = get_player_role($player) unless $role;
	$role = get_player_role($player) if $role eq '*';
	
	if (get_player_role($target) ne $role)
	{
		transform_player($target, $role);
		
		my $msg1 = "You have been cursed.";
		enqueue_message($target, $msg1, $player, $target);
		send_help($target, 1);
	}
}

sub action_transformother {
	my ($player, $role, $target) = @_;
	
	my ($newrole, $newteam) = split(/,/, $role, 2);
	$newteam = get_player_team($target) unless $newteam;
	$newrole = canonicalize_role($newrole, 1, $newteam) unless $newrole =~ /\+|=/;
	
	if (get_player_role($target) ne $newrole || $newteam)
	{
		transform_player($target, $newrole, $newteam);
		enqueue_message($target, $messages{action}{transform});
		send_help($target, 1);
	}
}

sub action_silentinfect {
	my ($player, $role, $target) = @_;
	
	$role = get_player_role($player) unless $role;
	$role = get_player_role($player) if $role eq '*';
	
	if (get_player_role($target) ne $role)
	{
		transform_player($target, $role);
	}
}

sub action_psych {
	my ($player, undef, $target) = @_;
	
	my ($oldteam, $newrole, $newteam) = split /,/, get_status($player, "convert");
	$oldteam = 'sk' unless $oldteam;
	$newrole = get_player_role($target) unless $newrole;
	$newteam = get_player_team($player) unless $newteam;
	
	if (get_player_team_short($target) eq $oldteam)
	{
		transform_player($target, $newrole, $newteam);
		my $rolename = get_player_role_name($target);
		
		my $msg1 = $messages{action}{psych1};
		enqueue_message($target, $msg1, $player, $target, "a $rolename");
		send_help($target, 1);
		#::bot_log "$msg1\n";
		
		my $msg2 = $messages{action}{psych2};
		my $who = get_status($target, "bussed2") || $target;
		$msg2 =~ s/#PLAYER2/$who/;
		enqueue_message($player, $msg2, $player, $target);
		#::bot_log "$msg2\n";
		
		$phases_without_kill = 0;
	}
}

sub action_possess {
	my ($player, undef, $target) = @_;
	
	if ($player ne $target)
	{
		my $action = $player_data{$player}{cur_action};
		my $uses = get_status($player, "act$action");
		
		change_team($target, get_player_team($player));
		give_ability($target, $action, $uses) if $uses;

		adjust_player_role_after_change($target);
		
		my $msg1 = "You have been possessed by #PLAYER1. You may choose to possess another player at night. You will die but your target will join your team and gain this ability.";
		enqueue_message($target, $msg1, $player, $target);
		send_help($target, 1);
		
		action_kill($target, "", $player);
	}
}

sub action_mutate {
	my ($player, $special, $target) = @_;

	my $action = $player_data{$player}{cur_action};
	my $uses = get_status($player, "act$action");
	
	my ($newrole, $newteam) = get_mutation($special, $target);
	return unless $newrole;
	
	transform_player($target, $newrole, $newteam);
	enqueue_message($target, $messages{action}{transform});

	if ($special =~ /keepaction/ && $action)
	{
		my $shortaction = action_base($action);
		give_ability($target, $action, $uses);
		set_status($target, $action_config{$shortaction}{status}, $special) if $action_config{$shortaction}{status};
	}
	
	send_help($target, 1);
}

sub action_morph {
	my ($player, $morphstatus, $target) = @_;
	
	my $action = $player_data{$player}{cur_action};
	my $uses = get_status($player, "act$action");

	my %oldstatus;
	foreach my $statusvalue (split /;/, $morphstatus)
	{
		my ($status, $value) = split /,/, $statusvalue, 2;
		$oldstatus{$status} = get_status($player, $status);
	}

	# Copy the player, except for groups. Give group actions as normal actions.
	$player_data{$player}{role} = $player_data{$target}{role};
	$player_data{$player}{actions} = [ get_player_all_actions($target) ];
	$player_data{$player}{status} = { %{ $player_data{$target}{status} } };
	
	# Unset group* so that group actions don't use the action for the group
	foreach my $key (keys %{$player_data{$player}{status}})
	{
		delete $player_data{$player}{status}{$key} if $key =~ /^group/;
	}
	
	# Set group action uses for the morpher (in case a mafia ends up as morpher)
	collect_player_group_actions($player);
	initialize_player_action_uses($player, 'group_actions');
	
	# Give the morph ability
	give_ability($player, $action, $uses) if $uses;
	
	# Special: the morpher appears to be the player they morphed into to all inspections, and on death
	set_status($player, 'rolename',    get_player_role_name($target));
	set_status($player, 'roletruename',get_player_role_truename($target));
	set_status($player, 'roletext',    get_status($target, 'roletext'));
	set_status($player, 'inspect',     get_status($target, 'inspect')     || get_player_team($target));
	set_status($player, 'inspectrole', get_status($target, 'inspectrole') || get_player_role_name($target));
	set_status($player, 'weapon',      get_player_weapon($target)         || "none");
	set_status($player, 'deathrole',   get_status($target, 'deathrole')   || get_player_role_truename($target));
	set_status($player, 'deathteam',   get_status($target, 'deathteam')   || get_player_team_short($target));
	
	# Copy some statuses from the old role if necessary
	foreach my $statusvalue (split /;/, $morphstatus)
	{
		my ($status, $value) = split /,/, $statusvalue, 2;
		$value = $oldstatus{$status} unless defined $value;
		if ($status =~ /^act(.*)$/) {
			give_ability($player, $1, $value);
		}
		else {
			increase_status($player, $status, $value);
		}
		mod_notice("Preserving ${player}'s $status of $value");
	}
	
	enqueue_message($player, $messages{action}{transform});
	send_help($player, 1);
}

sub action_stealitem {
	my ($player, undef, $target) = @_;

	my $target_role = get_player_role($target);
	my @target_role_parts = split /\+/, recursive_expand_role($target_role);

	my $player_role = get_player_role($player);

	my @items = grep { $role_config{$_}{item} && valid_template($_, $player_role) } @target_role_parts;

	if (!@items) {
		enqueue_message($player, $messages{action}{stealfail});
		return;
	}

	my $item_template = $items[rand @items];

	@target_role_parts = grep { $_ ne $item_template } @target_role_parts;
	my $charges = 1;

	my $chargestatus = $role_config{$item_template}{item_chargestatus};
	if ($chargestatus)
	{
		$charges = get_status($target, $chargestatus) || 0;
	}

	handle_trigger($target, get_status($target, "ondrop"));
	handle_trigger($target, get_status($target, "ondrop:$item_template"));

	transform_player($target, canonicalize_role(join('+', @target_role_parts), 0));
	transform_player($player, canonicalize_role("$player_role+$item_template", 0));

	if ($chargestatus)
	{
		set_status($player, $chargestatus, $charges);
	}

	my $desc = $role_config{$item_template}{item_name};

	my $msg1 = "Your #TEXT3 was stolen!";
	enqueue_message($target, $msg1, $player, $target, $desc);
		
	my $msg2 = "You stole a #TEXT3.";
	enqueue_message($player, $msg2, $player, $target, $desc);		
	send_help($player, 1);
}

sub action_steal {
	my ($player, $ability, $target) = @_;

	my $maxuses = get_status($player, "stealuses");

	if ($ability && $ability =~ /^\d+$/) {
		$maxuses = $ability;
		$ability = undef;
	}

	$ability = choose_random_ability($target) unless $ability;
	
	if (defined($ability))
	{
		my $uses = get_status($target, "act$ability");
		$uses = $maxuses if $maxuses && ($uses eq '*' || $uses > $maxuses);

		return unless $uses;
		
		::bot_log "STEAL $player $target $ability $uses\n";
	
		give_ability($player, $ability, $uses);
		remove_ability($target, $ability, $uses);

		my $desc = describe_ability($player, $ability);		
		
		# Copy some important statuses
		my $shortability = action_base($ability);
		my $status = $action_config{$shortability}{status};
		foreach my $status ($action_config{$shortability}{status}, "replace$ability", "failure$ability", "failure$shortability")
		{
			next unless $status;
			set_status($player, $status, get_status($target, $status)) if get_status($target, $status) && !get_status($player, $status);
		}
	
		my $msg1 = $messages{action}{steal1};
		enqueue_message($target, $msg1, $player, $target, $desc);
		
		my $msg2 = $messages{action}{steal2};
		enqueue_message($player, $msg2, $player, $target, $desc);		
	}
	else
	{
		my $msgfail = $messages{action}{stealfail};
		enqueue_message($player, $msgfail);
	}
}

sub action_stealdead {
	action_steal(@_);
}

sub action_copyabilityto {
	my ($player, $uses, $target, $recipient) = @_;
	
	my $ability = $player_data{$target}{phase_action};
	
	if ($ability)
	{
		$uses = '*' unless defined($uses);
		::bot_log "GIVE $player $target $ability $uses\n";
	
		give_ability($recipient, $ability, $uses);

		my $desc = describe_ability($recipient, $ability);		
		
		# Copy some important statuses
		my $shortability = action_base($ability);
		foreach my $status ($action_config{$shortability}{status}, "replace$ability", "failure$ability")
		{
			next unless $status;
			set_status($recipient, $status, get_status($target, $status)) if get_status($target, $status) && !get_status($recipient, $status);
		}
	
		my $msg2 = $messages{action}{steal2};
		enqueue_message($recipient, $msg2, $player, $target, $desc);		
	}
#	else
#	{
#		my $msgfail = $messages{action}{stealfail};
#		enqueue_message($recipient, $msgfail);
#	}
}
sub action_swap {
	my ($player, undef, $target1, $target2) = @_;
	
	return if $target1 eq $target2;
	
	swap_roles($target1, $target2);
	
	enqueue_message($target1, $messages{action}{swap});
	send_help($target1, 1);
	enqueue_message($target2, $messages{action}{swap});
	send_help($target2, 1);
}

sub action_giveability {
	my ($player, $gift, $target, $copyfrom) = @_;
	
	my @abilities = split /,/, ($gift || "kill:1,protect:1,inspect:1,block:1");
	
	my $silent = 0;
	if ($abilities[0] eq 'silent')
	{
		$silent = 1;
		shift @abilities;
	}

	@abilities = grep { my $uses = get_status($target, "act$_"); $uses ne '*' } @abilities;
	
	return unless @abilities;

	my $option = $abilities[rand @abilities];
	my %statusextra;
	%statusextra = split /:/, $1 if $option =~ s/\((.*)\)$//;
	my ($ability, $uses) = split /:/, $option;
	$uses = '*' unless $uses;
	
	::bot_log "GIVE $player $target $ability $uses\n";

	my $prevuses = get_status($target, "act$ability");
	
	give_ability($target, $ability, $uses);
	
	my $baseability = action_base($ability);
	my $status = $action_config{$baseability}{status};
	
	if (!$prevuses)
	{
		if ($status)
		{
			$copyfrom = $player unless defined($copyfrom);
			set_status($target, $status, get_status($player, "give$status") || get_status($copyfrom, $status));
		}
		foreach my $status (keys %statusextra)
		{
			set_status($target, $status, $statusextra{$status});
		}
	}
	
	my $who = get_status($target, "bussed2") || $target;
	
	my $desc = describe_ability($target, $ability);
	my $msg1 = $messages{action}{steal2};
	enqueue_message($target, $msg1, $player, $who, $desc);

	if ($player ne $target && !$silent)
	{
		my $msg2 = "You have given #PLAYER2 the ability: #TEXT3\n";
		enqueue_message($player, $msg2, $player, $who, $desc);
	}
}

sub action_restore {
	my ($player, undef, $target) = @_;
	
	# Don't restore cultists
	return if get_status($target, 'recruited');
	
	if (get_player_role($target) ne $player_data{$target}{startrole} ||
	    get_player_team($target) ne $player_data{$target}{startteam})
	{
		transform_player($target, $player_data{$target}{startrole}, $player_data{$target}{startteam});
		enqueue_message($target, $messages{action}{transform});
		send_help($target, 1);
	}
}

### Miscellaneous ###

sub action_defuse {
	my ($player, undef, $target) = @_;
	
	foreach my $timed (@timed_action_timers)
	{
		next unless $timed->{action} eq 'timebomb';
		next unless $timed->{targets}[0] eq $target;
		
		unschedule(\$timed->{timer});
		
		my $msg = $messages{action}{timedefuse};
		announce $msg;
		
		# Only defuse one timebomb
		return;
	}
}

sub action_resurrect {
	my ($player, undef, $target) = @_;
	
	return if alive($target);
	
	$player_data{$target}{alive} = 1;

	my $msg1 = $messages{action}{resurrect1};
	$msg1 =~ s/#PLAYER2/$target/;
	announce $msg1;
	
	enqueue_message($target, $messages{action}{resurrect2});

	# A player can't be brought back twice
	set_safe_status($target, 'immuneresurrect', '*');

	calculate_group_members();
	calculate_alive();
	
	increase_safe_status($player, 'statsresurrects', 1);
	increase_safe_status($target, 'statsresurrected', 1);
}

sub action_friend {
	my ($player, undef, $target) = @_;

	my $msg = $messages{action}{friend};
	my $group = get_player_team_short($player);
	$msg =~ s/#PLAYER1/$player/;
	$msg =~ s/#TEXT1/$group/;
	enqueue_message($target, $msg);
}

sub action_pardon {
	my ($player, undef, $target) = @_;
	
	set_temp_status($target, 'onlynch', 'revive');
}

sub action_addvote {
	my ($player, undef, $target) = @_;
	
	set_safe_status($target, 'extravote', (get_status($target, 'extravote') || 0) + 1);
	
	my $msg = $messages{action}{addvote};
	enqueue_message($target, $msg);
}

sub action_subvote {
	my ($player, undef, $target) = @_;
	
	set_safe_status($target, 'extravote', (get_status($target, 'extravote') || 0) - 1);
	
	my $msg = $messages{action}{subvote};
	enqueue_message($target, $msg);
}

sub action_proclaim {
	my ($player, undef, $target) = @_;
	
	set_safe_status($target, 'extravote', (get_status($target, 'extravote') || 0) + 1);
	
	my $msg = $messages{action}{addvote};
	enqueue_message($target, $msg);
	announce "A new King has been proclaimed! All hail King $target!";
	update_voiced_players();
}

sub action_forcevote {
	my ($player, undef, $target, $votee) = @_;
	
	::bot_log "FORCEVOTE $player $votee\n";
	set_safe_status($target, 'votelocked', $votee);
	
	return unless $phase eq 'day';
	
	remove_votes($target);
	set_votes($target, ($votee) x get_player_votes($target));
	vote_count();
}

sub action_census {
	my ($player, $sanity) = @_;
	
	my %item_count;
	my $total = 0;
	my $itemlist;
	my $where = "alive";
	my %plural;
	
	$sanity = "team" unless $sanity;

	if ($sanity eq 'team')
	{
		$itemlist = "no players";
		foreach my $player (@alive)
		{
			my $team = get_player_team_short($player);
			$item_count{$team}++;
			$total++;
			$plural{$team} = $team;
		}
	}
	elsif ($sanity eq 'weapon')
	{
		$itemlist = "no weapons";
		$where = "in use";
		foreach my $player (@alive)
		{
			my $weapon = get_player_weapon($player);
			next unless $weapon;
			$item_count{$weapon}++;
			$total++;
		}
	}
	elsif ($sanity eq 'item')
	{
		$itemlist = "no items";
		$where = "in use";
		foreach my $player (@alive)
		{
			my @role_parts = recursive_expand_role(get_player_role($player));
			foreach my $template (@role_parts)
			{
				next unless exists $role_config{$template};
				next unless $role_config{$template}{item};
				$item_count{$role_config{$template}{item_name}}++;
				$total++;
			}
		}
	}
	elsif ($sanity =~ /^act(.*)$/)
	{
		my $action = $1;
		$itemlist = "no players who can $action";
		$itemlist = "no cops" if $action eq 'inspect';
		$itemlist = "no doctors" if $action eq 'protect';
		$itemlist = "no roleblockers" if $action eq 'block';
		foreach my $player2 (@alive)
		{
			my $backupactions = get_status($player2, "backupactions");

			my $is_primary = 0;
			my $is_backup = 0;

			my @actions = get_player_actions($player2);
			@actions = map { action_base($_) } @actions;
			@actions = map { (get_status($player2, "replace$_"), $_) } @actions;
			
			# Count backups
			$is_backup = grep { $_ =~ /\b$action\b/ } split /,/, $backupactions if $backupactions;
			$is_primary = grep { $_ =~ /\b$action\b/ } @actions;
			
			if ($is_primary || $is_backup)
			{
				my $role = get_player_role_truename($player2);
				$item_count{$role}++;
				$total++;
				$plural{$role} = get_player_role_plural($player2);
			}
		}
	}
	else
	{
		my $team = $sanity;
		$itemlist = "no living players";
		$where = "in the $team";
		($itemlist = "no serial killers"), ($where = "at large") if $team eq 'sk';
		foreach my $player2 (@alive)
		{
			if (get_player_team_short($player2) eq $team)
			{
				my $role = get_player_role_truename($player2);
				$item_count{$role}++;
				$total++;
				$plural{$role} = get_player_role_plural($player2);
			}
		}
	}
	
	my @itemlist = map {
		"$item_count{$_} " . ($item_count{$_} == 1 ? $_ : $plural{$_} || "${_}s" ) 
	} sort keys %item_count;
	my $numitems = scalar(@itemlist);
	
	$itemlist = $itemlist[0] if $numitems == 1;
	$itemlist = $itemlist[0] . ' and ' . $itemlist[1] if $numitems == 2;
	$itemlist = join(", ", @itemlist[0..$#itemlist-1]) . ', and ' . $itemlist[$#itemlist] if $numitems >= 3;
	
	my $msg;
	$msg = ($total == 1 ? "There is $itemlist $where." : "There are $itemlist $where.");
	
	enqueue_message($player, $msg);
}

sub action_winonlynch {
	my ($player, undef, $target) = @_;
	
	set_temp_status($target, 'onlynch', 'lyncherwinssoft');
	set_temp_status($target, 'lyncher', get_player_team($player));
}

sub action_reload {
	my ($player) = @_;

	my @roleparts = split /\+/, recursive_expand_role(get_player_role($player));

	foreach my $part (@roleparts) {
		my $actions = $role_config{$part}{actions};
		next unless $actions;

		foreach my $action (@$actions) {
			my $baseaction = $action;

			my $uses = '*';
			$uses = $1 if $baseaction =~ s/;(\d+)$//;

			next if $baseaction =~ /reload/;

			# mod_notice("Reloading ${player}'s $baseaction");
			set_status($player, "act$baseaction", $uses);
		}
	}
}

sub action_charge {
	my ($player, $amount) = @_;

	my $maxcharge = get_status($player, "maxcharge") || 100;
	return if get_status($player, "weaponcharge") >= $maxcharge;

	increase_temp_status($player, "weaponcharge", $amount);
	my $currentcharge = get_status($player, "weaponcharge");
	if ($currentcharge > $maxcharge) {
		decrease_status($player, "weaponcharge", $currentcharge - $maxcharge);
		$currentcharge = $maxcharge;
	}
	enqueue_message($player, "Your weapon is charged (+$currentcharge)") if $currentcharge > 0;
}

sub action_safeclaim {
	my ($player) = @_;

	my $setup = $cur_setup;

	my $weirdness = setup_rule('weirdness', $setup); 
	$weirdness = rand(1.0) if setup_rule('randomweirdness', $setup);
	
	my %power = (town => rand(1.0));

	my %rolecount;

	foreach my $other (@players) {
		$rolecount{get_player_role($other)}++;
	}

	my @claims = map { $_->{role} } select_roles($setup, { townnormal => 4, townpower => 0, townbad => 0, sk => 0, survivor => 0, cult => 0, mafia => 0, mafia2 => 0, wolf => 0 }, $weirdness, scalar(@players), 1, \%power);

	shift @claims while @claims && $rolecount{$claims[0]};

	# mod_notice("Safe claims: @claims");

	if (@claims)
	{
		enqueue_message($player, "The following role does not appear in the setup:");
		enqueue_message($player, role_help_text($claims[0]));
	}
}

sub action_truthsay { # Daz 8/5/11 (WIP)
	my ($player, undef, $target) = @_;
		
	reduce_status($target, "doomed", '*')
}

