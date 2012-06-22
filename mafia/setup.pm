package mafia;

use strict;
use warnings;
no warnings 'redefine', 'qw';
use sort 'stable';
use Carp qw(cluck);

use String::Similarity;
use IO::Handle;
use Fcntl ':flock';

our (%role_config, %action_config, %group_config);
our (@funny_roles);

our %setup_config = (
	normal => {
		hidden => 1,
		randomweirdness => 1,
		allowwolf => 1,
		numalts3 => 12,
		start3_1  => "day", roles3_1  => [qw"t t m/mafia"],
		start3_2  => "day", roles3_2  => [qw"t ss,ssq m/mafia"],
		start3_3  => "day", roles3_3  => [qw"t fri m/mafia"],
		start3_4  => "day", roles3_4  => [qw"t jud m/mafia"],
		start3_5  => "day", roles3_5  => [qw"ss,fri jud m/mafia"],
		start3_6  => "day", roles3_6  => [qw"t,ss cday,cdayr m/mafia"],
		start3_7  => "day", roles3_7  => [qw"cday cdayi,cdayp,cdayn cday/mafia"],
		start3_8  => "day", roles3_8  => [qw"t,ss sv/survivor m/mafia"],
		start3_9  => "day", roles3_9  => [qw"t,v1 v1 red1/mafia"],
		start3_10 => "day", roles3_10 => [qw"t,tq t,tq sk/sk"],
		start3_11 => "day", roles3_11 => [qw"sk/sk1 v1,sk/sk2 red1/mafia"],
		start3_12 => "day", roles3_12 => [qw"t,trefq,ss saul/mafia-ally,ghost1 m/mafia"],
		start3_13 => "day", roles3_13 => [qw"rv1q,red1 t,v1 m/mafia,sk/sk"],
		help => "normal: The default setup, with a balanced mix of roles.",
		randomok => 1,
	},
	straight => {
		basic => 1,
			(setup_rule('theme', $b) && 1) <=> (setup_rule('theme', $a) && 1) ||
		weirdness => 0,
		noneutral => 1,
		nobastard => 1,
		townpowermult => 0.9,
		start => "day",
		help => "straight (3+ players): Only Townies, sane Cops, Doctors, Vigilantes, Roleblockers, Mafiosos, and Godfathers appear. Unlike most setups, games begin with day.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	mild => {
		basic => 1,
		weirdness => 0.2,
		nobastard => 1,
		townpowermult => 1,
		help => "mild: Most roles are basic, with only a few unusual roles. Serial killers, survivors, and cults are rare. Roles with secret properties don't appear.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	average => {
		basic => 1,
		weirdness => 0.5,
		allowwolf => 1,
		help => "average: There is a mix of basic and unusual roles.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	wacky => {
		basic => 1,
		weirdness => 0.9,
		allowwolf => 1,
		help => "wacky: Most roles are unusual, though basic roles still appear.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	insane => {
		basic => 1,
		weirdness => 1,
		nolimits => 1,
		help => "insane: All roles are possible, even completely useless ones.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	unranked => {
		basic => 1,
		nobastard => 1,
		noneutral => 1,
		nosurvivor => 1,
		weirdness => 0,
		townpowermult => 1,
		help => "unranked: Designed for new players as games of this don't count against your overall ranking. ",
	},
	oddrole => {
		minplayers => 3,
		weirdness => 1,
		oddrole => 1,
		# exp => 2,
		# allowwolf => 1,
		help => "oddrole: Common roles are rare, and rare roles are common.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	chosen => {
		weirdness => 1,
		teamweirdness => 0.5,
		exp => 0.6,
		nobastard => 1,
		rolechoices => 4,
		maxchoices => 3,
		help => "chosen: Each player gets a choice between up to three roles at the beginning of the game. Roles with secret properties don't appear.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	multirole => {
		enable_on_days => "25", # Tuesday, Friday
		minplayers => 3,
		maxplayers => 12,
		weirdness => 1,
		teamweirdness => 0.5,
		exp => 0.6,
		multiroles => 3,
		help => "multirole (3-12 players): Some players may recieve combination roles. WARNING: Not all combination roles work correctly, play at your own risk.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	multichosen => {
		enable_on_days => "25", # Tuesday, Friday
		minplayers => 3,
		maxplayers => 12,
		weirdness => 1,
		teamweirdness => 0.5,
		exp => 0.6,
		nobastard => 1,
		rolechoices => 3,
		maxchoices => 2,
		multiroles => 3,
		help => "multichosen (3-12 players): Each player gets a choice between up to two roles at the beginning of the game, which may be combination roles. Roles with secret properties don't appear.",
		realok => 1,
	},
	mm => {
		minplayers => 3,
		weirdness => 0.3,
		teamweirdness => 0.4,
		exp => 0.75,
		multiroles => 2,
		randomok => 1,
		minplayersrandom => 4,
		help => "mm: Mostly common roles are used, but some players might get roles that don't appear in normal games.",
		realok => 1,
	},
	mixed => {
		minplayers => 3,
		maxplayers => 12,
		randomweirdness => 1,
		teamweirdness => 0.5,
		exp => 0.2,
		multiroles => 2,
		randomok => 1,
		minplayersrandom => 4,
		help => "mixed (3-12 players): A somewhat unpredictable setup.",
		realok => 1,
	},
	screwball => {
		minplayers => 4,
		maxplayers => 12,
		weirdness => 1,
		teamweirdness => 0.4,
		exp => 0.75,
		multiroles => 3,
		nonight => 1,
		deepsouth => 1,
		start => "day",
		minplayersrandom => 4,
		help => "screwball (4-12 players): Nightless setup. Role assignment in this setup is roughly equivalent to wacky  multirole.",
	},
	chaos => {
		enable_on_days => "25", # Tuesday, Friday
		minplayers => 4,
		maxplayers => 7,
		weirdness => 1,
		nolimits => 1,
		exp => 0,
		multiroles => 4,
		help => "chaos (4-7 players): A setup unconstrained by the burdens of sanity, correctness, or playability. YOU HAVE BEEN WARNED.",
		realok => 1,
	},
	martian => {
		hidden => 1,
		minplayers => 8,
		maxplayers => 12,
		weirdness => 1,
		exp => 0,
		multiroles => 4,
		nobastard => 1,
		realok => 1,
	},
	tornado => {
		hidden => 1,
		minplayers => 8,
		maxplayers => 12,
		weirdness => 0.9,
		exp => 0.3,
		multiroles => 2,
		nobastard => 1,
		nobad => 1,
		realok => 1,
	},
	luigi => {
		minplayers => 3,
		maxplayers => 12,
		weirdness => 1,
		nolimits => 1,
		rolechoices => 4,
		maxchoices => 3,
		realok => 1,
		help => "luigi (3-12 players): A chosen setup, where roles are roughly equivalent to insane.",
	},
	xylspecial => {
		minplayers => 3,
		maxplayers => 20,
		weirdness => 1,
		teamweirdness => 0.5,
		oddrole => 1,
		rolechoices => 6,
		maxchoices => 4,
		help => "xylspecial (3-20 players): Each player gets a choice between up to four roles, most of them unusual.",
		randomok => 1,
		realok => 1,
	},
	deliciouscake => {
		enable_on_days => "25", # Tuesday, Friday
		maxplayers => 12,
		weirdness => 1,
		teamweirdness => 0.6,
		oddrole => 1,
		multiroles => 2,
		help => "deliciouscake (3-12 players): Anyways this cake is great, it's so delicious and moist.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	australian => {
		enable_on_days => "25", # Tuesday, Friday
		minplayers => 4,
		maxplayers => 12,
		weirdness => 1,
		teamweirdness => 0.6,
		oddrole => 1,
		multiroles => 2,
		rolechoices => 3,
		maxchoices => 3,
		help => "australian (4-12 players): They do things differently down under. Dedicated to everybody's favourite Australian, Lukion!",
		realok => 1,
	},
#	loransucks => {
#		enable_on_days => "x", # never
#		hidden => 1,
#		minplayers => 4,
#		maxplayers => 7,
#		weirdness => 1,
#		nolimits => 1,
#		exp => 0,
#		multiroles => 4,
#		rolechoices => 3,
#		maxchoices => 3,
#	},
	balanced => {
		basic => 1,
		weirdness => 0.75,
		teamweirdness => 0.25,
		allowwolf => 1,
		nobastard => 1,
		exp => 1,
		help => "balanced: This setup is similar to mild, but uses an expanded pool of common roles. Roles with secret properties don't appear.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	noreveal => {
		minplayers => 4,
		weirdness => 1,
		teamweirdness => 0.25,
		allowwolf => 1,
		hidedeath => 1,
		exp => 1,
		help => "noreveal (4+ players): This is a normal setup, but players' roles and teams are not revealed on death.",
		realok => 1,
	},
	"neko-open" => {
		minplayers => 4,
		weirdness => 0.25,
		teamweirdness => 0.5,
		allowwolf => 1,
		nobastard => 1,
		hidedeath => 1,
		"open" => 1,
		townpowermult => 0.5,
		exp => 1,
		help => "neko-open (4+ players): The roles in the setup are announced at the beginning of the game, but individual players' roles are not revealed on death.",
		realok => 1,
	},
	semiopen => {
		minplayers => 4,
		randomweirdness => 1,
		teamweirdness => 0.5,
		nobastard => 1,
		"semiopen" => 1,
		help => "semiopen (4+ players): A list of possible roles in the setup is announced at the beginning of the game.",
		realok => 1,
	},
	cosmic => {
		minplayers => 4,
		weirdness => 1,
		teamweirdness => 0.5,
		exp => 1,
		theme => "cosmic",
		baseroles => {
			t => 'theme_cosmic_macron',
			m => 'theme_cosmic_sniveler',
			sk => 'theme_cosmic_assassin',
		},
		help => "cosmic: A theme setup based on the board game Cosmic Encounter.",
		minplayersrandom => 4,
		fakeok => 1,
	},
	timespiral => {
		minplayers => 4,
		weirdness => 1,
		teamweirdness => 0.5,
		exp => 1,
		theme => "timespiral",
		start => "day",
		mafiaactions => "mafiakill,xsafeclaim;1",
		"mafia-allyactions" => "mafiakill,xsafeclaim;1",
		skactions => "xsafeclaim;1",
		survivoractions => "xsafeclaim;1",
		cultactions => "xsafeclaim;1",
		baseroles => {
			t => 'theme_timespiral_assemblyworker',
			m => 'theme_timespiral_spinneretsliver',
			sk => 'theme_timespiral_nightshadeassassin',
		},
		help => "timespiral: A theme setup based on Time Spiral block cards from Magic: The Gathering. Special mechanics include morphs with one-shot abilities, suspended roles that gain abilities after several days, and slivers that share abilities with each other.",
		fakeok => 1,
	},
	upick => {
		minplayers => 3,
		weirdness => 0.9,
		theme => "upick",
		baseroles => {
			t => 'upick_town',
			m => 'upick_mafia',
			sk => 'upick_sk',
		},
		help => "upick (3+ players, and a moderator): A setup where a moderator assigns the roles based on player requests. The player who starts the game becomes the moderator.",
		moderated => 1,
		upick => 1,
	},
	moderated => {
		minplayers => 3,
		weirdness => 0.9,
		help => "moderated (3p+ players, and a moderator): The player who starts the game is the moderator, and can set roles before the game begins or change them during the game.",
		moderated => 1,
	},
	league => {
		hidden => 1,
		minplayers => 7,
		weirdness => 0.33,
		help => "league: A game for the #mafia league. No moderator tampering is allowed.",
		nomods => 1,
		start_time => 600,
	},
	gunfight => {
		weirdness => 1,
		multiroles => 2,
		exp => 1,
		townplayermult => 1.5,
		townpowermult => 0.5,
		neutralfactor => 0.75,
		start => "day",
		nonight => 1,
		no_group_actions => 1,
		nocult => 1,
		nosurvivor => 1,
		expand_power => 1, # Roles are evaluated based on their parts
		theme => "worstidea",
		baseroles => {
			t => "gunfighter100handgun",
			m => "gunfighter100handgun",
			sk => "gunfighter100handgun",
			sv => "gunfighter100handgun",
		},
		help => "gunfight (3+ players): Lynching is for wimps. Take your gun and blast away the scum!",
		#randomok => 1,
		minplayersrandom => 4,
	},
	"gunfight-chosen" => {
		minplayers => 4,
		maxplayers => 12,
		rolechoices => 3,
		maxchoices => 3,
		oddrole => 1,
		multiroles => 2,
		weirdness => 1,
		exp => 1,
		townplayermult => 1.5,
		townpowermult => 0.5,
		neutralfactor => 0.75,
		start => "day",
		nonight => 1,
		no_group_actions => 1,
		nocult => 1,
		nosurvivor => 1,
		expand_power => 1, # Roles are evaluated based on their parts
		theme => "worstidea",
		baseroles => {
			t => "gunfighter100handgun",
			m => "gunfighter100handgun",
			sk => "gunfighter100handgun",
			sv => "gunfighter100handgun",
		},
		help => "gunfight-chosen (4-12 players): Lynching is for wimps. Take your favorite gun and blast away the scum!",
		fakeok => 1,
	},
	"gunfight-insane" => {
		minplayers => 4,
		maxplayers => 12,
		nolimits => 1,
		oddrole => 1,
		multiroles => 2,
		exp => 0.2,

		weirdness => 1,
		townplayermult => 1.5,
		townpowermult => 0.5,
		neutralfactor => 0.75,
		start => "day",
		nonight => 1,
		no_group_actions => 1,
		nocult => 1,
		nosurvivor => 1,
		expand_power => 1, # Roles are evaluated based on their parts
		theme => "worstidea",
		baseroles => {
			t => "gunfighter100handgun",
			m => "gunfighter100handgun",
			sk => "gunfighter100handgun",
			sv => "gunfighter100handgun",
		},
		help => "gunfight-insane (4-12 players): Lynching is for wimps. Take your most powerful gun and blast away the scum!",
		secret => 1,
		fakeok => 1,
	},
	dethy => {
		players => 5,
		roles => [qw"c ci cp cn m/mafia"],
		start => "nightnokill",
		noreveal => 1,
		help => "dethy (5 players): A fixed setup with 1 mafia and 1 cop of each sanity (normal, insane, paranoid, and naive).",
		fakeok => 1,
	}, 
	dethy7 => {
		players => 7,
		roles => [qw"c ci cp cn t m/mafia m/mafia"],
		start => "nightnokill",
		noreveal => 1,
		help => "dethy7 (7 players): A fixed setup with 2 mafia, 1 townie, and 1 cop of each sanity (normal, insane, paranoid, and naive).",
		fakeok => 1,
	},
 	dethy11 => {
		players => 11,
		roles => [qw"c c ci ci cp cp cn cn fr/mafia fr/mafia gf/mafia"],
		start => "nightnokill",
		noreveal => 1,
		help => "dethy11 (11 players): A fixed setup with 1 Mafia Godfather, 2 Frame Artists, and 2 cop of each sanity (normal, insane, paranoid, and naive).",
		fakeok => 1,
	},
	#c9 => {
	#	players => 7,
	#	roles => [qw"t t t c,t d,t m/mafia m/mafia"],
	#},
	f11 => {
		players => 9,
		numalts9 => 4,
		roles9_1 => [qw"t t t t t t t rb/mafia m/mafia"],
		roles9_2 => [qw"t t t t t t c m/mafia m/mafia"],
		roles9_3 => [qw"t t t t t t d m/mafia m/mafia"],
		roles9_4 => [qw"t t t t t c d rb/mafia m/mafia"],
		help => "f11 (9 players): A setup with 2 mafia and 7 town, with either exactly one or all three of cop, doc, or mafia roleblocker.",
		fakeok => 1,
	},
	lyncher => {
		minplayers => 5,
		maxplayers => 20,
		numalts4  => 1, roles4_1  => [qw"tly t t ly/lyncher"],
		numalts5  => 1, roles5_1  => [qw"tly t t ly/lyncher m/mafia"],
		numalts6  => 1, roles6_1  => [qw"tly t t t ly/lyncher m/mafia"],
		numalts7  => 1, roles7_1  => [qw"tly t t t t ly/lyncher m/mafia"],
		numalts8  => 1, roles8_1  => [qw"tly t t t t t ly/lyncher m/mafia"],
		numalts9  => 1, roles9_1  => [qw"tly t t t t t t ly/lyncher m/mafia"],
		numalts10 => 1, roles10_1 => [qw"tly t t t t t t t ly/lyncher m/mafia"],
		numalts11 => 1, roles11_1 => [qw"tly t t t t t t t t ly/lyncher m/mafia"],
		numalts12 => 1, roles12_1 => [qw"tly t t t t t t t t t ly/lyncher m/mafia"],
		numalts13 => 1, roles13_1 => [qw"tly t t t t t t t t t t ly/lyncher m/mafia"],
		numalts14 => 1, roles14_1 => [qw"tly t t t t t t t t t t t ly/lyncher m/mafia"],
		numalts15 => 1, roles15_1 => [qw"tly t t t t t t t t t t t t ly/lyncher m/mafia"],
		numalts16 => 1, roles16_1 => [qw"tly t t t t t t t t t t t t t ly/lyncher m/mafia"],
		numalts17 => 1, roles17_1 => [qw"tly t t t t t t t t t t t t t t ly/lyncher m/mafia"],
		numalts18 => 1, roles18_1 => [qw"tly t t t t t t t t t t t t t t t ly/lyncher m/mafia"],
		numalts19 => 1, roles19_1 => [qw"tly t t t t t t t t t t t t t t t t ly/lyncher m/mafia"],
		numalts20 => 1, roles20_1 => [qw"tly t t t t t t t t t t t t t t t t t ly/lyncher m/mafia"],
		start => "day",
		noreveal => 1,
		help => "lyncher (5- 20 players): A fixed setup with one lyncher, one mafia, and the remaining players townies.",
		randomok => 1,
	},
	kingmaker => {
		minplayers => 5,
		maxplayers => 12,
		theme => "kingmaker",
		weirdness => 0,
		noneutral => 1,
		numalts5  => 1, roles5_1  => [qw"km_kingmaker km_villain/mafia km_peasant km_peasant,km_hero km_peasant"],
		numalts6  => 1, roles6_1  => [qw"km_kingmaker km_villain/mafia km_peasant,km_hero km_peasant km_peasant km_peasant"],
		numalts7  => 1, roles7_1  => [qw"km_kingmaker km_villain/mafia km_villain/mafia km_cop,km_doc km_cop,km_doc,km_hero,km_peasant km_peasant km_peasant"],
		numalts8  => 1, roles8_1  => [qw"km_kingmaker km_villain/mafia km_villain/mafia km_cop,km_doc km_cop,km_doc,km_hero,km_peasant km_peasant km_peasant km_peasant"],
		numalts9  => 1, roles9_1  => [qw"km_kingmaker km_villain/mafia km_villain/mafia km_cop,km_doc,km_vig km_cop,km_doc,km_vig,km_hero,km_peasant km_peasant km_peasant km_peasant km_peasant"],
		numalts10 => 1, roles10_1 => [qw"km_kingmaker km_villain/mafia km_villain/mafia km_cop,km_doc,km_vig km_cop,km_doc,km_vig,km_hero,km_peasant km_peasant km_peasant km_peasant km_peasant km_peasant"],
		numalts11 => 1, roles11_1 => [qw"km_kingmaker km_villain/mafia km_villain/mafia km_cop,km_doc,km_vig km_cop,km_doc,km_vig,km_hero,km_peasant km_peasant km_peasant km_peasant km_peasant km_peasant km_peasant"],
		numalts12 => 1, roles12_1 => [qw"km_kingmaker km_villain/mafia km_villain/mafia km_cop,km_doc,km_vig km_cop,km_doc,km_vig,km_hero,km_peasant km_peasant km_peasant km_peasant km_peasant km_peasant km_peasant km_peasant"],
		baseroles => {
			t => "km_peasant",
			m => "km_villain",
		},
		start => "day",
		help => "kingmaker (5- 12 players): One player is the Kingmaker, one or more are Villains, and the remainder are Peasants, Heroes, Cops, Doctors, or Vigilantes. The Kingmaker selects a King each day, and the King decides who to lynch.",
	},
	kingmaker2 => {
		minplayers => 5,
		theme => "kingmaker",
		weirdness => 0,
		noneutral => 1,
		townplayermult => 0.9,
		baseroles => {
			t => "km_peasant",
			m => "km_villain",
		},
		start => "day",
		help => "kingmaker (5-12 players): One player is the Kingmaker, one or more are Villains, and the remainder are Peasants, Heroes, Cops, Doctors, or Vigilantes. The Kingmaker selects a King each day, and the King decides who to lynch. There is a more significant number of powerroles than normal kingmaker.",
	},
	dreamers => {
		minplayers => 4,
		theme => "dreamers",
		weirdness => 0,
		noneutral => 1,
		baseroles => {
			t => "dreamer1",
			m => "nightmare1",
		},
		start => "day",
		noreveal => 1,
		freegroupaction => 1,
		help => "dreamers (4+ players): Everyone has a random assortmort of night abilities. Nightmares may use the mafiakill in addition to their normal night action.",
		#randomok => 1,
		minplayersrandom => 4,
	},
	assassin => {
		minplayers => 5,
		maxplayers => 12,
		numalts5 => 1, roles5_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_assassin/assassin"],
		numalts6 => 1, roles6_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_guard ass_assassin/assassin"],
		numalts7 => 1, roles7_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_guard ass_guard ass_assassin/assassin"],
		numalts8 => 1, roles8_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_guard ass_guard ass_assassin/assassin ass_assassin/assassin"],
		numalts9 => 1, roles9_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_assassin/assassin ass_assassin/assassin"],
		numalts10 => 1, roles10_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_assassin/assassin ass_assassin/assassin"],
		numalts11 => 1, roles11_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_assassin/assassin ass_assassin/assassin"],
		numalts12 => 1, roles12_1 => [qw"ass_king ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_guard ass_assassin/assassin ass_assassin/assassin"],
		start => "day",
		help => "assassin (5-12 players): One player is the King, one or more are Assassins, and the remainder are Guards. The Guards know who the King is, but the Assassins don't. The Assassins win if the King dies. There are no night kills, but if an Assassin is lynched they can kill one player before dying.",
	},
	momir => {
		minplayers => 3,
		maxplayers => 15,
		numalts3  => 1, roles3_1  => [qw"mut mut mut/sk"],
		numalts4  => 1, roles4_1  => [qw"mut mut mut mut/sk"],
		numalts5  => 1, roles5_1  => [qw"mut mut mut mut/sk1 mut/sk2"],
		numalts6  => 1, roles6_1  => [qw"mut mut mut mut mut/sk1 mut/sk2"],
		numalts7  => 1, roles7_1  => [qw"mut mut mut mut mut/sk1 mut/sk2 mut/sk3"],
		numalts8  => 1, roles8_1  => [qw"mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3"],
		numalts9  => 1, roles9_1  => [qw"mut mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3"],
		numalts10 => 1, roles10_1 => [qw"mut mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3 mut/sk4"],
		numalts11 => 1, roles11_1 => [qw"mut mut mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3 mut/sk4"],
		numalts12 => 1, roles12_1 => [qw"mut mut mut mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3 mut/sk4"],
		numalts13 => 1, roles13_1 => [qw"mut mut mut mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5"],
		numalts14 => 1, roles14_1 => [qw"mut mut mut mut mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5"],
		numalts15 => 1, roles15_1 => [qw"mut mut mut mut mut mut mut mut mut mut mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5"],
		start => "night",
		nokillphases => 12,
		help => "momir (3-15 players): A fixed setup where all players are Mutants, either town or serial killer.",
		fakeok => 1,
	},
	evomomir => {
		hidden => 1,
		minplayers => 3,
		maxplayers => 15,
		numalts3  => 1, roles3_1  => [qw"evo evo evo/sk"],
		numalts4  => 1, roles4_1  => [qw"evo evo evo evo/sk"],
		numalts5  => 1, roles5_1  => [qw"evo evo evo evo/sk1 evo/sk2"],
		numalts6  => 1, roles6_1  => [qw"evo evo evo evo evo/sk1 evo/sk2"],
		numalts7  => 1, roles7_1  => [qw"evo evo evo evo evo/sk1 evo/sk2 evo/sk3"],
		numalts8  => 1, roles8_1  => [qw"evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3"],
		numalts9  => 1, roles9_1  => [qw"evo evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3"],
		numalts10 => 1, roles10_1 => [qw"evo evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3 evo/sk4"],
		numalts11 => 1, roles11_1 => [qw"evo evo evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3 evo/sk4"],
		numalts12 => 1, roles12_1 => [qw"evo evo evo evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3 evo/sk4"],
		numalts13 => 1, roles13_1 => [qw"evo evo evo evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3 evo/sk4 evo/sk5"],
		numalts14 => 1, roles14_1 => [qw"evo evo evo evo evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3 evo/sk4 evo/sk5"],
		numalts15 => 1, roles15_1 => [qw"evo evo evo evo evo evo evo evo evo evo evo/sk1 evo/sk2 evo/sk3 evo/sk4 evo/sk5"],
		start => "day",
		nokillphases => 12,
		help => "evomomir (3-15 players): A fixed setup where all players are Evolvers, either town or serial killer.",
		fakeok => 1,
	},
	mountainous => {
		maxplayers => 20,
		numalts3  => 1, start3_1  => "day",   roles3_1  => [qw"t t m/mafia"],
		numalts4  => 1, start4_1  => "day",   roles4_1  => [qw"t t t m/mafia"],
		numalts5  => 1, start5_1  => "day",   roles5_1  => [qw"t t t t m/mafia"],
		numalts6  => 1, start6_1  => "day",   roles6_1  => [qw"t t t t t m/mafia"],
		numalts7  => 1, start7_1  => "day",   roles7_1  => [qw"t t t t t t m/mafia"],
		numalts8  => 1, start8_1  => "day",   roles8_1  => [qw"t t t t t t t m/mafia"],
		numalts9  => 1, start9_1  => "day",   roles9_1  => [qw"t t t t t t t t m/mafia"],
		numalts10 => 1, start10_1 => "day",   roles10_1 => [qw"t t t t t t t t t m/mafia"],
		numalts11 => 1, start11_1 => "day",   roles11_1 => [qw"t t t t t t t t t t m/mafia"],
		numalts12 => 1, start12_1 => "day",   roles12_1 => [qw"t t t t t t t t t t t m/mafia"],
		numalts13 => 1, start13_1 => "day",   roles13_1 => [qw"t t t t t t t t t t t t m/mafia"],
		numalts14 => 1, start14_1 => "day",   roles14_1 => [qw"t t t t t t t t t t t t m/mafia m/mafia"],
		numalts15 => 1, start15_1 => "day",   roles15_1 => [qw"t t t t t t t t t t t t t m/mafia m/mafia"],
		numalts16 => 1, start16_1 => "day",   roles16_1 => [qw"t t t t t t t t t t t t t t m/mafia m/mafia"],
		numalts17 => 1, start17_1 => "day",   roles17_1 => [qw"t t t t t t t t t t t t t t t m/mafia m/mafia"],
		numalts18 => 1, start18_1 => "day",   roles18_1 => [qw"t t t t t t t t t t t t t t t t m/mafia m/mafia"],
		numalts19 => 1, start19_1 => "day",   roles19_1 => [qw"t t t t t t t t t t t t t t t t t m/mafia m/mafia"],
		numalts20 => 1, start20_1 => "day",   roles20_1 => [qw"t t t t t t t t t t t t t t t t t m/mafia m/mafia m/mafia"],
		start => "day",
		help => "mountainous (3-15 players): A fixed setup where only Townies and Mafiosos appear.",
	#		randomok => 1,
		realok => 1,
	},
	wtf => {
		hidden => 1,
		minplayers => 5,
		maxplayers => 9,
		# Players  WTF  Mafia  Townies Cops    Docs    Vigs
		# 5        1    1      1-2     0-1     0-1     0
		# 6        1    1      2-3     0-1     0-1     0
		# 7        1    1      3-4     0-1     0-1     0-1
		# 8        1    2      2-3     0-2     0-2     0-1
		# 9        1    2      3-5     0-2     0-2     0-1
		numalts5  => 3,  roles5_1  => [qw"twtf twtf cwtf wtf/survivor m/mafia"],
		                 roles5_2  => [qw"twtf twtf dwtf wtf/survivor m/mafia"],
		                 roles5_3  => [qw"twtf cwtf dwtf wtf/survivor m/mafia"],
		numalts6  => 3,  roles6_1  => [qw"twtf twtf twtf cwtf wtf/survivor m/mafia"],
		                 roles6_2  => [qw"twtf twtf twtf dwtf wtf/survivor m/mafia"],
		                 roles6_3  => [qw"twtf twtf cwtf dwtf wtf/survivor m/mafia"],
		numalts7  => 6,  roles7_1  => [qw"twtf twtf twtf twtf cwtf wtf/survivor m/mafia"],
		                 roles7_2  => [qw"twtf twtf twtf twtf dwtf wtf/survivor m/mafia"],
		                 roles7_3  => [qw"twtf twtf twtf twtf vwtf wtf/survivor m/mafia"],
		                 roles7_4  => [qw"twtf twtf twtf cwtf dwtf wtf/survivor m/mafia"],
		                 roles7_5  => [qw"twtf twtf twtf vwtf cwtf wtf/survivor m/mafia"],
		                 roles7_6  => [qw"twtf twtf twtf vwtf dwtf wtf/survivor m/mafia"],
		numalts8  => 10, roles8_1  => [qw"twtf twtf twtf cwtf cwtf wtf/survivor m/mafia m/mafia"],
		                 roles8_2  => [qw"twtf twtf twtf cwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles8_3  => [qw"twtf twtf twtf dwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles8_4  => [qw"twtf twtf twtf vwtf cwtf wtf/survivor m/mafia m/mafia"],
		                 roles8_5  => [qw"twtf twtf twtf vwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles8_6  => [qw"twtf twtf vwtf cwtf cwtf wtf/survivor m/mafia m/mafia"],
		                 roles8_7  => [qw"twtf twtf vwtf cwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles8_8  => [qw"twtf twtf vwtf dwtf dwtf wtf/survivor m/mafia m/mafia"],				
		                 roles8_9  => [qw"twtf twtf cwtf cwtf dwtf wtf/survivor m/mafia m/mafia"],				
		                 roles8_10 => [qw"twtf twtf cwtf dwtf dwtf wtf/survivor m/mafia m/mafia"],				
		numalts9  => 13, roles9_1  => [qw"twtf twtf twtf twtf twtf cwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_2  => [qw"twtf twtf twtf twtf twtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_3  => [qw"twtf twtf twtf twtf twtf vwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_4  => [qw"twtf twtf twtf twtf cwtf cwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_5  => [qw"twtf twtf twtf twtf cwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_6  => [qw"twtf twtf twtf twtf dwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_7  => [qw"twtf twtf twtf twtf vwtf cwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_8  => [qw"twtf twtf twtf twtf vwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_9  => [qw"twtf twtf twtf vwtf cwtf cwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_10 => [qw"twtf twtf twtf vwtf cwtf dwtf wtf/survivor m/mafia m/mafia"],
		                 roles9_11 => [qw"twtf twtf twtf vwtf dwtf dwtf wtf/survivor m/mafia m/mafia"],				
		                 roles9_12 => [qw"twtf twtf twtf cwtf cwtf dwtf wtf/survivor m/mafia m/mafia"],				
		                 roles9_13 => [qw"twtf twtf twtf cwtf dwtf dwtf wtf/survivor m/mafia m/mafia"],				
		start => "night",
		help => "wtf (5-9 players): An extremely confusing setup where nobody knows their real role.",
	},
	vengeful => {
		players => 5,
		roles => [qw"ven_t ven_t ven_t ven_gf/mafia ven_m/mafia"],
		no_group_actions => 1,
		start => "day",
		help => "vengeful (5 players): There is one Mafioso, one Godfather, and three Townies. If the Godfather is lynched day 1, the town wins. If a Townie is lynched, that Townie may kill another player before dying.",
	},


	cocopotato => {
		minplayers => 5,
		maxplayers => 8,
		numalts5 => 1, roles5_1 => [qw"coldpotato/sk1 coldpotato/sk2 	coldpotato/sk3 coldpotato/sk4 hotpotato/sk5"],
		numalts6 => 1, roles6_1 => [qw"coldpotato/sk1 coldpotato/sk2 coldpotato/sk3 coldpotato/sk4 coldpotato/sk5 hotpotato/sk6"],
		numalts7 => 1, roles7_1 => [qw"coldpotato/sk1 coldpotato/sk2 coldpotato/sk3 coldpotato/sk4 coldpotato/sk5 hotpotato/sk6 hotpotato/sk7"],
		start => "day",
		numalts8 => 1, roles8_1 => [qw"coldpotato/sk1 coldpotato/sk2 coldpotato/sk3 coldpotato/sk4 coldpotato/sk5 coldpotato/sk6 coldpotato/sk7 hotpotato/sk8"],
		help => "Hot Potato for 5+ players: Everyone is unlynchable except for the Hot Potato. If you are it, you had better get rid of it quickly, because if you are lynched while you are hot, you lose.",
	},



	raf => {
		minplayers => 2,
		maxplayers => 15,
		numalts2 => 1, roles2_1 => [qw"raf/sk1 raf/sk2"],
		numalts3 => 1, roles3_1 => [qw"raf/sk1 raf/sk2 raf/sk3"],
		numalts4 => 1, roles4_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4"],
		numalts5 => 1, roles5_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5"],
		numalts6 => 1, roles6_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5 raf/sk6"],
		numalts7 => 1, roles7_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5 raf/sk6 raf/sk7"],
		numalts8 => 1, roles8_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5 raf/sk6 raf/sk7 raf/sk8"],
		numalts9 => 1, roles9_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5 raf/sk6 raf/sk7 raf/sk8 raf/sk9"],
		numalts10 => 1, roles10_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5 raf/sk6 raf/sk7 raf/sk8 raf/sk9 raf/sk10"],
		numalts11 => 1, roles11_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5 raf/sk6 raf/sk7 raf/sk8 raf/sk9 raf/sk10 raf/sk11"],
		numalts12 => 1, roles12_1 => [qw"raf/sk1 raf/sk2 raf/sk3 raf/sk4 raf/sk5 raf/sk6 raf/sk7 raf/sk8 raf/sk9 raf/sk10 raf/sk11 raf/sk12"],
		numalts13 => 1, roles13_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11 rps/sk12 rps/sk13"],
		numalts14 => 1, roles14_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11 rps/sk12 rps/sk13 rps/sk14"],
		numalts15 => 1, roles15_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11 rps/sk12 rps/sk13 rps/sk14 rps/sk15"],
		start => "night",
		noday => 1,
		nokillphases => 30,
		help => "rps (2-15 players): In this variant of rock-paper-scissors, each player chooses to 'shoot self', 'shoot sky', or shoot another player. If you shoot yourself, you die unless another player shoots you, in which case that player dies. If everybody dies in one night, all players return to life to try again.",
	},
	rps => {
		minplayers => 2,
		maxplayers => 15,
		numalts2 => 1, roles2_1 => [qw"rps/sk1 rps/sk2"],
		numalts3 => 1, roles3_1 => [qw"rps/sk1 rps/sk2 rps/sk3"],
		numalts4 => 1, roles4_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4"],
		numalts5 => 1, roles5_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5"],
		numalts6 => 1, roles6_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6"],
		numalts7 => 1, roles7_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7"],
		numalts8 => 1, roles8_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8"],
		numalts9 => 1, roles9_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9"],
		numalts10 => 1, roles10_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10"],
		numalts11 => 1, roles11_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11"],
		numalts12 => 1, roles12_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11 rps/sk12"],
		numalts13 => 1, roles13_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11 rps/sk12 rps/sk13"],
		numalts14 => 1, roles14_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11 rps/sk12 rps/sk13 rps/sk14"],
		numalts15 => 1, roles15_1 => [qw"rps/sk1 rps/sk2 rps/sk3 rps/sk4 rps/sk5 rps/sk6 rps/sk7 rps/sk8 rps/sk9 rps/sk10 rps/sk11 rps/sk12 rps/sk13 rps/sk14 rps/sk15"],
		start => "night",
		noday => 1,
		nokillphases => 30,
		help => "rps (2-15 players): Rock-paper-scissors. You already know how to play.",
	},
	"momir-duel" => {
		help => "momir-duel (3-15 players): An all-sk setup where each person starts off as a mutant. Dayless setup - use your actions with skill to survive until the end.",
		minplayers => 3,
		maxplayers => 15,
		numalts2 => 1, roles2_1 => [qw"mut/sk1 mut/sk2"],
		numalts3 => 1, roles3_1 => [qw"mut/sk1 mut/sk2 mut/sk3"],
		numalts4 => 1, roles4_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4"],
		numalts5 => 1, roles5_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5"],
		numalts6 => 1, roles6_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6"],
		numalts7 => 1, roles7_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7"],
		numalts8 => 1, roles8_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8"],
		numalts9 => 1, roles9_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8 mut/sk9"],
		numalts10 => 1, roles10_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8 mut/sk9 mut/sk10"],
		numalts11 => 1, roles11_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8 mut/sk9 mut/sk10 mut/sk11"],
		numalts12 => 1, roles12_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8 mut/sk9 mut/sk10 mut/sk11 mut/sk12"],
		numalts13 => 1, roles13_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8 mut/sk9 mut/sk10 mut/sk11 mut/sk12 mut/sk13"],
		numalts14 => 1, roles14_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8 mut/sk9 mut/sk10 mut/sk11 mut/sk12 mut/sk13 mut/sk14"],
		numalts15 => 1, roles15_1 => [qw"mut/sk1 mut/sk2 mut/sk3 mut/sk4 mut/sk5 mut/sk6 mut/sk7 mut/sk8 mut/sk9 mut/sk10 mut/sk11 mut/sk12 mut/sk13 mut/sk14 mut/sk15"],
		start => "night",
		noday => 1,
	#	nokillphases => 12,
		fakeok => 1,
	},
"evo-duel" => { 
		help => "evo-duel (3-9 players): An all-sk setup where each person gains an ability every night. Dayless setup - use your actions with skill to survive until the end.",
		minplayers => 3,
		maxplayers => 9,
		numalts2 => 1, roles2_1 => [qw"evod/sk1 evod/sk2"],
		numalts3 => 1, roles3_1 => [qw"evod/sk1 evod/sk2 evod/sk3"],
		numalts4 => 1, roles4_1 => [qw"evod/sk1 evod/sk2 evod/sk3 evod/sk4"],
		numalts5 => 1, roles5_1 => [qw"evod/sk1 evod/sk2 evod/sk3 evod/sk4 evod/sk5"],
		numalts6 => 1, roles6_1 => [qw"evod/sk1 evod/sk2 evod/sk3 evod/sk4 evod/sk5 evod/sk6"],
		numalts7 => 1, roles7_1 => [qw"evod/sk1 evod/sk2 evod/sk3 evod/sk4 evod/sk5 evod/sk6 evod/sk7"],
		numalts8 => 1, roles8_1 => [qw"evod/sk1 evod/sk2 evod/sk3 evod/sk4 evod/sk5 evod/sk6 evod/sk7 evod/sk8"],
		numalts9 => 1, roles9_1 => [qw"evod/sk1 evod/sk2 evod/sk3 evod/sk4 evod/sk5 evod/sk6 evod/sk7 evod/sk8 evod/sk9"],
		start => "night",
		noday => 1,
		nokillphases => 12,
	#	hidden => 1,
	},
	"chainsaw" => {
		minplayers => 3,
		maxplayers => 15,
		numalts2 => 1, roles2_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2"],
		numalts3 => 1, roles3_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3"],
		numalts4 => 1, roles4_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4"],
		numalts5 => 1, roles5_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5"],
		numalts6 => 1, roles6_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6"],
		numalts7 => 1, roles7_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7"],
		numalts8 => 1, roles8_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8"],
		numalts9 => 1, roles9_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8 sk/sk9,red/sk9,sk/sk9"],
		numalts10 => 1, roles10_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8 sk/sk9,red/sk9,sk/sk9 sk/sk10,red/sk10,sk/sk10"],
		numalts11 => 1, roles11_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8 sk/sk9,red/sk9,sk/sk9 sk/sk10,red/sk10,sk/sk10 sk/sk11,red/sk11,sk/sk11"],
		numalts12 => 1, roles12_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8 sk/sk9,red/sk9,sk/sk9 sk/sk10,red/sk10,sk/sk10 sk/sk11,red/sk11,sk/sk11 sk/sk12,red/sk12,sk/sk12"],
		numalts13 => 1, roles13_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8 sk/sk9,red/sk9,sk/sk9 sk/sk10,red/sk10,sk/sk10 sk/sk11,red/sk11,sk/sk11 sk/sk12,red/sk12,sk/sk12 sk/sk13,red/sk13,sk/sk13"],
		numalts14 => 1, roles14_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8 sk/sk9,red/sk9,sk/sk9 sk/sk10,red/sk10,sk/sk10 sk/sk11,red/sk11,sk/sk11 sk/sk12,red/sk12,sk/sk12 sk/sk13,red/sk13,sk/sk13 sk/sk14,red/sk14,sk/sk14"],
		numalts15 => 1, roles15_1 => [qw"sk/sk1,red/sk1,sk/sk1 sk/sk2,red/sk2,sk/sk2 sk/sk3,red/sk3,sk/sk3 sk/sk4,red/sk4,sk/sk4 sk/sk5,red/sk5,sk/sk5 sk/sk6,red/sk6,sk/sk6 sk/sk7,red/sk7,sk/sk7 sk/sk8,red/sk8,sk/sk8 sk/sk9,red/sk9,sk/sk9 sk/sk10,red/sk10,sk/sk10 sk/sk11,red/sk11,sk/sk11 sk/sk12,red/sk12,sk/sk12 sk/sk13,red/sk13,sk/sk13 sk/sk14,red/sk14,sk/sk14 sk/sk15,red/sk15,sk/sk15"],
		start => "night",
		noday => 1,
		hidden => 1,
	#	nokillphases => 30,
		help => "chainsaw (3-15 players): Everyone's a serial killer. Kill them before they kill you!",
		fakeok => 1,
	},
	simenon => {
		hidden => 1,
		players => 7,
		numalts7 => 1, roles7_1 => [qw"t t t t c d mrec/mafia"],
		start => "nightnokill",
	},
	piec9 => {
		# Also known as Pie E7
		players => 7,
		numalts7 => 1, roles7_1 => [qw"t t t c d m/mafia rb/mafia"],
		start => "day",
	},
	basic12 => {
		# This setup stolen from synIRC/#mafia
		players => 12,
		numalts12 => 1, roles12_1 => [qw"t t t t t t t d c m/mafia m/mafia m/mafia"],
		start => "night",
	},
	ss3 => {
		players => 3,
		numalts3 => 1, roles3_1 => [qw"t ss m/mafia"],
		start => "day",
		randomok => 1,
	},
	smalltown => {
		minplayers => 6,
		maxplayers => 20,
		numalts6 => 1, roles6_1 => [qw"t t t t m/mafia m/mafia"],
		numalts7 => 1, roles7_1 => [qw"t t t t t m/mafia m/mafia"],
		numalts8 => 1, roles8_1 => [qw"t t t t t t gf/mafia m/mafia"],
		numalts9 => 1, roles9_1 => [qw"t t t t t t sk/sk gf/mafia m/mafia"],
		numalts10 => 1, roles10_1 => [qw"t t t t t t t sk/sk gf/mafia m/mafia"],
		numalts11 => 1, roles11_1 => [qw"t t t t t t t t sk/sk gf/mafia m/mafia"],
		numalts12 => 1, roles12_1 => [qw"t t t t t t t t sk/sk gf/mafia m/mafia m/mafia"],
		numalts13 => 1, roles13_1 => [qw"t t t t t t t t t sk/sk gf/mafia m/mafia m/mafia"],
		numalts14 => 1, roles14_1 => [qw"t t t t t t t t t t sk/sk gf/mafia m/mafia m/mafia"],
		numalts15 => 1, roles15_1 => [qw"t t t t t t t t t t t sk/sk gf/mafia m/mafia m/mafia"],
		numalts16 => 1, roles16_1 => [qw"t t t t t t t t t t t sk/sk gf/mafia m/mafia m/mafia m/mafia"],
		numalts17 => 1, roles17_1 => [qw"t t t t t t t t t t t t sk/sk gf/mafia m/mafia m/mafia m/mafia"],
		numalts18 => 1, roles18_1 => [qw"t t t t t t t t t t t t gf/mafia m/mafia m/mafia gf/mafia2 m/mafia2 m/mafia2"],
		numalts19 => 1, roles19_1 => [qw"t t t t t t t t t t t t t gf/mafia m/mafia m/mafia gf/mafia2 m/mafia2 m/mafia2"],
		numalts20 => 1, roles20_1 => [qw"t t t t t t t t t t t t t t gf/mafia m/mafia m/mafia gf/mafia2 m/mafia2 m/mafia2"],
		publicroles => [qw"c d trk rb asc suiday t red alien vot2 mayor copy bg2 nw mot v dhalf ss rand xk mup bus dp tik magn giver backup"],
		start => "day",
		smalltown => 1,
		randomok => 1,
		realok => 1,
	},
	"smalltown+" => {
		weirdness => 0.3,
		nobastard => 1,
		townpowermult => 0.3,
		minplayers => 6,
		maxplayers => 20,
		start => "day",
		publicroles => [qw"c d trk rb asc suiday t red alien vot2 mayor copy bg2 nw mot v dhalf ss rand xk mup bus dp tik magn giver backup"],
		smalltown => 1,
		realok => 1,
	},
	"smalltown+-base" => {
		weirdness => 0.3,
		nobastard => 1,
		townpowermult => 0.3,
		minplayers => 6,
		maxplayers => 20,
		hidden => 1,
		enable_on_days => "x", # Never
	},
	challenge => {
		weirdness => 0.75,
		teamweirdness => 0.25,
		exp => 1,
		allowwolf => 1,
		townpowermult => 0.4,
		minplayers => 3,
		help => "challenge (3+ players): The town has less power than normal.",
		randomok => 1,
		realok => 1,
	},
	bonanza => {
		weirdness => 0.75,
		exp => 0.3,
		allowwolf => 1,
		townpowermult => 3,
		minplayers => 3,
		help => "bonanza (3+ players): The town has more power than normal.",
		randomok => 1,
		realok => 1,
	},
	outfox => {
		# randomweirdness => 1,
		weirdness => 0.75,
		teamweirdness => 0.25,
		exp => 0.6,
		minplayers => 4,
		theme => "foxworld",
		help => "outfox (4+ players): A setup with a restricted role set.",
		randomok => 1,
		minplayersrandom => 4,
		realok => 1,
	},
	xany => {
		# randomweirdness => 1,
		weirdness => 1.00,
		teamweirdness => 0.75,
		oddrole => 1,
		minplayers => 4,
		theme => "xylworld",
		help => "xany (4+ players): A setup with a restricted role set.",
		secret => 1,
	},
	"cosmic-smalltown" => {
		minplayers => 6,
		maxplayers => 20,
		numalts6 => 1, roles6_1 => [qw"t t t t m/mafia m/mafia"],
		numalts7 => 1, roles7_1 => [qw"t t t t t m/mafia m/mafia"],
		numalts8 => 1, roles8_1 => [qw"t t t t t t m/mafia m/mafia"],
		numalts9 => 1, roles9_1 => [qw"t t t t t t sk/sk m/mafia m/mafia"],
		numalts10 => 1, roles10_1 => [qw"t t t t t t t sk/sk m/mafia m/mafia"],
		numalts11 => 1, roles11_1 => [qw"t t t t t t t t sk/sk m/mafia m/mafia"],
		numalts12 => 1, roles12_1 => [qw"t t t t t t t t sk/sk m/mafia m/mafia m/mafia"],
		numalts13 => 1, roles13_1 => [qw"t t t t t t t t t sk/sk m/mafia m/mafia m/mafia"],
		numalts14 => 1, roles14_1 => [qw"t t t t t t t t t t sk/sk m/mafia m/mafia m/mafia"],
		numalts15 => 1, roles15_1 => [qw"t t t t t t t t t t t sk/sk m/mafia m/mafia m/mafia"],
		numalts16 => 1, roles16_1 => [qw"t t t t t t t t t t t sk/sk m/mafia m/mafia m/mafia m/mafia"],
		numalts17 => 1, roles17_1 => [qw"t t t t t t t t t t t t sk/sk m/mafia m/mafia m/mafia m/mafia"],
		numalts18 => 1, roles18_1 => [qw"t t t t t t t t t t t t m/mafia m/mafia m/mafia m/mafia2 m/mafia2 m/mafia2"],
		numalts19 => 1, roles19_1 => [qw"t t t t t t t t t t t t t m/mafia m/mafia m/mafia m/mafia2 m/mafia2 m/mafia2"],
		numalts20 => 1, roles20_1 => [qw"t t t t t t t t t t t t t t m/mafia m/mafia m/mafia m/mafia2 m/mafia2 m/mafia2"],
		publicroles => [map { "theme_cosmic_$_" } qw"antimatter assassin cavalry changeling chosen chronos deuce empath 
			filch filth fungus gambler healer insect laser macron magnet mind2 mirror mutant oracle pentaform
			phantom philantropist reincarnator seeker subversive sniveler terrorist vacuum void vulch wrack zombie"],
		start => "day",
		theme => "cosmic",
		smalltown => 1,
	},
	ff6 => {
		minplayers => 6,
		maxplayers => 17,
		numalts6 => 1, roles6_1 => [qw"t,t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia"],
		numalts7 => 1, roles7_1 => [qw"t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia"],
		numalts8 => 1, roles8_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t t t t m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia"],
		numalts9 => 1, roles9_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t t t t sk/sk m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia"],
		numalts10 => 1, roles10_1 => [qw"t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t sk/sk m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia"],
		numalts11 => 1, roles11_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t t sk/sk m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia"],
		numalts12 => 1, roles12_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t t sk/sk m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia"],
		numalts13 => 1, roles13_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t t t t t t sk/sk m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia"],
		numalts14 => 1, roles14_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t t t sk/sk m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia"],
		numalts15 => 1, roles15_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t t t t sk/sk m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia"],
		numalts16 => 1, roles16_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t t t t sk/sk m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia"],
		numalts17 => 1, roles17_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t t t t t t t t sk/sk m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia,m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia"],
		numalts18 => 1, roles18_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t t t t t t t t m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia m/mafia2,m+theme_ff6_item_magicite/mafia2 m/mafia2 m/mafia2"],
		numalts19 => 1, roles19_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t t t t t m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia m/mafia2,m+theme_ff6_item_magicite/mafia2 m/mafia2 m/mafia2"],
		numalts20 => 1, roles20_1 => [qw"t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t+theme_ff6_item_magicite t,t,t+theme_ff6_item_magicite t t t t t t t t t m/mafia,m+theme_ff6_item_magicite/mafia m/mafia m/mafia m/mafia2,m+theme_ff6_item_magicite/mafia2 m/mafia2 m/mafia2"],
		publicroles => [map { "theme_ff6_$_" } qw"terra locke cyan shadow edgar sabin celes strago relm setzer mog gau gogo umaro banon ultros kefka"],
		start => "day",
		theme => "ff6",
		smalltown => 1,
	},
	test => {
		hidden => 1,
		nokillphases => 100,
		start => "day",
	},
	random => {
		randomsetup => 1,
		help => "random: Starts a random setup, which is announced when the game begins.",
	},
	# realmafia => {
	# 	realsetup => 1,
	#	help => "realmafia: Starts a random setup of only traditional scum-hunting games, which is announced when the game begins.",
	# }
	fadebot => {
		minplayers => 3,
		maxplayers => 12,
		hidden => 1,
	},
	deepsouth => {
		randomweirdness => 1,
		nonight => 1,
		deepsouth => 1,
		start => "day",
		help => "deepsouth: There is no night. Actions are sent during the day, and take effect at twilight.",
	},
	eyewitness => {
		help => "eyewitness: Sane witness sees the Mafia, Delusional Witness sees the Sane Witness. Use your skills of logic to win this game!",
		fadebot => 1,
	},
	faction => {
		help => "faction: Four teams battle to meet their custom win conditions.",
		fadebot => 1,
	},
	#feydwins => {
	#	#hidden => 1,
	#	minplayers => 6,
	#	maxplayers => 7,
	#	numalts6  => 5,  roles6_1  => [qw"vamp/sk1 zom/sk2 rbnm,cnm,dnm bg3 v t"],
	#	                 roles6_2  => [qw"vamp/sk1 zom/sk2 cha cmed monk t"],
	#			 roles6_3  => [qw"vamp/sk1 dp/sk2 c pgo crole v"],
	#			 roles6_4  => [qw"rand/mafia vamp/sk cnm,dnm,vnm censsk rb stalk"],
	#			 roles6_5  => [qw"vamp/sk1 psycho/sk2 c v1 red cbackup"],
	#	numalts7  => 1,  roles7_1  => [qw"rand/mafia vamp/sk dq,d censsk nw suiday t"],
	#	                 roles7_2  => [qw"m/mafia vamp/sk cdayi,cday d,dq rb ss v"],
	#			 roles7_3  => [qw"mdoppel/mafia vamp/sk c,cn d dbackup rb t"],
	#			 roles7_4  => [qw"gf/mafia vamp/sk cdayi,cdayn d monk dbackup red"],
	#			 roles7_5  => [qw"vamp/sk1 pos/sk2 cha vik copy cdayi,cdayp fn"],
	#	start => "night",
	#},
	"#mafia" => {
		minplayers => 4,
		weirdness => 1,
		teamweirdness => 0.5,
		exp => 1,
		generatemafiaplayers => 1,
		theme => "mafiaplayers",
		noreveal => 1,
		baseroles => {
			t => 'theme_mafia_t',
			m => 'theme_mafia_m',
			sk => 'theme_mafia_sk',
			cult1 => 'theme_mafia_cult1',
			sv => 'theme_mafia_sv',
		},
		hidden => 1,
	},
	allies => {
		help => "Allies. This setup always has one mafioso, a varying number of mafia-allies, and townies. This is a fixed setup.",
		minplayers => 6,
		maxplayers => 10,
		numalts6 => 1, roles6_1 => [qw"out_maf/mafia out_ally/mafia-ally t/town t/town t/town t/town"],
		numalts7 => 1, roles7_1 => [qw"out_maf/mafia out_ally/mafia-ally t/town t/town t/town t/town t/town"],
		numalts8 => 1, roles8_1 => [qw"out_maf/mafia out_ally/mafia-ally out_ally/mafia-ally t/town t/town t/town t/town t/town"],
		numalts9 => 1, roles9_1 => [qw"out_maf/mafia out_ally/mafia-ally out_ally/mafia-ally t/town t/town t/town t/town t/town t/town"],
		numalts10 => 1, roles10_1 => [qw"out_maf/mafia out_ally/mafia-ally out_ally/mafia-ally t/town t/town t/town t/town t/town t/town t/town"],
	},
);

sub select_fixed_setup {
	my ($numplayers, $setup) = @_;

	$setup = $setup->{setup} if ref($setup) eq 'HASH';

	my $alts = $setup_config{$setup}{"numalts$numplayers"};
	
	my $alt = $alts ? int(rand($alts) + 1) : 0;
	my $fixroles = $alts ? $setup_config{$setup}{"roles${numplayers}_${alt}"} : $setup_config{$setup}{roles};
	my $start = $setup_config{$setup}{"start${numplayers}_${alt}"} || setup_rule('start', $setup) || ($numplayers > 3 ? "night" : "day");

	return ($fixroles, $start);
}

sub setup_baserole {
	my ($setup, $role) = @_;

	$setup = $setup->{setup} if ref($setup) eq 'HASH';

	return $setup_config{$setup}{baseroles}{$role} || $role;
}

sub select_setup {
	my ($numplayers, $setup, $test) = @_;;
	my @roles;

	my $verbose = 1;
	$verbose = 0 if $test;

	::bot_log "SETUP START $setup for $numplayers players\n" if $verbose;
	
	my ($fixroles, $start) = select_fixed_setup($numplayers, $setup);

	if ($fixroles)
	{
		@roles = expand_fixed_setup_roles(@$fixroles);
	}
	else
	{
		$start = setup_rule('start', $setup) || ($numplayers > 3 ? 'night' : 'day');
		my $retries = 0;
		do {
			@roles = random_setup($numplayers, $setup, $test, $retries++);
		} while !@roles;
	}
	
	if (setup_rule('smalltown', $setup))
	{
		my @smalltown_roles = @{ setup_rule("publicroles" . $numplayers, $setup) || setup_rule("publicroles", $setup) };
		shuffle_list(\@smalltown_roles);

		foreach my $setuprole (@roles)
		{
			my $publicrole = pop @smalltown_roles;
			$setuprole->{role} = canonicalize_role($publicrole . "+" . $setuprole->{role}, 1, $setuprole->{team});
			$setuprole->{publicrole} = $publicrole;
		}
	}
	
	return ($start, @roles);
}

sub expand_fixed_setup_roles {
	my (@fixroles) = @_;
	my @roles;
	
	foreach my $setuprole (@fixroles)
	{
		my @alts = split /,/, $setuprole;
		my $alt = $alts[rand @alts];
		my ($role, $team) = split m'/', $alt;
		$team = 'town' unless $team;
		push @roles, { role => $role, team => $team };
	}
	
	return @roles;
}

sub random_setup {
	my ($numplayers, $setup, $test, $retries) = @_;
	my @roles;
	
	my $verbose = 1;
	$verbose = 0 if $test;
	
	my $weirdness = setup_rule('weirdness', $setup); 
	$weirdness = rand(1.0) if setup_rule('randomweirdness', $setup);
	my $teamweirdness = setup_rule('teamweirdness', $setup) || $weirdness;
	my $nolimits = setup_rule('nolimits', $setup);
	#::bot_log "SETUP nolimits is on\n" if $nolimits;

	if (setup_rule('generatemafiaplayers', $setup)) {
		convert_bestplayers_to_mafia_setup("mafia/bestplayers.dat");
	}
	
    begin_setup:
	
	# Generate a random setup
	
	my ($force_role, %num) = choose_teams($setup, $numplayers, $teamweirdness, $test, $verbose);
	
	my %power;

	$power{town} = best_town_total_power(\%num, $setup, $numplayers);
	$power{town} /= $num{town} if $num{town} > 0;

	# Add some variability
	$power{town} += rand(0.4) - 0.2;

	$power{town} = 0.8 if $power{town} > 0.8;
	$power{town} = 0.1 if $power{town} < 0.1;
	$power{town} = 0.2 if $numplayers == 3;
	$power{town} = 0 unless $num{town};

	if ($verbose)
	{
		::bot_log sprintf "SETUP INFO mafia $num{mafia}" . ($num{mafia2} ? " + $num{mafia2}" : "") . ", wolf $num{wolf}, cult $num{cult}, sk $num{sk}, survivor $num{survivor}, town $num{town}\n";
		::bot_log sprintf "SETUP INFO weirdness %.2f, est kill ratio %.2f\n", $weirdness, estimated_kill_ratio(\%num);
	}

	my $targetpower = $num{town} * $power{town};

	my @bestroles;
	my $bestpowerdifference = 99999;
	my $besttotpower;

	my $maxroleattempts = 5;

	# Hack - the all-sk setup is "fair"
	$maxroleattempts = 1 if $force_role;

	for my $iter (1..$maxroleattempts)
	{
		my $townpowercount = ($num{town} - $num{townbad}) * $power{town};
		$townpowercount = $num{town} if $townpowercount > $num{town};

		# $num{townpower} = int($townpowercount * 0.4 + rand());
		# $num{townnormal} = int(($num{town} - $num{townbad} - $townpowercount) * 0.4 + rand());
		$num{townpower} = $num{townnormal} = 0;
		while ($num{townpower} + $num{townnormal} + $num{townbad} < $num{town})
		{
			rand() < $power{town} ? $num{townpower}++ : $num{townnormal}++;
		}
		while ($num{townpower} + $num{townnormal} > $num{town})
		{
			$num{townnormal}--;
		}

		foreach my $team (qw[mafia mafia2 wolf])
		{
			$power{$team} = $num{$team} > 0 ? (0.05 * ($numplayers - $num{$team}) + 0.20 * $num{townpower}) / $num{$team} : 0;
			$power{$team} = 0.8 if $power{$team} > 0.8;
		}

		if ($verbose)
		{
			::bot_log "SETUP INFO candidate $iter\n";
			::bot_log sprintf "SETUP INFO town $num{townpower} power, $num{townnormal} normal, $num{townbad} bad\n";
			::bot_log sprintf "SETUP INFO power %.2f/%.2f/%.2f/%.2f\n", $power{town}, $power{mafia}, $power{mafia2}, $power{wolf};
		}

		@roles = select_roles($setup, \%num, $weirdness, $numplayers, $test, \%power, $force_role);
		my @substitutes = map { $_->{role} } select_roles($setup, { townnormal => $numplayers, townpower => 0, townbad => 0, sk => 0, survivor => 0, cult => 0, mafia => 0, mafia2 => 0, wolf => 0 }, $weirdness, $numplayers, $test, \%power);

		# Postprocess
		sanitize_setup($setup, \@roles, $numplayers, $weirdness, \@substitutes, $verbose) unless setup_rule('nolimits', $setup);

		# Collect roles
		if (setup_rule('multiroles', $setup))
		{
			@roles = collect_multi_roles($setup, $numplayers, @roles);
		}
		if (setup_rule('rolechoices', $setup))
		{
			@roles = collect_choice_roles($setup, $numplayers, @roles);
		}
	
		# Count number of townies
		my $totpower = 0;
		my %teampower;
		foreach my $role (@roles)
		{
			my $team = $role->{team};
			my $roleid = $role->{role};
			my $power = role_power($roleid, $numplayers, 0, setup_rule('expand_power', $setup));
			$teampower{$team} += $power;
			next if $team ne 'town';
			$totpower += $power;
		}

		my $powerdifference = abs($totpower - $targetpower);
	
		::bot_log sprintf "SETUP INFO total power %.1f (target %.1f)\n", $totpower, $targetpower if $verbose;

		if ($powerdifference < $bestpowerdifference)
		{
			@bestroles = @roles;
			$bestpowerdifference = $powerdifference;
			$besttotpower = $totpower;
		}
	}

	::bot_log sprintf "SETUP INFO using total power %.1f (target %.1f)\n", $besttotpower, $targetpower if $verbose;
	return @bestroles;
}

sub collect_multi_roles {
	my ($setup, $numplayers, @roles) = @_;

	shuffle_list(\@roles);
	@roles = sort { $a->{baseteam} cmp $b->{baseteam} || $a->{team} cmp $b->{team} } @roles;

	my @newroles;
	while (@roles)
	{
		# Collect choices
		my @choiceroles;
		my %teamcount;
		my @startroles;
		choice: for (1 .. setup_rule('multiroles', $setup))
		{
			my $choicerole = shift @roles;
			if (!$choicerole)
			{
				::bot_log "OOPS! Missing role in multisetup\n",
				last;
			}
			push @startroles, $choicerole->{role};
			foreach my $testrole (@choiceroles)
			{	
				next choice if $choicerole->{role} eq $testrole->{role};
				next choice if role_name($choicerole->{role}) eq role_name($testrole->{role});
			}
			push @choiceroles, $choicerole;
			$teamcount{$choicerole->{team}}++;
		}

		# Pick one team
		my $team = (sort { $teamcount{$b} <=> $teamcount{$a} } keys %teamcount)[0];
		@choiceroles = grep { $_->{team} eq $team } @choiceroles;

		@choiceroles = sort { role_power($b->{role}, $numplayers) <=> role_power($a->{role}, $numplayers) } @choiceroles;

		@choiceroles = @choiceroles[0 .. (setup_rule('multiroles', $setup) - 1)] if @choiceroles > setup_rule('multiroles', $setup);

		# Shuffle choices
		shuffle_list(\@choiceroles);

		@choiceroles = sort { defined($role_config{$a->{role}}{alias}) <=> defined($role_config{$b->{role}}{alias}) } @choiceroles;

		# Make composite role
		my $startrole = join(',', @startroles );
		my $newrole = { team => $choiceroles[0]{team}, baseteam => $choiceroles[0]{baseteam}, role => join('+', map { $_->{role} } @choiceroles) };
		my $midrole = $newrole->{role};
		
		my @parts;
		foreach my $multirole (map { $_->{role} } @choiceroles)
		{
			my @multiparts = grep { $_ !~ /^\*/ } recursive_expand_role($multirole);
			@multiparts = $multiparts[$#multiparts] if @parts && setup_rule('special_combine', $setup);
			shift @multiparts if @parts && @multiparts > 1 && !$role_config{$multiparts[0]}{minrole} && rand() < 0.5;
			push @parts, @multiparts;
		}

		# Special - Chance of combining abilities
		if (rand() < 0.5) {
			my @templates = qw[template_comb template_alt];
			push @parts, $templates[rand @templates];
		}

		# Canonicalize
		$newrole->{role} = canonicalize_role(join('+', @parts), 1, $newrole->{team});

		# ::bot_log "MULTIROLE $newrole->{team} $startrole -> $midrole -> $newrole->{role}\n";

		# Give a funny name
		if ($newrole->{role} =~ /\+/ && rand() < 0.5)
		{
			$newrole->{name} = $funny_roles[rand @funny_roles];
			# ::bot_log "NAME $newrole->{role} $newrole->{name}\n";
		}

		push @newroles, $newrole;
	}

	return @newroles;
}

sub collect_choice_roles {
	my ($setup, $numplayers, @roles) = @_;

	my %power;
	foreach my $role (@roles)
	{
		$power{$role} = role_power($role->{role}, $numplayers) + rand(1.5);
	}
	@roles = sort { $a->{baseteam} cmp $b->{baseteam} || $a->{team} cmp $b->{team} || $power{$a} <=> $power{$b} } @roles;
	my @newroles;
	while (@roles)
	{
		# Collect choices
		my @choiceroles;
		my %teamcount;
		my @startroles;
		choice: for (1 .. setup_rule('rolechoices', $setup))
		{
			my $choicerole = shift @roles;
			if (!$choicerole)
			{
				::bot_log "OOPS! Missing role in multisetup\n",
				last;
			}
			push @startroles, $choicerole->{role};
			foreach my $testrole (@choiceroles)
			{	
				next choice if $choicerole->{role} eq $testrole->{role};
				next choice if role_name($choicerole->{role}) eq role_name($testrole->{role});
			}
			push @choiceroles, $choicerole;
			$teamcount{$choicerole->{team}}++;
		}

		#::bot_log "CHOICES " . join(' ', map { $_->{role} . "/" . $_->{team} } @choiceroles) . "\n";

		# Pick one team
		my $team = (sort { $teamcount{$b} <=> $teamcount{$a} } keys %teamcount)[0];
		@choiceroles = grep { $_->{team} eq $team } @choiceroles;

		@choiceroles = sort { role_power($b->{role}, $numplayers) <=> role_power($a->{role}, $numplayers) } @choiceroles;

		@choiceroles = @choiceroles[0 .. (setup_rule('maxchoices', $setup) - 1)] if @choiceroles > setup_rule('maxchoices', $setup);

		# Shuffle choices
		shuffle_list(\@choiceroles);

		@choiceroles = sort { role_name($a->{role}) cmp role_name($b->{role}) } @choiceroles;

		#::bot_log "CHOICES2 " . join(' ', map { $_->{role} . "/" . $_->{team} } @choiceroles) . "\n";

		# Make composite role
		push @newroles, { team => $choiceroles[0]{team}, role => join(',', map { $_->{role} } @choiceroles) };
	}

	return @newroles;
}

sub choose_teams {
	my ($setup, $numplayers, $weirdness, $test, $verbose) = @_;
	my %num;
	my $force_role;

	#                3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24
	my @numscum = qw(1 1 1 2 2 2 2  2  3  3  3  3  3  4  4  4  4  4  4  4  4  5);
	my @minscum = qw(1 1 1 1 2 2 2  2  2  2  2  2  2  2  2  3  3  3  3  3  3  4);

	#              0    1    2    3    4    5
	my @cultp = qw(0 0.20 0.30 0.40 0.40 0.40);

	my $nolimits = setup_rule('nolimits', $setup);
	
	my $neutralfactor = setup_rule('neutralfactor', $setup) || ($weirdness > 0.5 ? 0.5 : $weirdness);
	my $badfactor = $neutralfactor;
	$badfactor = 0 if setup_rule('nobad', $setup);
	my $maxneutral = $numplayers < 5 ? 1 : int($numplayers / 5);
	$maxneutral = int(6 * $weirdness) if $maxneutral > int(6 * $weirdness);
	$maxneutral++ if rand() < 0.5 * $weirdness * $weirdness;
	$maxneutral = 0 if setup_rule('noneutral', $setup);
	$num{neutral} = int($neutralfactor * (rand($numplayers / 4) + rand($numplayers / 4) + $numplayers / 10 + 0.2));
	$num{neutral} = $maxneutral if $num{neutral} > $maxneutral && !setup_rule('nolimits', $setup);
	$num{neutral} = 0 if setup_rule('noneutral', $setup);
	
	# Divide neutrals into sk, survivor, and cult
	my $cultmultiplier = 1 + int($numplayers / 10);
	$num{cult} = ($numplayers >= 6 && (rand() < $cultp[$num{neutral} > 5 ? 5 : $num{neutral}] * $weirdness) ? 1 : 0);
	$num{cult} = 0 if setup_rule('nocult', $setup);
	$num{survivor} = 0; 
	for (1 .. $num{neutral} - $num{cult} * $cultmultiplier) { 
		if (rand() < 0.5 - 0.2 * $num{survivor})
		{
			$num{survivor}++;
		}
	}
	$num{survivor} = 0 if setup_rule('nosurvivor', $setup);
	$num{sk} = $num{neutral} - $num{survivor} - $num{cult} * $cultmultiplier;
	$num{sk} = 0 if $num{sk} < 0;

	$num{neutral} = $num{sk} + $num{survivor} + $num{cult};

	$num{townbad} = int(0.5 * $badfactor * (rand($numplayers / 4) + rand($numplayers / 4) + $numplayers / 10 + 0.2) + 0.25);
	
	# Adjusted number of players for calculating # of mafia
	my $adjplayers = $numplayers - int(rand(0.5 * $num{survivor} + 0.5 * $num{townbad} + 1.5 * $num{sk} + 5 * $num{cult} + 1));
	my $adjplayers2 = 0;

	# Some setups have more or fewer town players
	my $townplayermult = setup_rule('townplayermult', $setup) || 1;
	$adjplayers *= $townplayermult;
	$adjplayers = int($adjplayers);
	
	# Sometimes have two mafias
	if ($numplayers >= 10 && rand(1) < 0.5 * $weirdness * $weirdness)
	{
		$adjplayers2 = int($adjplayers * (0.4 + rand(0.2)));
		$adjplayers -= $adjplayers2;
		
		$adjplayers += int(rand(3) + 1);
		$adjplayers2 += int(rand(3) + 1);
	}

	my $maxmafia = $numplayers < 3 ? 0 : ($numscum[$numplayers - 3] || 5);

	# Remaining players become mafia and town
	$num{mafia} = $adjplayers < 3 ? 0 : ($numscum[$adjplayers - 3] || 5);
	$num{mafia2} = $adjplayers2 < 3 ? 0 : ($numscum[$adjplayers2 - 3] || 5);
	$num{town} = $numplayers - ($num{sk} + $num{survivor} + $num{cult} + $num{mafia} + $num{mafia2});
	$num{wolf} = 0;

	# Sometimes have werewolves instead of a mafia group
	if (setup_rule('allowwolf', $setup)) {
		if ($num{mafia2} > 0) {
			if (rand(1) < 0.5 * $weirdness) {
				$num{wolf} = $num{mafia2};
				$num{mafia2} = 0;
			}
		}
		elsif ($num{mafia} > 0) {
			if (rand(1) < 0.2 * $weirdness) {
				$num{wolf} = $num{mafia};
				$num{mafia} = 0;
			}
		}
	}

	my $difficulty = rand(0.5);
	my $minscum = $numplayers < 3 ? 1 : ($minscum[$numplayers - 3] || 4);

	if ($verbose)
	{	
		my $ekr = estimated_kill_ratio(\%num);
		::bot_log "SETUP INFO neutral $num{neutral} (cult $num{cult}, sk $num{sk}, survivor $num{survivor})\n";
		::bot_log "SETUP INFO adj players $adjplayers; mafia $num{mafia}" . ($num{mafia2} ? " + $num{mafia2}" : "") . ", wolf $num{wolf}, town $num{town}\n";	
		::bot_log sprintf "SETUP INFO initial est kill ratio %.2f (townies %i/%i)\n", $ekr, $num{town}, ($numplayers - $num{survivor});
		::bot_log sprintf "SETUP INFO difficulty %.2f, min town %.2f, min scumgroup %i\n", $difficulty, $numplayers * $ekr - $difficulty, $minscum;
	}
	
	foreach my $group (qw[mafia mafia2 wolf]) {
		if ($num{$group} && $num{$group} < $minscum) {
			my $adj = $minscum - $num{$group};
			::bot_log "SETUP CONVERTING $adj town to $group (scumgroup too small)\n" if $verbose;
			$num{$group} += $adj;
			$num{town} -= $adj;
		}
	}

	unless (setup_rule('no_group_actions', $setup))
	{
		# Sometimes convert multiple SKs into a second mafia
		if ($num{sk} >= 2 && $num{mafia} >= 2 && $num{mafia2} == 0 && rand() < 0.25 * $num{sk})
		{
			::bot_log "SETUP CONVERTING $num{sk} sk to mafia2 (multiple sks)\n" if $verbose;
			$num{mafia2} = $num{sk};
			$num{sk} = 0;
		}

		# Limit number of antitown kills
		my $maxscumkills = 2 + int($numplayers / 12);
		$maxscumkills++ if rand() < $weirdness * $weirdness;

		while ($num{sk} + ($num{mafia} ? 1 : 0) + ($num{mafia2} ? 1 : 0) + ($num{wolf} ? 1 : 0) > $maxscumkills && $num{sk} > 0)
		{
			::bot_log "SETUP CONVERTING 1 sk to town (too many killers)\n" if $verbose;
			$num{sk}--;
			$num{town}++;
		}

		# Town shouldn't have it too good
		while (($num{town} > 0 &&
			0.8 * $num{town} * $townplayermult - 1 + $difficulty > $numplayers * estimated_kill_ratio(\%num) &&
			$num{town} * $townplayermult > $numplayers * 0.66))
		{
			if (($num{mafia} < $maxmafia && rand() < 0.7) || $num{sk} + $num{cult} + $num{survivor} >= $maxneutral)
			{
				::bot_log "SETUP ADDING 1 mafia (too easy)\n" if $verbose;
				$num{mafia}++;
				$num{town}--;
			}
			else
			{
				::bot_log "SETUP ADDING 1 sk (too easy)\n" if $verbose;
				$num{sk}++;
				$num{town}--;
			}
		}

		# Town must have a reasonable chance to win by lynching, and must be at least 60% of players
		# Survivors don't count, and cults count one townie as cult
		while ($num{town} > 0 &&
			$num{town} * $townplayermult + 0.6 * $num{survivor} + $difficulty < $numplayers * estimated_kill_ratio(\%num) ||
			$num{town} * $townplayermult - $num{cult} * $cultmultiplier < ($numplayers - $num{survivor}) * 0.6)
		{
			# Remove a mafioso, sk, or cult leader at random

			my %choice;
			
			foreach my $team (qw[mafia mafia2 wolf sk cult survivor])
			{
				$choice{$team} = $num{$team};
				if ($team =~ /mafia|wolf/ && $choice{$team} > 0) {
					$choice{$team} -= $minscum;
					$choice{$team} = 0 if $choice{$team} < 0;
				}
			}
			
			my $total = $choice{mafia} + $choice{mafia2} + $choice{wolf} + $choice{sk} + $choice{cult} + 0.5 * $choice{survivor};
			last if $total <= 0;

			my $select = rand($total);

			foreach my $team (qw[mafia mafia2 wolf sk cult survivor])
			{
				if (($select -= $choice{$team}) < 0)
				{
					::bot_log "SETUP REMOVING 1 $team (too hard)\n" if $verbose;
					$num{$team}--;
					$num{town}++;
					last;
				}
			}
		}
	}
	else 
	{
		foreach my $team (qw[mafia mafia2 wolf])
		{
			while ($num{$team} > $maxmafia)
			{
				::bot_log "SETUP REMOVING 1 $team (too many)\n" if $verbose;
				$num{$team}--;
				$num{town}++;
			}
		}
	}

	# A 7+ player setup must have at least 2 scum or a cult.
	while ($numplayers >= 7 && $num{cult} == 0 && $num{mafia} + $num{mafia2} + $num{wolf} + $num{sk} < 2)
	{
		if ($num{survivor} > 0)
		{
			::bot_log "SETUP CONVERTING 1 survivor to mafia (not enough scum)\n" if $verbose;
			$num{survivor}--;
			$num{mafia}++;
		}
		else
		{
			::bot_log "SETUP CONVERTING 1 town to mafia (not enough scum)\n" if $verbose;
			$num{town}--;
			$num{mafia}++;
		}
	}
	
	# An 8+ player setup should have at least 2 mafia most of the time
	unless (rand() < 0.4 * $weirdness)
	{
		while ($numplayers >= 8 && $num{cult} == 0 && $num{mafia} < 2 && $num{wolf} < 2)
		{
			foreach my $team (qw[wolf mafia2 sk survivor town])
			{
				if ($num{$team} > 0)
				{
					::bot_log "SETUP CONVERTING 1 $team to mafia (not enough mafia)\n" if $verbose;
					$num{$team}--;
					$num{mafia}++;
					last;
				}
			}
		}
	}
	
	# If no cult/sk and no survivor ensure minimum number of mafia
	if ($num{mafia} + $num{town} == $numplayers && $num{townbad} == 0 && $num{mafia} != ($numscum[int($numplayers * $townplayermult) - 3] || 5))
	{
		::bot_log "SETUP RESETTING to default mafia\n" if $verbose;
		$num{mafia} = ($numscum[int($numplayers * $townplayermult) - 3] || 5);
		$num{town} = $numplayers - $num{mafia};
	}
	
	# Must be at least 1 scum
	if (!$num{mafia} && !$num{mafia2} && !$num{wolf} && !$num{sk} && !$num{cult})
	{
		::bot_log "SETUP ADDING 1 mafia (no scum)\n" if $verbose;
		$num{town}--;
		$num{mafia}++;
	}

	# Sometimes convert a lone mafia to a serial killer
	foreach my $team (qw[mafia mafia2 wolf])
	{
		if ($num{$team} == 1 && (rand() < 0.3 || $numplayers >= 7) && !setup_rule('noneutral', $setup))
		{
			::bot_log "SETUP CONVERTING 1 $team to sk (not enough $team)\n" if $verbose;
			$num{$team}--;
			$num{sk}++;
		}
	}
	
	# Sometimes make an all-SK setup
	if ($numplayers <= 12 && rand() < ($nolimits ? 0.05 : 0.01 * $weirdness * $weirdness))
	{
		::bot_log "SETUP CONVERTING everyone to sk\n" if $verbose;
		$num{sk} = $numplayers - $num{mafia} - $num{mafia2};
		$num{cult} = 0;
		$num{survivor} = 0;
		$num{town} = 0;
		
		my $theme = setup_rule('theme', $setup) || "normal";
		if (($role_config{psy}{theme} || "normal") =~ /\b$theme\b/ && rand() < 0.5)
		{
			$num{sk}--;
			$num{town}++;
			$force_role = "psy";
		}
	}
	
	# If there is no mafia, convert mafia2 to mafia
	if ($num{mafia} == 0 && $num{mafia2} > 0)
	{
		::bot_log "SETUP CONVERTING all mafia2 to mafia (no mafia)\n" if $verbose;
		$num{mafia} = $num{mafia2};
		$num{mafia2} = 0;
	}

	# Equalize mafia and mafia2
	if ($num{mafia} > 0 && $num{mafia2} > 0)
	{
		my $totmafia = $num{mafia} + $num{mafia2};
		::bot_log "SETUP REDIVIDING $totmafia scum into mafia and mafia2\n" if $verbose;
		$num{mafia2} = int($totmafia / 2);
		$num{mafia} = $totmafia - $num{mafia2};
	}
	
	# In 3 player, occasionally add a survivor
	if ($numplayers == 3 && $num{town} > 0 && $num{survivor} == 0 && rand() < 0.2 && !setup_rule('nosurvivor', $setup))
	{
		::bot_log "SETUP CONVERTING 1 town to survivor (3 player)\n" if $verbose;
		$num{town}--;
		$num{survivor}++;
	}

	return ($force_role, %num);	
}

sub select_roles {
	my ($setup, $num, $weirdness, $numplayers, $test, $power, $force_role) = @_;
	my %num = %$num;
	my %power = %$power;

	my $townpowermult = (setup_rule('rolechoices', $setup) || setup_rule('multiroles', $setup)) ? 0.5 : 1;
	my $townpowershift = 0;

	my $rolechoices = (setup_rule('rolechoices', $setup) || 1) * (setup_rule('multiroles', $setup) || 1);

	if ($rolechoices > 2)
	{
		$townpowershift = int($num{townpower} * ($rolechoices - 2));
	}

	my (@townrolesbasic, @townrolesweird);
	my (@mafiarolesbasic, @mafiarolesweird, @skrolesbasic, @skrolesweird);
	my (@wolfrolesbasic, @wolfrolesweird);
	my (@survivorrolesbasic, @survivorrolesweird, @cultroles);
	
	foreach my $role (keys %role_config)
	{
		next unless $role_config{$role}{setup};
		
		my $theme = setup_rule('theme', $setup) || "normal";
		next unless ($role_config{$role}{theme} || "normal") =~ /\b$theme\b/;
		next if $test && role_is_secret($role);
		
		foreach my $group (split /,/, $role_config{$role}{setup})
		{
			if ($group =~ /mafia-ally/)
			{
				push @survivorrolesweird, "$role/mafia-ally",
			}
			elsif ($group =~ /town-ally/)
			{
				push @survivorrolesweird, "$role/town-ally",
			}
			elsif ($group =~ /jester/)
			{
				push @survivorrolesweird, "$role/jester",
			}
			elsif ($group =~ /lyncher/)
			{
				push @survivorrolesweird, "$role/lyncher",
			}
			elsif ($group =~ /town/)
			{
				if ($group =~ /bad/)
				{
					push @survivorrolesweird, "$role/town";
				}
#				elsif ($group =~ /power/)
#				{
#					push @townrolespowerweird, $role;
#					push @townrolespower, $role if $group =~ /basic/;
#				}
				else
				{
					push @townrolesweird, $role;
					push @townrolesbasic, $role if $group =~ /basic/;
				}
			}
			elsif ($group =~ /mafia/)
			{
				push @mafiarolesweird, $role;
				push @mafiarolesbasic, $role if $group =~ /basic/;
			}
			elsif ($group =~ /wolf/)
			{
				push @wolfrolesweird, $role;
				push @wolfrolesbasic, $role if $group =~ /basic/;
			}
			elsif ($group =~ /survivor/)
			{
				push @survivorrolesweird, $role;
				push @survivorrolesbasic, $role if $group =~ /basic/;
			}
			elsif ($group =~ /sk/)
			{
				push @skrolesweird, $role;
				push @skrolesbasic, $role if $group =~ /basic/;
			}
			elsif ($group =~ /cult/)
			{
				push @cultroles, $role;
			}
		}
	}

	my @roles;

	# Choose specific roles
	for (1 .. $num{mafia} * $rolechoices)
	{
		my $rolesweird = (\@mafiarolesweird);
		my $rolesbasic = (\@mafiarolesbasic);
		my $role = select_role($setup, (rand() < $weirdness ? $rolesweird : $rolesbasic), $numplayers, \%num, $power{mafia}, $weirdness, "mafia");
		push @roles, { role => $role, team => "mafia" };
	}
	for (1 .. $num{mafia2} * $rolechoices)
	{
		my $rolesweird = (\@mafiarolesweird);
		my $rolesbasic = (\@mafiarolesbasic);
		my $role = select_role($setup, (rand() < $weirdness ? $rolesweird : $rolesbasic), $numplayers, \%num, $power{mafia2}, $weirdness, "mafia");
		push @roles, { role => $role, team => "mafia2" };
	}
	for (1 .. $num{wolf} * $rolechoices)
	{
		my $rolesweird = \@wolfrolesweird;
		my $rolesbasic = \@wolfrolesbasic;
		my $role = select_role($setup, (rand() < $weirdness ? $rolesweird : $rolesbasic), $numplayers, \%num, $power{wolf}, $weirdness, "wolf");
		push @roles, { role => $role, team => "wolf" };
	}
	for my $sk_id (1 .. $num{sk})
	{
		for (1 .. $rolechoices)
		{
			my $role = select_role($setup, (rand() < $weirdness ? \@skrolesweird : \@skrolesbasic), $numplayers, \%num, 0.9, $weirdness, "sk");
			push @roles, { role => $role, team => "sk" . ($num{sk} == 1 ? "" : $sk_id) };
		}
	}
	for my $cult_id (1 .. $num{cult})
	{
		for (1 .. $rolechoices)
		{
			my $role = select_role($setup, \@cultroles, $numplayers, \%num, 1, $weirdness, "cult");
			push @roles, { role => $role, team => "cult" . ($num{cult} == 1 ? "" : $cult_id) };
		}
	}
	for my $survivor_id (1 .. $num{survivor})
	{
		for (1 .. $rolechoices)
		{
			my $role = select_role($setup, (rand() < $weirdness ? \@survivorrolesweird : \@survivorrolesbasic), $numplayers, \%num, 0.25, $weirdness, "survivor");
			push @roles, { role => $role, team => "survivor" . ($num{survivor} == 1 ? "" : $survivor_id) };
		}
	}
	for my $town_id (1 .. $num{townnormal} * $rolechoices + $townpowershift)
	{
		my $role = select_role($setup, (rand() < $weirdness ? \@townrolesweird : \@townrolesbasic), $numplayers, \%num, $power{town}, $weirdness, "town", 0, $townpowermult);
		$role = $force_role if $force_role;
		push @roles, { role => $role, team => "town" };
	}
	for (1 .. $num{townpower} * $rolechoices - $townpowershift)
	{
		my $role = select_role($setup, (rand() < $weirdness ? \@townrolesweird : \@townrolesbasic), $numplayers, \%num, $power{town}, $weirdness, "town", 1, $townpowermult);
		$role = $force_role if $force_role;
		push @roles, { role => $role, team => "town" };
	}
	for (1 .. $num{townbad} * $rolechoices)
	{
		my $role = select_role($setup, (rand() < $weirdness ? \@townrolesweird : \@townrolesbasic), $numplayers, \%num, $power{town}, $weirdness, "town", -1, $townpowermult);
		$role = $force_role if $force_role;
		push @roles, { role => $role, team => "town" };
	}
	
	# Some roles have special teams
	foreach my $role (@roles)
	{
		$role->{baseteam} = $role->{team};
		$role->{team} = $1 if $role->{role} =~ s{/(.*)$}{};
	}
	
	return @roles;
}

sub count_roles {
	my ($roles, $action_count, $role_count) = @_;

	foreach my $action (keys %action_config)
	{
		$action_count->{$action} = 0;
	}
	foreach my $role (@$roles)
	{
		$role_count->{$role->{team}}{count_role_as($role->{role})}++;
		$role_count->{$role->{team}}{'=' . $role->{role}}++;
		$role_count->{$role->{team}}{'*'}++;
		$role_count->{'*'}{count_role_as($role->{role})}++;
		$role_count->{'*'}{'=' . $role->{role}}++;
		my $actions = $role_config{$role->{role}}{actions};
		my $group_actions = $group_config{$role->{team}}{actions};
		foreach my $action (@$actions, @$group_actions)
		{
			my $shortaction = action_base($action);
			my $uses = 3;
			
			$uses = $1 if $action =~ /;(\d+)$/;

			next if $role_config{$role->{role}}{status}{failure} && $role_config{$role->{role}}{status}{failure} >= 75;
			next if $role_config{$role->{role}}{status}{"failure$action"} && $role_config{$role->{role}}{status}{"failure$action"} >= 75;
			#next if $shortaction eq 'inspect' && $role_config{$role->{role}}{status}{sanity} && ($role_config{$role->{role}}{status}{sanity} eq 'paranoid' ||
			#	$role_config{$role->{role}}{status}{sanity} eq 'naive');
			
			$action_count->{$shortaction} += $uses / 3;
		}
	}

}

sub sanitize_setup {
	my ($setup, $roles, $numplayers, $weirdness, $substitutes, $verbosity) = @_;

	# Sort to put masons/siblings last, roles with checks last, and other roles from least to most powerful within each team
	use sort 'stable';
	@$roles = sort { 
		($role_config{$a->{role}}{minrole} || 0) <=> ($role_config{$b->{role}}{minrole} || 0) ||
		($role_config{$a->{role}}{setup_checks} ? 1 : 0) <=> ($role_config{$b->{role}}{setup_checks} ? 1 : 0) ||
		$a->{team} cmp $b->{team} ||		
		role_power($a->{role}, $numplayers) <=> role_power($b->{role}, $numplayers)		
	} @$roles;

	::bot_log("SETUP ROLES0 " . join(' ', map { "$_->{role}/$_->{team}" } @$roles) . "\n") if $verbosity;
	
	foreach my $pass (1, 2)
	{
		foreach my $role (@$roles)
		{
			my %role_count = ();
			my %action_count = ();
			count_roles($roles, \%action_count, \%role_count);
	
			$role->{role} = preconvert_role($setup, $role->{role}, $role->{team}, \%role_count, \%action_count, $numplayers, $weirdness, $substitutes, $verbosity, $pass);
		}
	}

	::bot_log("SETUP ROLES1 " . join(' ', map { "$_->{role}/$_->{team}" } @$roles) . "\n") if $verbosity;
}

sub best_town_total_power {
	my ($num, $setup, $numplayers) = @_;

	# Determine number of power roles vs normal townies
	# According to statistics on MafiaScumWiki, with no power roles at all, each additional mafioso requires about 8 additional townies.
	# The MC9 setup, which is considered fairly balanced, has 2 power roles with 5 townies and 2 mafia.
	# The C9 setup, also considered fairly balanced, has an average of 1 power role with 5 townies and 2 mafia.
	# 
	# The actual numbers below are derived from Math(tm) using data from the above and some MafiaScum games.
	my $power = 0;
	foreach my $team (qw[mafia mafia2 wolf])
	{
		next unless $num->{$team};
		$power += $num->{$team} * 3.00 - 1.60;
	}
	$power += 1.40 * $num->{sk};
	$power += (1.40 + 0.60 * $numplayers) * $num->{cult};
	$power -= 0.5 * $num->{survivor};
	$power -= $num->{town} * 0.9;
	$power += 2.3;

	$power *= setup_rule('townpowermult', $setup) || 1;

	return $power;
}

sub select_role {
	my ($setup, $rolelist, $numplayers, $num, $power, $weirdness, $team_name, $dopower, $thresholdmult) = @_;

	my $nolimits = setup_rule('nolimits', $setup);
	
	my $numtries;

	my $threshold = 0.3 + 0.25 * $power;
	$threshold *= $thresholdmult if defined($thresholdmult);
	my $threshold2 = -0.1;
	$threshold2 = -0.5 if defined($thresholdmult);
	$threshold2 = -2.0 if setup_rule('noneutral', $setup);
	my $exp = ($weirdness > 0.75 ? 4 - 4 * $weirdness : 1);
	$exp = setup_rule('exp', $setup) if setup_rule('exp', $setup);
	
	$dopower = (rand() < $power ? 1 : 0) if !defined($dopower);

	my @role;

	my $rolechoices = 1;

	my @rolechoices = filter_roles($setup, $rolelist, $numplayers, $num, $team_name);
	my $minrarity;

	my $ismultirole = setup_rule('multiroles', $setup) ? 1 : 0;

	my @xrolechoices = grep {
		my $shortrole = $_;
		$shortrole =~ s/\/.*$//;
		my $power = role_power($shortrole, $numplayers, $ismultirole, setup_rule('expand_power', $setup));
		($dopower > 0 && $power > $threshold) || ($dopower == 0 && $power <= $threshold && $power > $threshold2) || ($dopower < 0 && $power <= $threshold2);
	} @rolechoices;
	@rolechoices = @xrolechoices if @xrolechoices;

	foreach my $role (@rolechoices)
	{
		my $shortrole;
		($shortrole = $role) =~ s/\/.*$//;

		my $rarity = $role_config{$shortrole}{rarity} || 1;
		my $minplayers = $role_config{$shortrole}{minplayers} || 3;
		# $rarity = $role_config{$shortrole}{multirolerarity} if $role_config{$shortrole}{multirolerarity} && setup_rule('multiroles', $setup);
		if (setup_rule('oddrole', $setup)) {
			$rarity = 1 + ($role_config{$shortrole}{changecount} || 0);
			#$rarity = 1 + ($role_config{$shortrole}{seencount} || 0);
			$rarity += 40 if $role_config{$role}{nonadaptive};
		}
		$rarity = $rarity ** $exp;
		$rarity *= ($numplayers - $minplayers + 1) if $numplayers > $minplayers && !$nolimits;

		$minrarity = $rarity if !defined($minrarity) || $rarity < $minrarity;
	}

	return 't' unless @rolechoices;

	# ::bot_log("ROLECHOICES @rolechoices\n") if @rolechoices < 20;

	for (1 .. $rolechoices)
	{
		$numtries = 0;
		my ($role, $shortrole);
		while (1)
		{
			return 't' if ++$numtries >= 1000;
			$role = $rolechoices[rand @rolechoices];;
			($shortrole = $role) =~ s/\/.*$//;

			my $rarity = $role_config{$shortrole}{rarity} || 1;
			my $minplayers = $role_config{$shortrole}{minplayers} || 3;
			# $rarity = $role_config{$shortrole}{multirolerarity} if $role_config{$shortrole}{multirolerarity} && setup_rule('multiroles', $setup);
			if (setup_rule('oddrole', $setup)) {
				$rarity = 1 + ($role_config{$shortrole}{changecount} || 0);
				#$rarity = 1 + ($role_config{$shortrole}{seencount} || 0);
				$rarity += 40 if $role_config{$role}{nonadaptive};
			}
			$rarity = $rarity ** $exp;
			$rarity *= ($numplayers - $minplayers + 1) if $numplayers > $minplayers && !$nolimits;
			#::bot_log "TRYROLE $role $rarity/$minrarity\n";

			next if rand($rarity) > $minrarity;

			last;

		}

		push @role, $role;
	}

	my @shortrolechoices = @rolechoices > 9 ? (@rolechoices[0..9], "...") : @rolechoices;
	#::bot_log("SELECTROLE $team_name $dopower @shortrolechoices -> @role\n");
	
	::bot_log "ERROR! No role from (", join(" ", @$rolelist), ")\n" unless @role;
	# ::bot_log "ROLE setup $setup power $power threshold $threshold dopower $dopower weirdness $weirdness numtries $numtries role @role\n";

	return join(',', @role);
}

sub preconvert_role {
	my ($setup, $role, $team, $role_count, $action_count, $numplayers, $weirdness, $substitutes, $show_convert, $pass) = @_;
	my $orig_role = $role;
	my $count_role = count_role_as($role);
	my %team_count;
	
	$weirdness = 0.5 if $weirdness > 0.5;

	my $unique_bias = 1;
	$unique_bias = 0 if setup_rule('rolechoices', $setup) || setup_rule('multiroles', $setup);
	
	#::bot_log "ROLE $role $team $role_count->{$team}{$count_role}\n";
	
	foreach my $team (keys %$role_count)
	{
		next if $team eq '*';
		my $shortteam = $team;
		$shortteam =~ s/\d+$//;
		$team_count{$shortteam} += $role_count->{$team}{'*'};
	}
		
	# Count allies as being part of the original team
	my $baseteam = $team;
	$baseteam =~ s/-ally$//;
	my $teamsize = $role_count->{$team}{'*'};
	$teamsize += ($role_count->{$baseteam}{'*'} || 0) if $baseteam ne $team;
	
	# Enforce minimum setup size
	if (($role_config{$role}{minplayers}   || 0) > $numplayers || 
		($role_config{$role}{minteam}  || 0) > $teamsize ||
		($role_config{$role}{minmafia} || 0) > ($team_count{mafia} || 0) || 
		($role_config{$role}{minwolf}  || 0) > ($team_count{wolf}  || 0) ||
		($role_config{$role}{minsk}    || 0) > ($team_count{sk}    || 0) ||
		($role_config{$role}{mincult}  || 0) > ($team_count{cult}  || 0) ||
		($role_config{$role}{minscum}  || 0) > ($team_count{mafia} || 0) + ($team_count{sk} || 0) ||
		($role_config{$role}{minrole}  || 0) > ($role_count->{'*'}{"=$role"}))
	{
		$role = setup_baserole($setup, 't') if $team =~ /town/;
		$role = setup_baserole($setup, 'm') if $team =~ /mafia/;
		$role = setup_baserole($setup, 'sk') if $team =~ /sk/;
		$role = setup_baserole($setup, 'sv') if $team =~ /survivor/;
		$role = setup_baserole($setup, 'wolf') if $team =~ /wolf/;
	}
	
	# Convert (1st)
	if ($role ne $orig_role)
	{
		$role_count->{$team}{$count_role}--;
		$role_count->{$team}{"=$orig_role"}--;
		$role_count->{'*'}{$count_role}--;
		$role_count->{'*'}{"=$orig_role"}--;
		$count_role = count_role_as($role);
		$role_count->{$team}{$count_role}++;
		$role_count->{$team}{"=$role"}++;
		$role_count->{'*'}{$count_role}++;
		$role_count->{'*'}{"=$role"}++;
		::bot_log "PRECONVERT${pass}-SETUP $orig_role ($team) to $role\n" if $show_convert;
		$orig_role = $role;
	}
	
	my $mafiakills = ($team_count{mafia} || 0) > 1 ? $action_count->{mafiakill} / 2 : $action_count->{mafiakill};
	my $regkills = $action_count->{"kill"} + $action_count->{mup} / 4 + $action_count->{kill2} * 2 + $mafiakills + $action_count->{absorb} 
	+ $action_count->{infect} + $action_count->{trick} + $action_count->{drain};
	
	# If there are a lot of poisoners, sometimes convert doctor to poison doctor
	$role = 'dpoison' if $pass == 1 && $role eq 'd' && rand($regkills + 2 * $action_count->{recruit} + $action_count->{poison}) < $action_count->{poison};
	
	# If there is a cult, sometimes convert doctor to missionary
	$role = 'miss' if $pass == 1 && $role eq 'd' && rand($regkills + 2 * $action_count->{recruit}) < 2 * $action_count->{recruit};

	# If there are no killing roles at all, some roles are useless
	if (!$regkills)
	{
		# Doctor is useless, convert to poison doctor, missionary, or townie/mafioso
		$role = ($team eq 'mafia' ? 'm' : 't') if $role eq 'd' || $role eq 'dhalf';

		# Angel is partially useless, convert to poison doctor or reviver
		$role = ($action_count->{poison} ? 'dpoison' : 'rv1') if $role eq 'drev';
		
		# Kill immunity is useless, convert to the base role
		$role = 't' if $role eq 'tik';
		$role = ($team =~ /sk/ ? 'sk' : 'v') if $role eq 'vik';
	}

	# Never have more than two siblings
	$role = ($team =~ /mafia/ ? 'm' : 't') if $count_role eq 'sib' && $role_count->{'*'}{$count_role} > 2;
	
	# Convert (2nd)
	if ($role ne $orig_role)
	{
		$role_count->{$team}{$count_role}--;
		$role_count->{$team}{"=$orig_role"}--;
		$role_count->{'*'}{$count_role}--;
		$role_count->{'*'}{"=$orig_role"}--;
		$count_role = count_role_as($role);
		$role_count->{$team}{$count_role}++;
		$role_count->{$team}{"=$role"}++;
		$role_count->{'*'}{$count_role}++;
		$role_count->{'*'}{"=$role"}++;
		::bot_log "PRECONVERT${pass}-ACT   $orig_role ($team) to $role\n" if $show_convert;
		$orig_role = $role;
	}
	
	my $maxnum = $role_config{$role}{maxnum} || 1;
	$unique_bias = 0 if $maxnum > 1;
	if (role_power($role, $numplayers) > 0.5)
	{
		$maxnum *= setup_rule('maxchoices', $setup) if setup_rule('maxchoices', $setup);
	}
	#::bot_log "ROLE $role ($team) = $count_role: count $role_count->{$team}{$count_role}, max $maxnum\n";
	
	# If there are several of one role (other than mafioso or townie) possibly convert some of them to vanilla of the appropriate team
	while ($pass == 1 && $team =~ /town|mafia/ && !$role_config{$role}{unlimited} && !$role_config{$role}{minrole} && $role_count->{$team}{$count_role} >= 2 && rand($role_count->{$team}{$count_role} + $unique_bias) > $maxnum)
	{
		if ($team =~ /mafia/)
		{
			$role = setup_baserole($setup, 'm');
		}
		elsif ($count_role eq 'd' && ($role_count->{$team}{"=d"} || 0) >= ($role eq 'd' ? 2 : 1) && !$role_count->{$team}{"=dbackup"} && rand() < $weirdness)
		{
			# If there's a doctor, possibly change to backup doctor
			$role = 'dbackup';
		}
		elsif ($count_role eq 'c' && ($role_count->{$team}{"=c"} || 0) >= ($role eq 'c' ? 2 : 1) && !$role_count->{$team}{"=cbackup"} && rand() < $weirdness)
		{
			# If there's a cop, possibly change to backup cop
			$role = 'cbackup';
		}
		elsif ($role_config{$role}{changeto} && rand() < $weirdness)
		{
			# Check for a role or roles to change to
			my @newrole = split /,/, $role_config{$role}{changeto};
			$role = $newrole[rand @newrole];
		}
		elsif (!$role_config{$role}{nochange})
		{
			$role = setup_baserole($setup, 't');
			$role = shift @$substitutes if $substitutes && @$substitutes;

			# Don't substitute to mason/sibling
			$role = setup_baserole($setup, 't') if $role_config{$role}{minrole};
		}

		# Disable nonsane cops and confused JATs for nobastard
		if (setup_rule('nobastard', $setup) && role_name($role, 0) ne role_name($role, 1))
		{
			$role = setup_baserole($setup, 't');
			$role = shift @$substitutes if $substitutes && @$substitutes;

			# Don't substitute to mason/sibling
			$role = setup_baserole($setup, 't') if $role_config{$role}{minrole};
		}

		my $new_count_role = count_role_as($role);

		$role_count->{$team}{$new_count_role} = 0 if !defined($role_count->{$team}{$new_count_role});

		# Convert (3rd)
		if ($role ne $orig_role)
		{
			::bot_log "PRECONVERT${pass}-COUNT $orig_role ($team $count_role) [$role_count->{$team}{$count_role}] to $role [$role_count->{$team}{$new_count_role}]\n" if $show_convert;
			$role_count->{$team}{$count_role}--;
			$role_count->{$team}{"=$orig_role"}--;
			$role_count->{'*'}{$count_role}--;
			$role_count->{'*'}{"=$orig_role"}--;
			$count_role = count_role_as($role);
			$role_count->{$team}{$count_role}++;
			$role_count->{$team}{"=$role"}++;
			$role_count->{'*'}{$count_role}++;
			$role_count->{'*'}{"=$role"}++;
			$orig_role = $role;
		}
		else
		{
			last;
		}
	}

	my $minmason = 2;
	$minmason *= setup_rule('maxchoices', $setup) if setup_rule('maxchoices', $setup);
	
	# Try hard to pair masons/siblings
	foreach my $mason (qw[mas1 mas2 sib theme_cosmic_symbiote gunfighter150polaritywave])
	{
		if ($role_count->{$team}{"=$mason"} && $role_count->{$team}{"=$mason"} < $minmason)
		{
			$role = $mason;
		}
	}
	if ($team eq 'mafia' && $role_count->{'*'}{"=sib2"} && $role_count->{'*'}{sib} < $minmason)
	{
		$role = 'sib2';
	}

	# Convert (4th)
	if ($role ne $orig_role)
	{
		$role_count->{$team}{$count_role}--;
		$role_count->{$team}{"=$orig_role"}--;
		$role_count->{'*'}{$count_role}--;
		$role_count->{'*'}{"=$orig_role"}--;
		$count_role = count_role_as($role);
		$role_count->{$team}{$count_role}++;
		$role_count->{$team}{"=$role"}++;
		$role_count->{'*'}{$count_role}++;
		$role_count->{'*'}{"=$role"}++;
		::bot_log "PRECONVERT${pass}-MASON $orig_role ($team) to $role\n" if $show_convert;
		$orig_role = $role;
	}

	# Magic setup checks
	if ($role_config{$role}{setup_checks})
	{
		check: foreach my $check (@{$role_config{$role}{setup_checks}})
		{
			my ($newrole, @kvpairs) = split /,/, $check;
			
			while (@kvpairs)
			{
				my $key = shift @kvpairs;
				my $value = shift @kvpairs;
				
				if ($key =~ /^minact(.*)$/)
				{
					next check if ($action_count->{$1} || 0) >= $value;
				}
				if ($key =~ /^minrole(.*)$/)
				{
					next check if ($role_count->{$team}{"=$1"} || 0) >= $value;
				}
				if ($key =~ /^minkill$/)
				{
					next check if $regkills >= $value;
				}
				if ($key =~ /^minteam(.*)$/)
				{
					next check if ($team_count{$1} || 0) >= $value;
				}
				if ($key =~ /^team$/)
				{
					next check if $team =~ /^$value/;
				}
				if ($key =~ /^maxplayers$/)
				{
					next check if $numplayers <= $value;
				}
				if ($key =~ /^minplayers$/)
				{
					next check if $numplayers >= $value;
				}
				if ($key =~ /^unique$/)
				{
					next check if ($role_count->{$team}{"=$role"} || 0) <= $value;
				}
				if ($key =~ /^maxpart(.*)$/)
				{
					my $key = $1;
					my $count = 0;
					foreach my $rolekey (keys %{$role_count->{'*'}}) {
						$count += $role_count->{'*'}{$rolekey} if $rolekey =~ /^=/ && $rolekey =~ /$key/;
						# ::bot_log("COUNTING $role_count->{'*'}{$rolekey} $rolekey ($key)\n") if $rolekey =~ /^=/ && $rolekey =~ /$key/;
					}
					next check if $count <= $value;
				}
			}

			if ($newrole =~ /^(.*)=(.*)$/) {
				my $old = $1;
				my $new = $2;
				$newrole = $role;
				$newrole =~ s/$old/$new/;
			}
			
			$role = $newrole;
			last;
		}
	}
	
	# Convert (5th)
	if ($role ne $orig_role)
	{
		$role_count->{$team}{$count_role}--;
		$role_count->{$team}{"=$orig_role"}--;
		$role_count->{'*'}{$count_role}--;
		$role_count->{'*'}{"=$orig_role"}--;
		$count_role = count_role_as($role);
		$role_count->{$team}{$count_role}++;
		$role_count->{$team}{"=$role"}++;
		$role_count->{'*'}{$count_role}++;
		$role_count->{'*'}{"=$role"}++;
		::bot_log "PRECONVERT${pass}-CHECK $orig_role ($team) to $role\n" if $show_convert;
		$orig_role = $role;
	}

	return $role;
}

sub estimated_kill_ratio {
	my ($num) = @_;
	my %num = %$num;
	my $numplayers = $num{town} + $num{mafia} + $num{mafia2} + $num{wolf} + $num{cult} + $num{sk} + $num{survivor};
	
	return 1 if $num{town} == 0;

	# Number of townies recruited each night (a recruit is about twice as bad as a kill)
	my $recruittown = $num{cult} * ($num{town} / ($numplayers - 1)) * 2;
	
	# With a cult, mafia kills are more likely to hit the cult
	my $recruitadj = $num{cult} * $num{town} / 4;
	
	# Number of town/scum killed by SKs each night
	# Bad townies are counted twice
	my $skkilltown = ($num{town} + $num{survivor} + $num{townbad} - $recruitadj) / ($numplayers - 1) * $num{sk};
	my $skkillscum = $num{sk} - $skkilltown;
	
	# Number of town/scum killed by mafia each night
	my $mafiakilltown = 0;
	my $mafiakillscum = 0;
	foreach my $team (qw[mafia mafia2 wolf])
	{
		if ($num{$team} > 0)
		{
			# Bad townies are counted twice
			my $killtown = ($num{town} + $num{survivor} + $num{townbad} - $recruitadj) / ($numplayers - $num{$team});
			$mafiakilltown += $killtown;
			$mafiakillscum += 1 - $killtown;
		}
	}
	
	my $nightkilltown = $mafiakilltown + $skkilltown;
	my $nightkillscum = $mafiakillscum + $skkillscum;
	
	my $dayratio = ($num{town} + $num{survivor} - $nightkilltown) / ($numplayers - $nightkilltown - $nightkillscum);
	
	# Fraction of lynches which hit scum (counting after the first night's kill)
	my $maxlynchbias = 0.45 + $numplayers / 100;
	my $lynchbias = ($dayratio <= 0.5 ? 0 : ($dayratio > 0.6 ? $maxlynchbias : $maxlynchbias * ($dayratio - 0.5) / (0.6 - 0.5)));
	my $rightlynches = ($num{mafia} + $num{mafia2} + $num{wolf} + $num{cult} + $num{sk} - $nightkillscum) / ($numplayers - $nightkillscum - $nightkilltown) * (1 - $lynchbias) + $lynchbias;

	# Number of town/scum lynched each day
	my $lynchkilltown = 1 - $rightlynches;
	my $lynchkillscum = $rightlynches;
	
	# Total number of town/scum killed each day+night cycle
	my $totalkilltown = $skkilltown + $mafiakilltown + $lynchkilltown + $recruittown;
	my $totalkillscum = $skkillscum + $mafiakillscum + $lynchkillscum;
	
	# Fraction of kills which are town
	return $totalkilltown / ($totalkilltown + $totalkillscum);
}

sub filter_roles {
	my ($setup, $rolelist, $numplayers, $num, $team_name) = @_;

	if (!@$rolelist) {
		::bot_log "Empty role list for $team_name??\n";
	}
	return @{$rolelist}[1 .. $#$rolelist] if $rolelist->[0] eq '*filtered*';

	my $nolimits = setup_rule('nolimits', $setup);

	my @rolechoices;
	foreach my $role (@$rolelist)
	{
		my $shortrole;
		($shortrole = $role) =~ s!/.*$!!;

		next if $role =~ /-ally/ && $num->{mafia} == 0;
		next if $role =~ /-ally/ && $num->{town} < $numplayers / 2 + 2;

		next if $nolimits && ($role_config{$shortrole}{minrole} || 0) > 1;
		next if setup_rule('maxchoices', $setup) && ($role_config{$shortrole}{minrole} || 0) > 1;

		unless ($nolimits)
		{
			next if ($role_config{$shortrole}{minplayers} || 0) > $numplayers;
			next if ($role_config{$shortrole}{minmafia}   || 0) > $num->{mafia};
			next if ($role_config{$shortrole}{mincult}    || 0) > $num->{cult};
			next if ($role_config{$shortrole}{minsk}      || 0) > $num->{sk};
			next if ($role_config{$shortrole}{minscum}    || 0) > $num->{mafia} + $num->{sk};
		}

		next if setup_rule('nobastard', $setup) && role_name($shortrole, 0) ne role_name($shortrole, 1);

		push @rolechoices, $role;
	}

	@$rolelist = ("*filtered*", @rolechoices);

	return @rolechoices;
}

