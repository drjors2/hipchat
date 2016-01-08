#!/usr/bin/perl
# -*-cperl-*
#
# Perl script to send a notification to hipchat using either the REST API v1 or v2.
#
# Created by Chris Tobey.
#

use warnings       ;
use strict         ;
use Getopt::Long   ;
use LWP::UserAgent ;
use JSON           ;
use Pod::Usage     ;
use Carp ;
use Config::Simple ;

my $usage = "This script will send a notification to hipchat.\n
\tUsage:
\t\t--help     Shows this help
\t\t-room      Hipchat room name or ID.
\t\t\t\tExample: '-room \"test\"'
\t\t-token     Hipchat Authentication token.
\t\t\t\tExample: '-token \"abc\"'
\t\t-message   Message to be sent to room.
\t\t\t\tExample: '-message \"Hello World!\"'
\t\t-topic     Topic to be sent to room.
\t\t\t\tExample: '-topic \"Hello World!\"'
\t\t-type      (Optional) Hipchat message type (text|html).
\t\t\t\tExample: '-type \"text\"'                   (default: text)
\t\t-API       (Optional) Hipchat API Version. (v1|v2).
\t\t\t\tExample: '-type \"v2\"'                     (default: v2)
\t\t-notify    (Optional) Message will trigger notification.
\t\t\t\tExample: '-notify \"true\"'                 (default: false)
\t\t-colour    (Optional) Message colour (y|r|g|p|g|random)
\t\t\t\tExample: '-colour \"green\"'                (default: yellow)
\t\t-from      (Optional) Name message is to be sent from.
\t\t\t\tExample: '-from \"Test\"'                   (only used with APIv1)
\t\t-proxy     (Optional) Network proxy to use.
\t\t\t\tExample: '-proxy \"http://127.0.0.1:3128\"'

\n\tBasic Example:
\t\thipchat.pl -room \"test\" -token \"abc\" -message \"Hello World!\" 
\n\tFull Example:
\t\thipchat.pl -room \"test\" -token \"abc\" -message \"Hello World!\" \\
\t\t\t\t -type text -api v2 -notify true -colour green -proxy http://127.0.0.1:3128
\n";

my $cfg = new Config::Simple('hipchat.cfg') or die Config::Simple->error();

my $tokens = $cfg->get_block('tokens');

my $oRoom           = ""                                      ;
my $oToken          = ""                                      ;
my $oMessage        = ""                                      ;
my $oTopic          = ""                                      ;
my $oFrom           = ""                                      ;
my $oType           = ""                                      ;
my $oAPI            = ""                                      ;
my $oProxy          = ""                                      ;
my $oNotify         = ""                                      ;
my $oColour         = ""                                      ;
my $oDebug          = ""                                      ;
my $hipchat_host    = ""                                      ;
my $hipchat_url     = ""                                      ;
my $hipchat_json    = ""                                      ;
my $message_limit   = ""                                      ;
my @valid_colours   = qw/yellow red green purple gray random/ ;
my $colour_is_valid = ""                                      ;
my $default_colour  = ""                                      ;
my @valid_types     = qw/html text/                           ;
my $type_is_valid   = ""                                      ;
my $default_type    = ""                                      ;
my @valid_APIs      = qw/v1 v2/                               ;
my $api_is_valid    = ""                                      ;
my $default_API     = ""                                      ;
my $ua              = ""                                      ;
my $request         = ""                                      ;
my $response        = ""                                      ;
my $exit_code       = ""                                      ;

#Set some options statically.
$hipchat_host          = "https://api.hipchat.com"               ;
$default_colour        = "yellow"                                ;
$default_API           = "v2"                                    ;
$default_type          = "html"                                  ;
$message_limit         = 10000                                   ;

#Get the input options.
GetOptions( "room|r=s"         => \$oRoom    ,
            "token|k=s"        => \$oToken   ,
            "message|m=s"      => \$oMessage ,
            "from|f=s"         => \$oFrom    ,
            "type|y=s"         => \$oType    ,
            "api|a=s"          => \$oAPI     ,
            "proxy|x=s"        => \$oProxy   ,
            "notify|n=s"       => \$oNotify  ,
            "colour|color|c=s" => \$oColour  ,
            "debug|d=s"        => \$oDebug   ,
            "topic|t=s"        => \$oTopic
          );

##############################
## VERIFY OPTIONS
##############################

#Check to verify that all options are valid before continuing.

($oRoom eq "") &&  die "\tYou must specify a Hipchat room!\n\n$usage"        ;

my $cat;
{local $/=undef; $cat=<>;};
if ($oMessage eq "") {
    die "\tYou must specify a message to post!\n\n$usage"  unless  ($cat =~ /\w+/) ; 
    $oMessage = $cat;
}
#Check that the API version is valid.
$oAPI = $oAPI || $default_API                                                ;

foreach my $api (@valid_APIs) {
  if (lc($oAPI) eq $api) {
    $api_is_valid = 1                                                        ;
    $oAPI = $api                                                             ;
    last                                                                     ;
  }
}
$api_is_valid || print "\tYou must select a valid API version!\n\n$usage"    ;

#Check that the From name exists if using API v1.
$oFrom eq "" && $oAPI eq "v1" &&
  die "\tYou must specify a From name when using API v1!\n\n$usage"          ;

#Check that the message is shorter than $message_limit characters.
length($oMessage) > $message_limit &&
  die "\tMessage must be $message_limit characters or less!\n\n$usage"       ;

#Check that the message type is valid.
$oType = $oType || $default_type                                             ;

foreach my $type (@valid_types) {
  if (lc($oType) eq $type) {
    $type_is_valid = 1                                                       ;
    $oType = $type                                                           ;
    last                                                                     ;
  }
}
$type_is_valid ||  die "\tYou must select a valid message type!\n\n$usage"   ;

#Check if the notify option is set, else turn it off.
if (lc($oNotify) eq "y" || lc($oNotify) eq "yes" || lc($oNotify) eq "true") {
  $oNotify = ($oAPI eq "v1") ? "1" : "true"
} else {
  $oNotify = ($oAPI eq "v1") ? "0" : "false"                                 ;
}

#Check that the colour is valid.
$oColour = $oColour || $default_colour                                       ;
foreach my $colour (@valid_colours) {
  if (lc($oColour) eq $colour) {
    $colour_is_valid = 1                                                     ;
    $oColour = $colour                                                       ;
    last                                                                     ;
  }
}
$colour_is_valid || die "\tYou must select a valid colour!\n\n$usage"        ;

##############################
### SUBMIT THE NOTIFICATION ##
##############################

#Setup the User Agent.
$ua = LWP::UserAgent->new;

#Set the default timeout.
$ua->timeout(10);

#Set the proxy if it was specified.
if ($oProxy ne "") {
  $ua->proxy(['http', 'https', 'ftp'], $oProxy);
}

#Submit the notification based on API version
if ($oAPI eq "v1") {
  $hipchat_url = "$hipchat_host\/$oAPI\/rooms/message";

  $response            = $ua->post($hipchat_url , {
                                                   auth_token     => $oToken   ,
                                                   room_id        => $oRoom    ,
                                                   from           => $oFrom    ,
                                                   message        => $oMessage ,
                                                   message_format => $oType    ,
                                                   notify         => $oNotify  ,
                                                   color          => $oColour  ,
                                                   format         => 'json'    ,
                                                  });
} elsif ($oAPI eq "v2") {
  if ($oTopic) {
    $hipchat_url = sprintf ("$hipchat_host\/$oAPI\/room/$oRoom/topic?auth_token=$oToken" ,
                            $tokens->{SendNotif});
    $hipchat_json     = encode_json({topic => $oTopic});
    print "$hipchat_json$/";
    $request = HTTP::Request->new(POST => $hipchat_url) ;
    $request->content_type('application/json')          ;
    $request->content($hipchat_json)                    ;

    $response = $ua->request($request)                  ;
  } else {
    $hipchat_url = sprintf ("$hipchat_host\/$oAPI\/room/$oRoom/notification?auth_token=%s"
                            , $tokens->{SendNotif});
    $hipchat_json     = encode_json({
                                     color          => $oColour  ,
                                     message        => $oMessage ,
                                     message_format => $oType    ,
                                     notify         => $oNotify  ,
                                    });
    print "$hipchat_json$/";

    $request = HTTP::Request->new(POST => $hipchat_url) ;
    $request->content_type('application/json')          ;
    $request->content($hipchat_json)                    ;

    $response = $ua->request($request)                  ;
  }
} else {
  print "The API version was not correctly set! Please try again.\n";
}

#Check the status of the notification submission.
if ($response->is_success) {
  print "Hipchat notification posted successfully.\n" ;
} else {
  print "Hipchat notification failed!\n"              ;
  print $response->status_line . "\n"                 ;
}

#Print some debug info if requested.
if ($oDebug ne "") {
  print $response->decoded_content . "\n"   ;
  print "URL            = $hipchat_url\n"   ;
  print "JSON           = $hipchat_json\n"  ;
  print "auth_token     = $oToken\n"   ;
  print "room_id        = $oRoom\n"    ;
  print "from           = $oFrom\n"    ;
  print "message        = $oMessage\n" ;
  print "message_format = $oType\n"    ;
  print "notify         = $oNotify\n"  ;
  print "color          = $oColour\n"  ;
}

#Always exit with 0 so scripts don't fail if the notification didn't go through.
#Will still fail if input to the script is invalid.

$exit_code = 0;
exit $exit_code;


__DATA__
testing 
