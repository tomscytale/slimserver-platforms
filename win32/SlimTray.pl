# $Id$
# 
# SlimTray.exe controls the starting & stopping of the slimsvc Windows Service.
#
# If the service is not installed, we'll install it first.
#
# This program relies on Win32::Daemon, which is not part of CPAN.
# http://www.roth.net/perl/Daemon/
#
# The user can choose to run SlimServer as a service, or as an application.
# Running as an application will allow access to mapped network drives.
#
# The checkbox selection will be:
# 'at system start' (service) or 'at login' (app). 
# 
# If the user chooses app - the service will still be installed, but set to
# Manual start.

use strict;
use PerlTray;

use Cwd qw(cwd);
use File::Spec;
use Getopt::Long;
use LWP::Simple;
use Win32;
use Win32::Daemon;
use Win32::Process qw(DETACHED_PROCESS CREATE_NO_WINDOW NORMAL_PRIORITY_CLASS);
use Win32::Process::List;
use Win32::TieRegistry ('Delimiter' => '/');
use Win32::Service;

my $timerSecs   = 10;
my $ssActive    = 0;
my $starting    = 0;
my $processObj  = 0;
my $checkHTTP   = 0;

# Passed on the command line by Getopt::Long
my $cliStart    = 0;
my $cliExit     = 0;

my $registryKey = 'CUser/Software/SlimDevices/SlimServer';

my $serviceName = 'slimsvc';
my $appExe      = File::Spec->catdir(baseDir(), 'server', 'slim.exe');

my $errString   = 'SlimServer Failed. Please see the Event Viewer & Contact Support';

# Dynamically create the popup menu based on Slimserver state
sub PopupMenu {
	my @menu = ();

	if ($ssActive) {
		push @menu, ["*Open SlimServer", "Execute 'SlimServer Web Interface.url'"];
		push @menu, ["--------"];
		push @menu, ["Stop SlimServer", \&stopSlimServer];
	}
	elsif ($starting) {
		push @menu, ["Starting SlimServer...", ""];
	}
	else {
		push @menu, ["*Start SlimServer", \&startSlimServer];
	}

	my $serviceString = 'Automatically run at system start';
	my $appString     = 'Automatically run at login';

	# We can't modify the service while it's running
	# So show a grayed out menu.
	my $setManual = undef;
	my $setAuto   = undef;
	my $setLogin  = undef;

	if (!$ssActive && !$starting) {

		$setManual = sub { setStartupType('none') };
		$setAuto   = sub { setStartupType('auto') };
		$setLogin  = sub { setStartupType('login') };
	}

	# Startup can be in one of three states: At boot (service), at login
	# (app), or Off, which leaves the service installed in a manual state. 
	my $type = startupType();

	if ($type eq 'login') {

		push @menu, ["_ $serviceString", $setAuto, undef];
		push @menu, ["v $appString", $setManual, 1];

	} elsif ($type eq 'auto') {

		push @menu, ["v $serviceString", $setManual, 1];
		push @menu, ["_ $appString", $setLogin, undef];

	} else {

		push @menu, ["_ $serviceString", $setAuto, undef];
		push @menu, ["_ $appString", $setLogin, undef];
	}

	push @menu, ["--------"];
	push @menu, ["Go to Slim Devices Web Site", "Execute 'http://www.slimdevices.com'"];
	push @menu, ["E&xit", "exit"];
	
	return \@menu;
}

# Called when the tray application is invoked again. This can handle
# new startup parameters.
sub Singleton {

	# Had problems using Getopt::Long since @ARGV isn't set.
	# XXX There also seems to be a problem with arguments passed
	# in. $_[0] is not the first parameter, so we use $_[1].
	if (scalar(@_) > 1) {
		if ($_[1] eq '--start') {
			startSlimServer();
		}
		elsif ($_[1] eq '--exit') {
			exit;
		}
	}
}

# Display tooltip based on SS state
sub ToolTip {

	if ($starting) {
		return "SlimServer Starting";
	}

	if ($ssActive) {
		return "SlimServer Running";
	}
   
	return "SlimServer Stopped";
}

# The regular (heartbeat) timer that checks the state of SlimServer
# and modifies state variables.
sub Timer {
	my $wasStarting = $starting;

	checkSSActive();

	if ($starting) {

		SetAnimation($timerSecs * 1000, 1000, "SlimServer", "SlimServerOff");

	} elsif ($wasStarting && $ssActive && startupType() ne 'login') {

		# If we were waiting for SS to start before this check, show the SS home page.
		if (checkForHTTP()) {

			Execute("SlimServer Web Interface.url");

		} else {

			$checkHTTP = 1;
		}

	} elsif ($checkHTTP && checkForHTTP()) {

		$checkHTTP = 0;

		Execute("SlimServer Web Interface.url");
	}
}

# The one-time startup timer, since there are things we can't do
# at Perl initialization.
sub checkAndStart {

	# Kill the timer, we only want to run once.
	SetTimer(0, \&checkAndStart);

	if ($cliExit) {
		exit;
	}

	# Install the service if it isn't already.
	my %status = ();

	Win32::Service::GetStatus('', $serviceName, \%status);

	if (scalar keys %status == 0) {

		installService();
	}

	# Add paths if they don't exist.
	my $startupType = startupType();

	if ($startupType eq 'none') {

		my $cKey = $Registry->{'CUser/Software/'};
		my $lKey = $Registry->{'LMachine/Software/'};

		$cKey->{'SlimDevices/'} = {
			'SlimServer/' => {
				'/StartAtBoot'  => 0,
				'/StartAtLogin' => 0,
			},
		};

		$lKey->{'SlimDevices/'} = { 'SlimServer/' => { '/Path' => baseDir() } };
	}

	# If we're set to Start at Login, do it, but only if the process isn't
	# already running.
	if (processID() == -1 && $startupType eq 'login') {

		startSlimServer();
	}

	# Now see if the service happens to be up already.
	checkSSActive();

	if ($ssActive) {

		SetIcon("SlimServer");

	} else {

		SetIcon("SlimServerOff");
	}

	# Handle the command line --start flag.
	if ($cliStart) {

		if (!$ssActive) {

			startSlimServer();

		} else {

			# Don't launch the browser if we start at login time.
			Execute("SlimServer Web Interface.url");
		}

		$cliStart = 0;
	}
}

sub checkSSActive {
	my $state = 'stopped';

	if (startupTypeIsService()) {

		my %status = ();

		Win32::Service::GetStatus('', $serviceName, \%status);

		if ($status{'CurrentState'} == 0x04) {

			$state = 'running';
		}

	} else {

		if (processID() != -1) {

			$state = 'running';
		}
	}

	if ($state eq 'running') {

		SetIcon("SlimServer");
		$ssActive = 1;
		$starting = 0;

	} else {

		SetIcon("SlimServerOff");
		$ssActive = 0;
	}
}

sub startSlimServer {

	if (startupTypeIsService()) {

		if (!Win32::Service::StartService('', $serviceName)) {

			showErrorMessage("Starting $errString");

			$starting = 0;
			$ssActive = 0;

			return;
		}

	} else {

		runBackground($appExe);
	}

	if (!$ssActive) {

		Balloon("Starting SlimServer...", "SlimServer", "", 1);
		SetAnimation($timerSecs * 1000, 1000, "SlimServer", "SlimServerOff");

		$starting = 1;
	}
}

sub stopSlimServer {

	if (startupTypeIsService()) {

		if (!Win32::Service::StopService('', $serviceName)) {

			showErrorMessage("Stopping $errString");

			return;
		}

	} else {

		my $pid = processID();

		if ($pid == -1) {

			showErrorMessage("Stopping $errString");

			return;
		}

		Win32::Process::KillProcess($pid, 1<<8);
	}

	if ($ssActive) {

		Balloon("Stopping SlimServer...", "SlimServer", "", 1);

		$ssActive = 0;
	}
}

sub showErrorMessage {
	my $message = shift;

	MessageBox($message, "SlimServer", MB_OK | MB_ICONERROR);
}

sub startupTypeIsService {

	my $type = startupType();

	# These are the service types.
	if ($type eq 'auto' || $type eq 'manual') {

		return 1;
	}

	return 0;
}

# Determine how the user wants to start SlimServer
sub startupType {

	my $atBoot  = $Registry->{"$registryKey/StartAtBoot"};
	my $atLogin = $Registry->{"$registryKey/StartAtLogin"};

	if ($atLogin) {
		return 'login';
	}

	if ($atBoot) {

		my $serviceStart = $Registry->{"LMachine/SYSTEM/CurrentControlSet/Services/$serviceName/Start"};

		if ($serviceStart) {

			# Start of 2 is auto, 3 is manual.
			return oct($serviceStart) == 2 ? 'auto' : 'manual';
		}
	}

	return 'none';
}

sub setStartupType {
	my $type = shift;

	if ($type !~ /^(?:login|auto|manual|none)$/) {

		return;
	}

	if ($type eq 'login') {

		$Registry->{"$registryKey/StartAtBoot"}  = 0;
		$Registry->{"$registryKey/StartAtLogin"} = 1;

		# Force the service to manual start, don't remove it.
		setServiceManual();

	} elsif ($type eq 'none') {

		$Registry->{"$registryKey/StartAtBoot"}  = 0;
		$Registry->{"$registryKey/StartAtLogin"} = 0;

		setServiceManual();

	} else {

		$Registry->{"$registryKey/StartAtBoot"}  = 1;
		$Registry->{"$registryKey/StartAtLogin"} = 0;

		if ($type eq 'auto') {

			setServiceAuto();

		} else {

			setServiceManual();
		}
	}
}

# Return the SlimServer install directory.
sub baseDir {

	# Try and find it in the registry.
	# This is a system-wide registry key.
	my $swKey = $Registry->{"LMachine/Software/SlimDevices/SlimServer/Path"};

	if (defined $swKey) {
		return $swKey;
	}

	# Otherwise look in the standard location.
	my $baseDir = File::Spec->catdir('C:\Program Files', 'SlimServer');

	# If it's not there, use the current working directory.
	if (!-d $baseDir) {

		$baseDir = cwd();
	}

	return $baseDir;
}

sub checkForHTTP {

	my $prefFile = File::Spec->catdir(baseDir(), 'server', 'slimserver.pref');
	my $httpPort = 9000;

	# Quick and dirty finding of the httpport. Faster than loading YAML.
	if (-r $prefFile) {

		if (open(PREF, $prefFile)) {

			while (<PREF>) {
				if (/^httpport: (\d+)$/) {
					$httpPort = $1;
					last;
				}
			}

			close(PREF);
		}
	}

	my $content = get("http://localhost:$httpPort/EN/html/ping.html");

	if ($content && $content =~ /alive/) {

		return $httpPort;
	}

	return 0;
}

sub setServiceAuto {

	_configureService(SERVICE_AUTO_START);
}

sub setServiceManual {

	_configureService(SERVICE_DEMAND_START);
}

sub _configureService {
	my $type = shift;

	Win32::Daemon::ConfigureService({
		'machine'     => '',
		'name'        => $serviceName,
		'start_type'  => $type,
	});
}

sub installService {
	my $type = shift || SERVICE_DEMAND_START;

	Win32::Daemon::CreateService({
		'machine'     => '',
		'name'        => $serviceName,
		'display'     => 'SlimServer',
		'description' => "Slim Devices' SlimServer Music Server",
		'path'        => $appExe,
		'start_type'  => $type,
	});
}

sub runBackground {
	my @args = @_;

	$args[0] = Win32::GetShortPathName($args[0]);

	Win32::Process::Create(
		$processObj,
		$args[0],
		"@args",
		0,
		DETACHED_PROCESS | CREATE_NO_WINDOW | NORMAL_PRIORITY_CLASS,
		'.'
	);
}

sub processID {

	my $p   = Win32::Process::List->new;
	my $pid = ($p->GetProcessPid(qr/^slim\.exe$/))[0];

	return $pid;
}

*PerlTray::ToolTip = \&ToolTip;

GetOptions(
	'start' => \$cliStart,
	'exit'  => \$cliExit,
);

# Checking for existence & launching of SS in a timer, since it
# fails if done during Perl initialization.
SetTimer(":1", \&checkAndStart);

# This is our regular timer which continually checks for existence of
# SS. We could have combined the two timers, but changing the
# frequency of the timer proved problematic.
SetTimer(":" . $timerSecs);

__END__
