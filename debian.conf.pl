#!/usr/bin/perl

# Debian server configurator perl script
# ------------------------------------
#
# Copyright (C) 2014 Tom Seymour <thmshly@remail.pw>
# 
# This program is licensed under the MIT License.
#
# The full license can be viewed at: 
# https://github.com/thmshly/server-config/MIT-LICENSE.txt
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

use warnings;
use strict;

# For some reason this doesn't work as Getopt::Long::Configure(); - Configure can't be found in @INC (at least on the two machines I've tried)
# Exporting the function as below works.
use Getopt::Long qw(GetOptions Configure);
Configure("Bundling");

my ($configure, 
	$all,
	$without,
	$users, 
	$groups,
	$shell,
	$dir,
	$home,
	$custm,
	$services, 
	$perms, 
	$aptSrc, 
	$backports,
	$ssh,
	$port,
	$dots,
	$git, 
	$nginx, 
	$install,
	$packages, 
	$splmntPkg, 
	$toInstall,
	);

my $name = ' ';				# To stop 'uninit value' warning
my $debug = 0;
my $simulate = 0; 			# If enabled (1), don't run any commands. controlled by option `--simulate|sim!`
my $prompt = 1;				# If enabled (1), prompt user before continuing with each action
my $sep = ' '; 				# List separator. Currently used to split option lists
my $updatesCount = 0;		# To make sure apt-get update/upgrade is only run once. May be set in $defaultPkgs as well as a through --install.
my $db = "";				# Opening debug variable, used in system calls. Set to "echo '" when $simulate is on.
my $dbe = "";				# Closing debug variable. Set to "'" when in $simulate.
my $defaultDir;

# Default packages to install: space separated list. Order respected, except updates, which is ALWAYS DONE FIRST. What if there's a package called updates?
my $defaultPkgs = "sudo etckeeper links vim vrms updates";

# Default services to disable: space separated list. Order respected, if it matters.
my $defaultSrvcs = "sendmail apache2 mysql bind9 cups";

# Default user shell
my $defaultShell = "/bin/bash";

# Default groups for user: comma separated list. Again, order respected. All will be put through groupadd;
my $defaultGrps = "sudo,admin,other,testing";

# Default home directory for user. Also set in &users(). This is a BUG. Set it after Getoptions? Doesn't work.
$defaultDir = "/home/$name";

# String that identifies a keyserver entry in %sources hash. Not really important, so long as it starts with a character that can't be in a package
# name (or maybe just contain said character?)
my $kySrvString = "!keyserver";

# Package repositories to add to /etc/apt/sources.list.d/
# Can also contain a package keyserver path and fingerprint to pass to apt-key adv:
# Use the form: "pkgName".$kySrvString => "keyserver.example.com 0xSomeFingerprint"
my %sources = (
	# Specify the right source for your version of debian.
	"backports"				=> "deb http://ftp.debian.org/debian wheezy-backports main", 
	"mariadb"				=> "deb http://mirror.netcologne.de/mariadb/repo/5.5/debian wheezy main",
	"mariadb".$kySrvString	=> "keyserver.ubuntu.com 0xcbcb082a1bb943db",
);

# Sources to remove with 'make_free' keyword for --repos
my $unfree = "non-free contrib"; 

# Packages that require backports. Need to be installed with "apt-get -t wheezy-backports install $package_name", or similar.
my @backports = ("trac");

# Command to use in `apt-get install` to install from backports: see previous comment.
my $backportsCmd = "-t wheezy-backports";

# Base url path to dotfiles (to save writing it out several times)
my $dotRepoPath = "https://raw.github.com/thmshly/server-config/master/dotfiles/";

# Url locations of dotfiles to be downloaded with --dots|o. Currently there's no way to make exclusions, or download directories? e.g. ~/.conf/...
my %dotfiles = (
	".bashrc" 		=> $dotRepoPath.".bashrc",
	".screenrc"		=> $dotRepoPath.".screenrc",
	".vimrc" 		=> $dotRepoPath.".vimrc",
	".inputrc" 		=> $dotRepoPath.".inputrc"
);

GetOptions("configure" => \$configure,		# On or off. Configure things. If off, all subsets of configure are ignored
    	   "all" => \$all, 					# !Not Implemented! Configure all: not literally all (only $users $services $permissions and $aptSrc)
    	   "without" => \$without, 			# !Not Implemented! Without a specific element: will negate something from $all. 
    	   "services|s" => \$services, 		# Disable services. Prompts user to supply or append to a list of services (defaults: $defaultSrvcs).
    	   "users|u" => \$users,			# Create a user. Takes $name, $groups, $shell, $dir, and $custm. None required: prompts for any omitted.
		   "name|n=s" => \$name,			# Name for user
		   "groups|g=s" => \$groups,		# User's groups, to create before creating user
		   "shell|sh=s" => \$shell,			# User's shell
		   "dir|d=s" => \$dir,				# User's home directory
		   "custm|c" => \$custm,			# Prompts for custom arguments to pass to `useradd`. 
		   "permissions|p" => \$perms,		# !Not Implemented! Change permissions for files like /bin/su, /var/logs/* and /etc/*
		   #"apt=s" => \$aptSrc,			# String of options to configure apt: s - /etc/sources, uy - update && upgrade
		   "repos=s" => \$aptSrc,			# List of repositories to add to /etc/apt/sources.list.d/. Keyword: `make_free` -> $unfree
		   "ssh=s" => \$ssh,				# !Not Implemented! SSH. $port number.
		   "git" => \$git,					# !Not Implemented! Set username and email for commits
		   "install=s" => \$packages,		# Installs specified packages, updates and sources with apt-get. Keywords: `defaults` and `updates`
		   #"packages|pkg=s" => \$packages,	# A string of packages to install. Specifying `defaults` installs packages listed in $defaultPkgs
		   "supplement=s" => \$splmntPkg,	# Deprecated. A string of packages to install in addition to the defaults $defaultPkgs
		   "dots|o=s" => \$dots,			# Downloads and places dotfiles in home directory of user specified as string. /root possible.
		   "debug|bug!" => \$debug,		# Boolean. Prints all system commands to STDOUT and runs them (unless $simulate).
		   "simulate|sim!" => \$simulate,	# Boolean. Prints all system commands to STDOUT, does not run them.
		   "prompt!" => \$prompt,			# Boolean. Prompts the user for confirmation before continuing with each action.
) or die("Error in command line arguments $!\n");


if($simulate){
	print "This is a simulation, system commands will be echod as strings to STDOUT.\n";
	$db = "echo '  ";
	$dbe = "'";
}

if($configure){
	if(defined($all)){
			$services=1;$users=1;$perms=1;$aptSrc=1;
	}
	if(defined($without)){
		&without();						
	}
	if($services){
		print "Configuring services.. "; 
		&services();
	}
	if($users){
		print "Configuring users..\n"; 
		&users();
	}
	if($perms){
		print "Configuring permissions..\n"; 
		&permissions();
	}
	if($dots){
		print "Configuring dotfiles..\n"; 
		&dotfiles();
	}
	if($port){
		print "Configuring ssh..\n"; 
		&ssh();
	}
	if($nginx){
		print "Configuring nginx..\n"; 
		&nginx();
	}
	if($git){
		print "Configuring git..\n"; 
		&git();
	}
}

# A wrapper for system() with some extra features!
sub sys {
	my ($cmd,$noSudo,$dontPrompt) = @_;

	#! TODO: implement prompting	
	
	# If not root, use sudo unless $noSudo
	if($< && !$noSudo){

		# print out the command whether in debug or simulate
		print "   sudo $cmd\n" if $debug or $simulate;

		# print debug info if $debug
		print caller(2),"\n" if $debug;

		# Execute the command only when NOT in simulate
		system("sudo $cmd") unless $simulate;	
		
	# Else just run the commands as current user
	} else {

		# print out the command whether in debug or simulate
		print "   $cmd\n" if $debug or $simulate;

		# print debug info if $debug
		print caller(2),"\n" if $debug;

		# Execute the command only when NOT in simulate
		system($db."$cmd".$dbe) unless $simulate;	
	}
	# Test..
	&sys("echo 'This should work. String to test. etc, etc.'",1,0);

}

if(defined($packages)){
	# Edit sources first if requested
	&apt("sources") if defined($aptSrc);

	# Keywords `updates` and `defaults`:
	# Update package list and upgrade system packages. Remove keyword from $packages string if updates were requested
	&apt("updates") && $packages =~ s/( |^)updates( |$)//g if $packages =~ /( |^)updates( |$)/;

	# Install defaults and remove keyword 'defaults' from $packages string (pointless with this regex..?) if defaults were requested.
	&apt("defaults") && $packages =~ s/^defaults$// if $packages =~ /^defaults$/; 
	
	# Add $defaultPkgs to $toInstall if defaults keyword given. There should be other packages, hence longer regex.
	$toInstall = $defaultPkgs if $packages =~ /( )defaults( |$)|( |^)defaults( )/;

	# Make hash out of @backports array in order to type less.
	my %bckprts = map { $_ => 1 } @backports;

	# Iterate items in $packages string spilt by the separator $sep
	foreach(split($sep,$packages)){

		# If item is in %backports hash
		if( exists($bckprts{$_})){
			print "Package $_ requires backports repository.. \n";		
			# Install package (singular: subsequent execs of apt-get possible) from backports
			&apt("backports",$_);
			# Advance one iteration in loop: don't add package to $toInstall (it's just been installed!)
			next;

		# If item is in %sources hash, and by definition requires sources to be added
		} elsif(exists($sources{$_})) {
			print "Found $_ in \%sources hash.. ";
			
			# Add package keys from keyserver if defined by $packageName.$kySrvString in %sources hash
			if(exists($sources{$_.$kySrvString})){
				print "and it needs special keyserver treatment!\n";	
				&apt("keyserver",$sources{$_.$kySrvString});
			}			
			
			# Add sources to /etc/sources.list.d/$_.list
			$aptSrc = "$_";
			&apt("sources");

		} 
		
		# Append package name onto $toInstall
		$toInstall .= " $_" unless $_ eq "defaults"|| $_ eq "updates";
	}
	
	# Install packages in $toInstall
	&apt("install",$toInstall) unless !$toInstall;

} elsif($aptSrc){
		print "Configuring apt sources..\n"; 
		&apt("sources");
}

sub without {

}

sub services {
	print "Here's what's running: \n";
	system("$db sudo lsof -i $dbe");
	print "Enter the services to disable [defaults: $defaultSrvcs. Use '+ <services>' to add to this list]: \n";
	my $srvcList = <STDIN>;	chomp($srvcList);
	$srvcList = &parseDefaults($defaultSrvcs,$srvcList);

	if($srvcList eq ''){
		print "Recieved !, skipping service config\n";	
		return 0;
	}
	
	foreach(split($sep,$srvcList)){
		print "Disabling: $_\n";
		system("$db service $_ stop; insserv -r $_ $dbe") unless $simulate;
		print "service $_ stop\ninsserv -r $_\n" if $simulate;
	} 
}

sub users {
	if($name eq " "){ # Set to space to stop the warning of uninit value in default decl $defaultDir
		print "Enter a name for the user: \n";
		$name = <STDIN>; chomp($name);
		$defaultDir = "/home/$name";
	}
	if(!defined($groups)){
		print "Please enter a list of groups for user '$name' [default: $defaultGrps]: \n";
		$groups = <STDIN>; chomp($groups);
		$groups = &parseDefaults($defaultGrps,$groups);
	} else {
		if ($groups eq "defaults"){
			$groups = $defaultGrps;		
		}	
	}
	&createGroups($groups) if $groups;

	if(!defined($shell)){
		print "Please enter the login shell for user '$name' [default: $defaultShell]: \n";
		$shell = <STDIN>; chomp($shell);
		$shell = &parseDefaults($defaultShell,$shell);
	}
	if(!defined($dir)){
		print "Please enter a path for the user's home directory [default: $defaultDir]: \n";
		$dir = <STDIN>; chomp($dir);
		$dir = &parseDefaults($defaultDir,$dir);
	}
	if(defined($custm)){
		print "Enter your custom arguments to pass to `useradd`: \n";
		$custm = <STDIN>; chomp($custm);
	}

	# Prepend switches here, so that useradd works when vars are empty
	$groups = "-G ".$groups if $groups;
	$shell = "-s ".$shell if $shell;
	$dir = "-d ".$dir if $dir;
	print "User $name will be created with groups '$groups', shell '$shell', in directory '$dir' ";
	print "and custom args '$custm'" if $custm; print ".\n";
	# Create the user account
	system("$db useradd -m $groups $shell $dir $custm $name $dbe");
	# Set a password for the user
	system("$db passwd $name $dbe");
	# Set expiry data for password
	system "$db passwd -w 5 -x 32 -n 5 $name $dbe";
1;}

sub createGroups {
	my $grpList = shift;
	print "Creating groups..\n";
	# Split groups list by comma
	foreach(split(',',$grpList)){
		print "$_..\n ";
		# Create the group
		system("$db groupadd $_ $dbe");	
	}
	print "\n";
1;}

sub parseDefaults {
	my ($default,$usrIn) = @_;
	if(!$usrIn){
		# If user input is empty, use defaults
		print "Using defaults: $default\n";
		$usrIn = $default;
	} else {
		if($usrIn =~ /^(\+ ).+/){
			# If user input begins with '+ ', prepend defaults to user input
			print "Using the defaults '$default', $usrIn..\n";
			$usrIn =~ s/^(\+)/$default/g;
		} elsif($usrIn =~ /^\!$/){
			# If user input is '!', return empty string
			$usrIn = '';	
		}
	} 
	return $usrIn;
}

sub permissions {
}

sub apt {
	my $mode = shift;
	my $aptSrcDir = "/etc/apt/sources.list.d";
	if($mode eq "updates" && $updatesCount==0){
		print "Updating sources and upgrading installed packages with apt-get..\n";	
		system "$db apt-get update && apt-get upgrade $dbe";
		$updatesCount = 1;
		print "You should reboot your system as soon as you can.\n";
		return 1;

	} elsif($mode eq "sources"){
		
		if($aptSrc =~ /( |^)make_free( |$)/){
			print "Removing '$unfree' repositories from apt..\n";
			# Install python-software-properties
			print "Installing python-software-properties for use of 'add-apt-repository'..\n";
			system("$db apt-get install python-software-properties$dbe");
			# Remove non-free and contrib sources
			system("$db add-apt-repository --remove $unfree$dbe");
			# Remove "make_free" from $aptSrc string
			$aptSrc =~ s/( |^)make_free( |$)//g;
		}

		if($aptSrc){
			#system("$db vim /etc/apt/sources.list $dbe");
			foreach(split($sep,$aptSrc)){
				if(exists($sources{$_})){
					print "Found repository for $_. Creating $aptSrcDir/$_.list..\n";
					system("$db echo $sources{$_} >> $aptSrcDir/$_.list$dbe");	
					$backports = 1 if $_ eq "backports";
				} else {
					print "Maunally add repository for $_? (yes/no): \n";	
					my $answ = <STDIN>; chomp($answ);
					system($db."vim $aptSrcDir/$_.list".$dbe) if $answ =~ /^ ?yes ?$/;
				}
			}
		}
		# Update apt sources! Can't be done too often.. right?
		print "Updating apt sources..\n";
		system($db."apt-get update".$dbe);

	} elsif($mode eq "defaults"){
		print "Installing default packages: $defaultPkgs\n";
		&apt("updates") if $defaultPkgs =~ /( |^)updates( |$)/;
		system($db."apt-get install $defaultPkgs".$dbe);
		return 1;
		
	} elsif($mode eq "backports"){
		my $pkg = shift;
		# Configure sources for backports if not already done, i.e. if !$backports
		unless($backports){
			$aptSrc = "backports";
			&apt("sources");
		}
		print "Installing '$pkg' from $mode..\n";
		system($db."apt-get $backportsCmd install $pkg".$dbe);
		return 1;

	} elsif($mode eq "install"){
		my $pkgs = shift;	
		print "Installing $pkgs.. \n";
		# Install packages $pkgs- should not contain 'updates' or 'default' - currently this dies if either is found, but could instead strip them out? 
		# Later.
		system($db."apt-get install $pkgs".$dbe) unless $pkgs =~ /( |^)upflates( |$)|( |^)defaults( |$)/ && die("Keyword 'updates' or 'defaults' found in package list at 'apt-get install': review program code! $!");
		return 1;

	} elsif($mode eq "keyserver"){
		my $ks = shift;	
		print "Getting keys from $ks..\n";
		# Download keys from keyserver $ks
		system($db."apt-key adv --recv-keys --keyserver $ks".$dbe);
	}
}

sub dotfiles {
	# In future make sure $dots doesn't start with '-'
	my $path = "/home/$dots/";
	my $epoch = time();
	$path = '/root/' if $dots eq "root";
	print "Downloading files to $path..\n";
	for my $key ( keys %dotfiles ){
		print "$key..\n";
		system "$db cp -rp $path$key $path$key.orig$epoch $dbe";
		system "$db wget -P $path $dotfiles{$key} $dbe";
	}
}
sub ssh {
	
}
sub nginx {
}

sub git {
}
