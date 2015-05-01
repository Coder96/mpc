#!/usr/bin/perl 

# Includes
use File::Basename;
use Fcntl ':flock';

use constant { true => 1 , false => 0 };

#
# lets lock our self so only one instance of the program will run.
#
open SELF, '</opt/mpc/mpc_start.pl' or die "Install in /opt/mpc/mpc_start.pl"; 
flock SELF, LOCK_EX | LOCK_NB or exit;
#
# Global vars
#

my $configFile = 'mpc_config.txt';

my $youtubedlPath = '/opt/mpc/youtube-dl';
my $wgetPath = 'wget';

my $rsstailPath = 'rsstail';
my $xmlstarletPath = 'xmlstarlet';
my $curlPath = 'curl';
my $ChannelId = '9999';
my $UrlIdentString = '[DownLoadURL]';

my $workdir = '/opt/mpc';
my $DowloadDir = '~/';

my $cFeedsFile     = 'mpc_feeds.txt';
my $cOldFiles      = 'mpc_oldfiles.log';
my $cOldFilestoAdd = 'mpc_oldfilestoadd.log';
my $cLastRun       = 'mpc_lastrun.log';
my $cDownloadFile  = 'mpc_download.log';
my $cOneTimeDL     = 'mpc_onetimedl.txt';
my $cLastJobRun    = 'mpc_lastjobrun.log';
my $cWebConfig     = 'mpc_webconfig.php';

my $MaxNumberofFeedItemsToDownload = 9999;
my $MaxNumberofCharsToUseofDescption = 80;

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
	\$youtubedlPath = '/opt/mpc/youtube-dl';
	\$wgetPath = 'wget';
	\$rsstailPath = 'rsstail';
	\$xmlstarletPath = 'xmlstarlet';
	\$curlPath = 'curl';
	\$ChannelId = '9999';
	\$DowloadDir = '/';
	\$MaxNumberofFeedItemsToDownload = 9999;
	\$MaxNumberofCharsToUseofDescption = 80;
	\$debug = false;
	\$cFeedsFile     = 'mpc_feeds.txt';
	\$cOldFiles      = 'mpc_oldfiles.log';
	\$cOldFilestoAdd = 'mpc_oldfilestoadd.log';
	\$cLastRun       = 'mpc_lastrun.log';
	\$cDownloadFile  = 'mpc_download.log';
	\$cOneTimeDL     = 'mpc_onetimedl.txt';
	\$cLastJobRun    = 'mpc_lastjobrun.log';
	\$UrlIdentString = '[DownLoadURL]';
	\$cWebConfig     = 'mpc_webconfig.php';
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
CheckCreateFile($cLastJobRun);
CheckCreateFile($cFeedsFile);
CheckCreateFile($cOldFiles);
CheckCreateFile($cOldFilestoAdd);
CheckCreateFile($cOldFiles);
CheckCreateFile($cOneTimeDL);
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
	 s/#.*//;            # ignore comments by erasing them
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

open OneTimeMediaDL, "$workdir/$cOneTimeDL" or die $!;
my @OneTimeDL = <OneTimeMediaDL>;
close(OneTimeMediaDL);
EraseFile($cOneTimeDL);

#
# Check if needed programs are installed.
#
@list = `$youtubedlPath --help`;
if ($? == -1) {
	writeLog("Missing program $youtubedlPath");
	writeLog("Download from http://rg3.github.com/youtube-dl/");
	$fail = 'y';
}
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
@list = `$xmlstarletPath --help`;
if ($? == -1) {
	writeLog("Missing program $xmlstarletPath");
	writeLog("install from apt-get install xmlstarlet");
	$fail = 'y';
}
@list = `$curlPath --help`;
if ($? == -1) {
	writeLog("Missing program $curlPath");
	writeLog("install from apt-get install curl");
	$fail = 'y';
}
if($fail eq 'y'){
	exit();
}

writeLog("Start:".rDateTime() );

ONETIME: foreach $oneTimeDL (@OneTimeDL){
	chomp($oneTimeDL);
	($otdURL, $otdTitle, $otdSubtitle, $otdDescp) = split(/\t/,$oneTimeDL);
	$DownloadType = DownladType($oneTimeDL);
	writeLog("OneTime type:$DownloadType Link:$oneTimeDL");
	
	if($DownloadType =~ 'youtube-dl'){
		YouTubedownload($otdURL, $otdTitle, $otdSubtitle, $otdDescp);
	}
	elsif($DownloadType =~ 'wget'){
		wgetdownload($otdURL, $otdTitle, $otdSubtitle, $otdDescp);
	}
}

FEED: foreach $feed (@feeds){
	
	my ($feedName, $feedUrl, $feedUser, $feedPass, $feedmisc, $DownloadType) = ' ';
	
	($feedName, $feedUrl, $feedUser, $feedPass, $feedmisc) = split("\t", $feed);
	
	$DownloadType = DownladType($feedUrl);
	
	writeLog("$feedName type:$DownloadType");

	if($DownloadType =~ 'youtube-dl'){
		$uniqueString = '---HopeThisIsUnique---';
		my $command = "$rsstailPath -u '$feedUrl' -ldcH1Z$uniqueString -n$MaxNumberofFeedItemsToDownload -b$MaxNumberofCharsToUseofDescption 2>&1";
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
				my ($fTitle, $fLink, $fDescription, $fLocalFileName) ='';
				foreach $line (@feedlines){
					($mkey, $mvalue) = split(/: /,$line, 2 );
					if($mkey =~ m/Title/){$fTitle = $mvalue;}
					if($mkey =~ m/Link/){$fLink = $mvalue;}
#					if($line =~ m/Description:/){$fDescription = $mvalue;}
				}
#				if(length($fDescription)<10){
#					next ITEM;
#				}
				# Skip item if we've already got it
				chomp($fLink);
				foreach my $item (@previouslyDownloaded){
					next ITEM if $fLink eq $item;
				}
				YouTubedownload($fLink, $feedName, $fTitle, $fDescription);
			}
		}
	}	elsif($DownloadType =~ 'wget'){
		my $cRecSS = '---------recordseperator--------';
		my $cFldS  = 'FldS-----------';
		my $cTitle = 'titl-----------';
		my $cDescS = 'dscp-----------';
		my $cLinkS = 'link-----------';
		
		
		if($feedUrl =~ m/justin.tv/i){ 
			$command = "$curlPath -L -s '$feedUrl' | $xmlstarletPath sel -t -m '/objects/object' -o '$cDescS' -v 'stream_name' -o ' ' -v 'title'  -o ' on ' -v 'created_on' -o '$cFldS' -o '$cTitle' -o ' Part ' -v 'broadcast_part' -o '$cFldS' -o '$cLinkS' -v 'video_file_url' -n -o '$cRecSS' -n";
		} elsif($feedUrl =~ m/blip.tv/i){ 
			$command = "$curlPath -L -s '$feedUrl' | $xmlstarletPath sel -t -m '/rss/channel/item' -o '$cDescS' -v 'title' -o '$cFldS' -o '$cLinkS' -m 'enclosure' -v '\@url' -n -o '$cRecSS' -n";
		} else {
			$command = "$curlPath -L -s '$feedUrl' | $xmlstarletPath sel -t -m '/rss/channel/item' -o '$cTitle' -v 'title' -o '$cFldS' -o '$cDescS' -v 'description' -o '$cFldS' -o '$cLinkS' -m 'enclosure' -v '\@url' -n -o '$cRecSS' -n";
		}
		writeDebugLog("$command");
		$block = qx($command);
		if($error =~ m/Start tag expected/i){
			writeLog("404 $feedName $feedUrl");
			next FEED;
		}
		$block =~ s/[\n\r\t]+//g;
		@records = split(/$cRecSS/,$block);
		my $FeedItemsCtr = 1;
		ITEMA: foreach $Record (@records){
			$FeedItemsCtr++;
			(@feilds) = split(/$cFldS/,$Record);
			foreach $Feild (@feilds){
				if($Feild =~ m/^$cLinkS/i){$fLink = trim(substr($Feild,length($cLinkS)));}
				if($Feild =~ m/^$cTitle/i){$fTitle = trim(substr($Feild,length($cTitle)));}
				if($Feild =~ m/^$cDescS/i){$fDescription = trim(substr($Feild,length($cDescS),$MaxNumberofCharsToUseofDescption));}
			}
			chomp($fLink);
			if($feedUrl =~ m/justin.tv/i){
				$fpos1 = index($fLink, '.justin.tv/');
				$justintvurl = substr($fLink, $fpos1);
				foreach my $item (@previouslyDownloaded){
					next ITEMA if $justintvurl eq $item;
				}
			} else {
				foreach my $item (@previouslyDownloaded){
					next ITEMA if $fLink eq $item;
				}
			}
			wgetdownload($fLink, $feedName, $fTitle, $fDescription);
			($fTitle, $fLink, $fDescription, $fLocalFileName) ='';
			if ($FeedItemsCtr > $MaxNumberofFeedItemsToDownload){
				goto LeaveFeedItems;
			}		
		}
		LeaveFeedItems:
	}
}

writeLog("Stop:".rDateTime() );
close(LOG);
close(OLDFILES);

sub writeRecorded{
	my($wFile, $wChanid, $wTitle, $wSubtitle, $wDescription, $wStarttime, $wOriginalAirDate) = @_;
	#
	# Create index someday.
	#
}

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

sub DownladType{
	my ($feedUrl) = @_;
	my $DownloadType = 'wget';
	if($feedUrl =~ /youtube.com/i) { $DownloadType = 'youtube-dl'; }
	if($feedUrl =~ /vimeo.com/i){ $DownloadType = 'youtube-dl'; }
	if($feedUrl =~ /blip.tv/i){ $DownloadType = 'wget'; }
	if($feedUrl =~ /escapistmagazine.com/i){ $DownloadType = 'youtube-dl'; }
	if($feedUrl =~ /justin.tv/i){ $DownloadType = 'wget'; }
  if($feedUrl =~ /pbs.org/i){ $DownloadType = 'youtube-dl'; }
#  if($feedUrl =~ //i){ $DownloadType = ''; }
#  if($feedUrl =~ //i){ $DownloadType = ''; }
#  if($feedUrl =~ //i){ $DownloadType = ''; }
#  if($feedUrl =~ //i){ $DownloadType = ''; }
	return($DownloadType);
}

sub YouTubedownload{
	my ($fLink, $feedName, $fTitle, $fDescription) = @_;
#	my ($fLocalFileName, $fDateTime, $fDate) = setupDates($fDescription, '.%(ext)s');
	
	writeDebugLog("Title:$fTitle");
	writeDebugLog("Description:$fDescription");
	$fLocalFileName = $fTitle;
	$fLocalFileName =~ s/\s/_/gi;
	$fLocalFileName =~ s/&amp;/and/gi;
	$fLocalFileName =~ tr|"'\\/%&:;||d;
	$fLocalFileName = $fLocalFileName . '.%(ext)s';
	writeDebugLog("Youtube Filename:$fLocalFileName");
	
	my $command = ("$youtubedlPath --no-part -vo '$DowloadDir/$feedName/$fLocalFileName' '$fLink' >$workdir/$cDownloadFile");
	
	if(! -d "$DowloadDir/$feedName"){
		mkdir("$DowloadDir/$feedName");
	} 
	writeDebugLog("$command");
	my $cLog = qx($command);
	writeDebugLog("Youtube:$cLog");
	$cLog = trim($cLog);
	if($cLog eq ''){
		open YT_OUT, "$workdir/$cDownloadFile" or die $!;
		my @yt_out = <YT_OUT>;
		close(YT_OUT);
		my @string = grep(/Destination:/i, @yt_out);
		my ($xkey, $xvalue) = split(/: /,@string[0]);
		chomp($xvalue);
		writeDebugLog("Basename: $xvalue");
		my $File = basename($xvalue);
		if(length($fTitle) < 11){
			$fTitle = $fTitle . ' ' . substr($fDescription,0,30);
			$fDescription = substr($fDescription,30)
		}
		writeRecorded(
			$File,
			$ChannelId,
			$feedName,
			$fTitle,
			$fDescription . ' ' . $UrlIdentString . $fLink,
			$fDateTime,
			$fDate
			);
		writeOldFilesLog($fLink);
		sleep(1);
		#	exit();
		($fTitle, $fLink, $fDescription, $fLocalFileName) ='';
		return true;
	} else {
		writeLog("Faild to retrive file. $fLink from $feedName.");
		return false;
	}
}

sub wgetdownload{
	my ($fLink, $feedName, $fTitle, $fDescription) = @_;
	
#	my ($suffix) = $fLink =~ /(\.[^.]+)$/;
#	my($fLocalFileName, $fDateTime, $fDate) = setupDates($ChannelId, $suffix);
#	$fpos1 = index($fLocalFileName, '?');
#	if($fpos1 > -1){
#		$fLocalFileName = substr($fLocalFileName, 0, $fpos1);
#	}

#	Remove anythig after the ? in url for the file name
	$fpos1 = index($fLink, '?');
	if($fpos1 > -1){
		$fLocalFileName = substr($fLink, 0, $fpos1);
	} else {
		$fLocalFileName = $fLink;
	}
#	Get the file name.
	$fpos1 = rindex($fLocalFileName, '/');
	if($fpos1 > -1){
		$fLocalFileName = substr($fLocalFileName, ++$fpos1);
	}
	$fLocalFileName =~ s/\s/_/gi;
	$fLocalFileName =~ s/&amp;/and/gi;
	$fLocalFileName =~ tr|"'\\/%&:;||d;
	
	if(length($fLocalFileName)<15){
		$fpos1 = rindex($fLocalFileName, '.');
		if($fpos1 > -1){
			$fTitle =~ s/\s/_/gi;
			$fTitle =~ s/&amp;/and/gi;
			$fTitle =~ tr|"'\\/%&:;||d;
			$fLocalFileName = $fTitle . substr($fLocalFileName, $fpos1);
		}
	}
	
	my $command = ("$wgetPath -v --output-document='$DowloadDir/$feedName/$fLocalFileName' --output-file=$workdir/$cDownloadFile '$fLink'");
	writeDebugLog("$DowloadDir/$feedName");
	if(! -d "$DowloadDir/$feedName"){
		mkdir("$DowloadDir/$feedName");
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
	writeRecorded(
		$fLocalFileName,
		$ChannelId,
		$feedName,
		$fTitle,
		$fDescription . ' ' . $UrlIdentString . $fLink,
		$fDateTime,
		$fDate
		);
	if($fLink =~ m/justin.tv/i){
		$fpos1 = index($fLink, '.justin.tv/');
		$justintvurl = substr($fLink, $fpos1);
		writeOldFilesLog($justintvurl);
	} else {
		writeOldFilesLog($fLink);
	}
	sleep(1);
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
