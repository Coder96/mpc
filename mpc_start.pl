#!/usr/bin/perl 

# Includes
use File::Basename;
use Fcntl ':flock';

use constant { true => 1 , false => 0 };

#
# lets lock our self so only one instance of the program will run.
#
open SELF, '</opt/mpc/mpc_start.pl' or exit; 
flock SELF, LOCK_EX | LOCK_NB or exit;
#
# Global vars
#

my $configFile = 'mpc_config.txt';

my $youtubedlPath = '/opt/mpc/youtube-dl';
my $wgetPath = 'wget';

my $rsstailPath = 'rsstail';

my $workdir = '/opt/mpc';

my $cFeedsFile     = 'mpc_feeds.txt';
my $cOldFiles      = 'mpc_oldfiles.log';
my $cLastRun       = 'mpc_lastrun.log';
my $cDownloadFile  = 'mpc_download.log';
my $cWebConfig     = 'mpc_webconfig.php';
my $cSaveDir				=	'~/mpc';
my $debug = false;

my $justintvurl = '';  # yes this is bad. Global Var.

#
# Create Config file if it does not exesists.
#
unless(-e "$workdir/$cWebConfig"){
	CheckCreateFile($cWebConfig);
	
	open(CONFIG, ">>$workdir/$cWebConfig")or die $!;
	print CONFIG <<DONE
	\$DisplayUrlChars = 40;
DONE
}

unless(-e "$workdir/$configFile"){
	CheckCreateFile($configFile);
	
	open(CONFIG, ">>$workdir/$configFile")or die $!;
	print CONFIG <<DONE ;
	\$wgetPath = 'wget';
	\$rsstailPath = 'rsstail';
	\$debug = false;
	\$cFeedsFile     = 'mpc_feeds.txt';
	\$cOldFiles      = 'mpc_oldfiles.log';
	\$cOldFilestoAdd = 'mpc_oldfilestoadd.log';
	\$cLastRun       = 'mpc_lastrun.log';
	\$cDownloadFile  = 'mpc_download.log';
	\$cLastJobRun    = 'mpc_lastjobrun.log';
	\$cWebConfig     = 'mpc_webconfig.php';
	\$cSaveDir       = '~/mpc';
DONE
	
	close(CONFIG);
}

#
# Load config file options
#
open(CONFIG, "$workdir/$configFile");
@lines = <CONFIG>;
foreach $line (@lines){
	eval($line);
}
close(CONFIG);

#
# Create needed files
#
CheckCreateFile($cDownloadFile);
CheckCreateFile($cFeedsFile);
CheckCreateFile($cOldFiles);
CheckCreateFile($cOldFilestoAdd);
CheckCreateFile($cOldFiles);
CheckCreateFile($cLastRun);

open LOG, ">$workdir/$cLastRun" or die $!;

open FEEDS, "$workdir/$cFeedsFile" or die $!;
while (<FEEDS>)	{
	 s/#.*//;            # ignore comments by erasing them
	next if /^\s*$/; # ignore blank lines
	chomp;
	push @feeds, $_;
}
close(FEEDS);

open OLDFILES, "$workdir/$cOldFiles" or die $!;
while (<OLDFILES>){
	 s/#.*//;        # ignore comments by erasing them
	next if /^\s*$/; # ignore blank lines
	chomp;
	push @previouslyDownloaded, $_;
}
close(OLDFILES);

open OLDFILESADDTO, "$workdir/$cOldFilestoAdd" or die $!;
my @addtooldfile = <OLDFILESADDTO>;
close(OLDFILESADDTO);
EraseFile($cOldFilestoAdd);

open OLDFILES, ">>$workdir/$cOldFiles" or die $!;
foreach $filetoadd (@addtooldfile){
	chomp($filetoadd);
	writeOldFilesLog($filetoadd);
}

#
# Check if needed programs are installed.
#
@list = `$wgetPath --help`;
if ($? == -1) {
	writeLog("Missing program $wgetPath");
	writeLog("install from apt-get install wget");
	$fail = 'y';
}
@list = `$rsstailPath -help`;
if ($? == -1) {
	writeLog("Missing program $rsstailPath");
	writeLog("install from apt-get install rsstail");
	$fail = 'y';
}
if($fail eq 'y'){
	exit();
}

writeLog("Start:".rDateTime() );

FEED: foreach $feed (@feeds){
	
	my ($feedName, $feedUrl, $feedUser, $feedPass, $feedmisc, $DownloadType) = ' ';
	
	($feedName, $feedUrl, $feedUser, $feedPass, $feedmisc) = split("\t", $feed);
	
	writeLog("$feedName type:$DownloadType");

	$uniqueString = '---HopeThisIsUnique---';
	my $command = "$rsstailPath -u '$feedUrl' -lH1z -Z$uniqueString 2>&1";
	writeDebugLog("$command");
	my $rsstail = qx($command);
	if($rsstail =~ m/^Error/i){
		writeLog("Faild to retrive or bad xml. $feedName $feedUrl");
		next FEED;
	}
	@feedGroup = split(/$uniqueString/,$rsstail);
	ITEM: foreach $feedlines (@feedGroup){
		$feedlines = trim($feedlines);
		if($feedlines ne ''){
			@feedlines = split("\n",$feedlines);
			my ($fTitle, $fLink) ='';
			foreach $line (@feedlines){
				($mkey, $mvalue) = split(/: /,$line, 2 );
				if($line =~ m/Link:/){$fLink = $mvalue;}
			}
			# Skip item if we've already got it
			chomp($fLink);
			foreach my $item (@previouslyDownloaded){
				next ITEM if $fLink eq $item;
			}
			wgetdownload($fLink, $feedName);
		}
	}
}

writeLog("Stop:".rDateTime() );
close(LOG);
close(OLDFILES);

sub writeOldFilesLog($){
	my ($wlink) = @_;
	print(OLDFILES "$wlink\n");
}

sub writeLog($){
	my ($string) = @_;
	print(LOG "$string\n");      
}

sub writeDebugLog($){
	my ($string) = @_;
	if($debug){
		print(LOG "$string\n");      
	}
}

sub wgetdownload{
	my ($fLink, $feedName) = @_;
	
#	my ($suffix) = $fLink =~ /(\.[^.]+)$/;
#	my($fLocalFileName, $fDateTime, $fDate) = setupDates($ChannelId, $suffix);
		
	$fpos1 = index($fLink, '?');
	if($fpos1 > -1){
		$fLocalFileName = substr($fLink, 0, $fpos1);
	} else {
		$fLocalFileName = $fLink;
	}
	
	$fpos1 = rindex($fLocalFileName, '/');
	if($fpos1 > -1){
		$fLocalFileName = substr($fLocalFileName, ++$fpos1);
	}

	my $command = ("$wgetPath -v --output-document='$cSaveDir/$feedName/$fLocalFileName' --output-file=$workdir/$cDownloadFile '$fLink'");
	if(! -e "$cSaveDir/$feedName"){
	mkdir("$cSaveDir/$feedName");
	}
	writeDebugLog("$command");
	my $cLog = qx($command);
	$cLog = trim($cLog);
	open DLWF, "$workdir/$cDownloadFile" or die $!;
	$error = <DLWF>;
	close(DLWF); 
	if($error =~ m/ERROR 404: Not Found/i or
	   $error =~ m/unable to resolve host address/i){
		writeLog("404 otd $fLink");
		return false;
	}
	sleep(1);
	writeOldFilesLog($fLink);
	return true;
}

sub CheckCreateFile {
	my ($file) = @_;
	unless(-e "$workdir/$file"){
		system("touch $workdir/$file");
		system("chmod a+w $workdir/$file");
	}
}

sub setupDates{
	my ($iChannelId, $ifileExt) = @_;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $wDate = sprintf("%s-%02s-%02s",$year+1900,$mon+1,$mday);
	my $wLocalFileName = sprintf("%s_%s%02s%02s%02s%02s%02s00$ifileExt",$ChannelId,$year+1900,$mon+1,$mday,$hour,$min,$sec);
	my $wDateTime = sprintf("%s %02s:%02s:%02s",$wDate,$hour,$min,$sec);
	
	return($wLocalFileName,$wDateTime,$wDate);
}

sub rDateTime{
	my $fDateTime;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$fDateTime = sprintf("%s-%02s-%02s %02s:%02s:%02s",$year+1900,$mon+1,$mday,$hour,$min,$sec);  
	return $fDateTime;
}

sub EraseFile{
	my ($file) = @_;
	open FILE, ">$workdir/$file" or die $!;
	close(FILE);
}

# Perl trim function to remove whitespace from the start and end of the string
sub trim($){
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
# Left trim function to remove leading whitespace
sub ltrim($){
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim($){
	my $string = shift;
	$string =~ s/\s+$//;
	return $string;
}
