#!/usr/bin/perl

#****************************************************************************
#*   Cisco Find Host                                                        *
#*   Finds what port an ip address or host is on                            *
#*                                                                          *
#*   Copyright (C) 2013 by Jeremy Falling except where noted.               *
#*                                                                          *
#*   This program is free software: you can redistribute it and/or modify   *
#*   it under the terms of the GNU General Public License as published by   *
#*   the Free Software Foundation, either version 3 of the License, or      *
#*   (at your option) any later version.                                    *
#*                                                                          *
#*   This program is distributed in the hope that it will be useful,        *
#*   but WITHOUT ANY WARRANTY; without even the implied warranty of         *
#*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          *
#*   GNU General Public License for more details.                           *
#*                                                                          *
#*   You should have received a copy of the GNU General Public License      *
#*   along with this program.  If not, see <http://www.gnu.org/licenses/>.  *
#****************************************************************************


use strict;
use warnings;
use Net::SNMP;
use Socket;
use NetAddr::IP; 
use Getopt::Long;
use Term::ANSIColor;
use Net::SSH::Perl;

use vars qw($opt_d $opt_h $opt_H $opt_C $opt_c $PROGNAME);

########################################################################################
#NOTES
#exit codes are 0- ok 1 - user error 2- script failure
#unless -d is provided, minimal output is given so this script can be ran automagicly
#
#

########################################################################################
#Define varriables
my $PROGNAME = "cisco_port_utilty.pl";
my $username = "admin";
my $password = "pass";
my $enable_password = "password";
my $default_com = "public";

my $null_var; #Anything we don't care about but need a variable for some sort of task, use this
my $opt_h;
my $opt_d;
my $opt_c;
my $opt_Host;
my $opt_C;
my $host_ip;
my $packed_ip;
my $numofvlans;
my $current_vlan;
my $human_status;
my $human_error;
my $exit_request;
my @output;

########################################################################################
Getopt::Long::Configure('bundling');
GetOptions
	("d"   => \$opt_d, "debug"    => \$opt_d,
	 "h"   => \$opt_h, "help"       => \$opt_h,
	 "c=s"   => \$opt_c, "cisco=s"       => \$opt_c,
	 "H=s" => \$opt_Host, "host=s" => \$opt_Host,
	 "C=s" => \$opt_C, "community=s" => \$opt_C);

if ($opt_h) {

print "

This script can be used to find what port is associated with an ip or hostname. 

-H, --host=HOST
   The host you want to find 
-c, --cisco=HOST
   Name or IP address of device to run the checks on
-C, --community=community
   SNMPv1 community (default public)
-d, --debug
   Enable debugging (Are you a human? Yes? Great! you will more then likely want to use this flag to see what is going on. Or not if you are utterly boring....)
   
";
exit (0);}


unless ($opt_Host) {print colored ['red'],"Host name/address not specified\n"; print color("reset"); exit (1)};
my $host = $1 if ($opt_Host =~ /([-.A-Za-z0-9]+)/);
unless ($host) {print colored ['red'],"Invalid host: $opt_Host\n"; print color("reset"); exit (1)};

unless ($opt_c) {print colored ['red'],"Device \(switch or router\) not specified \n"; print color("reset"); exit (1)};
my $host_device = $opt_c;

my $snmp_community = $opt_C;
unless ($opt_C) {$snmp_community = $default_com;};



########################################################################################
#start new snmp session
my($snmp,$snmp_error) = Net::SNMP->session(-hostname => $host_device,
                                           -community => $snmp_community,);
                                           
debugOutput("\n**DEBUGGING IS ENABLED**\n");
debugOutput("**DEBUG: Attempting to see where $host is plugged in.....");

#check to see if user provided a hostname or ip address
if ($host =~ /[a-zA-Z]/)
{
	#user provided a hostname, convert to ip.
	debugOutput("**DEBUG: Looks like you provided a hostname, converting to ip address");
	#convert host to ip
	$packed_ip = gethostbyname("$host");
	my $hname_to_ip_stat = $?;
	#check to see if resolution failed, and if so, give error and exit
	debugOutput("**DEBUG: return code from gethostbyname is: $hname_to_ip_stat  \n");
	if ($hname_to_ip_stat!=0){ print colored ['red'], "ERROR: name resolution of $host failed. \n"; print color("reset"); exit (2);}
		
	if (defined $packed_ip) {
		$host_ip = inet_ntoa($packed_ip);
		debugOutput("**DEBUG: After conversion, our host ip is $host_ip ");
    }
}

else
{   
	#user gave an ip address
	debugOutput("**DEBUG: Looks like you provided an ip address, no need to convert anything");
	$host_ip = $host;
	
}



########################################################################################
#we dont exit if ping fails, some devices wont respond to ping but the ping causes the arp
#table to be populated if the ip exists

debugOutput("**DEBUG: Preparing to ping host");

my $dec = pack("C*",split /\./, $host_ip);

#the id will be based upon the ip addr, so this script can be used multiple times at once
my$row = $host_ip;
$row =~ s/\.//g;

my %ping_oids = (
	'ciscoPingEntryStatus'      => ".1.3.6.1.4.1.9.9.16.1.1.1.16.$row",
	'ciscoPingEntryOwner'       => ".1.3.6.1.4.1.9.9.16.1.1.1.15.$row",
	'ciscoPingProtocol'         => ".1.3.6.1.4.1.9.9.16.1.1.1.2.$row",
	'ciscoPingPacketCount'      => ".1.3.6.1.4.1.9.9.16.1.1.1.4.$row",
	'ciscoPingPacketSize'       => ".1.3.6.1.4.1.9.9.16.1.1.1.5.$row",
	'ciscoPingAddress'          => ".1.3.6.1.4.1.9.9.16.1.1.1.3.$row",
	'sent'                      => ".1.3.6.1.4.1.9.9.16.1.1.1.9.$row",
	'received'   			    => ".1.3.6.1.4.1.9.9.16.1.1.1.10.$row",
	'low'     					=> ".1.3.6.1.4.1.9.9.16.1.1.1.11.$row",
	'avg'     					=> ".1.3.6.1.4.1.9.9.16.1.1.1.12.$row",
	'high'      				=> ".1.3.6.1.4.1.9.9.16.1.1.1.13.$row",
	'completed'      			=> ".1.3.6.1.4.1.9.9.16.1.1.1.14.$row",
	

);

$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingEntryStatus}, INTEGER, 6]);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingEntryStatus:",2);
$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingEntryStatus}, INTEGER, 5]);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingEntryStatus:",2);
$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingEntryOwner}, OCTET_STRING, "perlscript"]);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingEntryOwner:",2);
$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingProtocol}, INTEGER, 1]);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingProtocol:",2);
$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingPacketCount}, INTEGER, 4]);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingPacketCount:",2);
$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingPacketSize}, INTEGER, 150]);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingPacketSize:",2);
$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingAddress}, OCTET_STRING, $dec]);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingAddress:",2);


#start ping
$snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingEntryStatus}, INTEGER, '1']);
checkSNMPStatus("ERROR: could not start ping:",2);

debugOutput("**DEBUG: successfully started ping, do wait a bit… ");
sleep 12;

my %ping_results = ();

#get the ping results, validate the response, then convert from a hash
my $sent_h = $snmp->get_request( -varbindlist => [$ping_oids{sent}]);
checkSNMPStatus("ERROR: could not get ping results - sent:",2);
($null_var,my $sent) = each %$sent_h;

my $received_h = $snmp->get_request( -varbindlist => [$ping_oids{received}]);
checkSNMPStatus("ERROR: could not get ping results - received:",2);
($null_var,my $received) = each %$received_h;

#dont sanity check snmp for low, avg, and high. these dont have values if the ping failed
my $low_h = $snmp->get_request( -varbindlist => [$ping_oids{low}]);
($null_var,my $low) = each %$low_h;

my $avg_h = $snmp->get_request( -varbindlist => [$ping_oids{avg}]);
($null_var,my $avg) = each %$avg_h;

my $high_h = $snmp->get_request( -varbindlist => [$ping_oids{high}]);
($null_var,my $high) = each %$high_h;

my $completed_h = $snmp->get_request( -varbindlist => [$ping_oids{completed}]);
checkSNMPStatus("ERROR: could not get ping results - completed:",2);
($null_var,my $completed) = each %$completed_h;

#check if low has a value, if so give the normal results.
if ($low){
#give the user some output if they so desire
	if ($opt_d) {printf "**DEBUG: Packet loss: %d percent (%d/%d) \n", (100 * ($sent-$received)) / $sent, $received, $sent;}
	debugOutput(print "**DEBUG: Average delay $avg \(low: $low high: $high\)");
}
#otherwise limit the output to prevent some math related errors
else{
	if ($opt_d) {printf "**DEBUG: Packet loss: %d percent (%d/%d) \n", (100 * ($sent-$received)) / $sent, $received, $sent;}

}



#clear the table
my $snmp_set_status = $snmp->set_request( -varbindlist =>  [$ping_oids{ciscoPingEntryStatus}, INTEGER, '6']);
checkSNMPStatus("ERROR: could not set snmp value ciscoPingEntryStatus:",2);



########################################################################################
#get vlans, then look for ip based on vlan to save on the switch load

my %oids = (
    'ifDescr'                      => '1.3.6.1.2.1.2.2.1.2',
);


debugOutput("**DEBUG: Looking for vlans");

my $info = $snmp->get_entries(-columns => [ $oids{ifDescr}], -startindex => "1", -endindex => "4096" ); #this is so we only look for the first 4096 interfaces. vlans are 1-4096
checkSNMPStatus("ERROR: Could not get list of vlans:",2);

$numofvlans = scalar keys %$info;

debugOutput("**DEBUG: Found $numofvlans vlans");

 ########################################################################################
#get the mac address for the host given

my $mediatoaddy;
my $mac_addy;


LOOK_FOR_MAC_ADDY: foreach my $oid (grep /^$oids{ifDescr}\./, keys(%$info)) {

  my($index) = $oid =~ m|\.(\d+)$|;
 
  $current_vlan = join(',', $index);
 
  my %oids2 = (
                'ipNetToMediaPhysAddress'      => "1.3.6.1.2.1.4.22.1.2.$current_vlan.$host_ip",
  );
  
  debugOutput("**DEBUG: Looking for host in vlan $current_vlan");
  
  $mediatoaddy = $snmp->get_request( -varbindlist => [ $oids2{ipNetToMediaPhysAddress}]);
#  unless ($mediatoaddy) {print "Couldn't poll device \n", $snmp->error(); exit (1)};




        foreach my $key (keys %{$mediatoaddy}) {
                $mac_addy = "$mediatoaddy->{$key}";
                #strip off 0x
                $mac_addy =~ s/0x//g;

                if ($mac_addy ne "") {
                        debugOutput("**DEBUG: Found mac address $mac_addy in vlan $current_vlan ");
                        last LOOK_FOR_MAC_ADDY; #break the
                        
                } else {
                        debugOutput("**DEBUG: did not find host in vlan $current_vlan \n");
                }
                
         }
}

#check to see if mac was found
unless ($mac_addy) {print "Couldn't find mac address for host, does the cisco have an ip on the vlan your host is in? ", $snmp->error();print "\n"; exit (2)};


#convert mac address to h.h.h.h format as required by the cisco
debugOutput("**DEBUG: Converting mac addess to cisco format  ");
#add validation for mac addy here**


my $cisco_mac_addy = $mac_addy;
$cisco_mac_addy =~ s/(.{4})/$1./g;
$cisco_mac_addy = substr($cisco_mac_addy, 0, -1);
debugOutput("**DEBUG: Mac converted to $cisco_mac_addy  ");

########################################################################################
#get port mac is associated to
#http://www.cisco.com/en/US/tech/tk648/tk362/technologies_tech_note09186a00801c9199.shtml
#
#looks like vlan after com. is required, ex public@202
#
#looks also like snmp on the on this mib is broken... using ssh as a temp workaround...

debugOutput("**DEBUG: Finding which port the host is associated with ");

doSSH();

debugOutput("\n");

print "Ports this mac address is on:\n @output\n";

debugOutput("\n");

########################################################################################
#Functions!

#This function will do the error checking and reporting when related to SNMP
sub checkSNMPStatus {
	$human_error = $_[0];
	$exit_request = $_[1];
	$snmp_error = $snmp->error();
    
    #check if there was an error, if so, print the requested message and the snmp error. I used the color red to get the user's attention.
    if ($snmp_error) {
		print colored ['red'], "$human_error $snmp_error \n";

		#check to see if the error should cause the script to exit, if so, exit with the requested code
		if ($exit_request) {
			print color("reset");
			exit $exit_request;
		}
	}
}

#This function will be used to give the user output, if they so desire
sub debugOutput {
	$human_status = $_[0];
    if ($opt_d) {
		print "$human_status \n";
		
	}
}

#sub to loginto the switch via ssh
#return requires a subroutine, so here it is:
sub doSSH {
	my $session = Net::SSH::Perl -> new($host_device);
	 $session -> login($username, $password);
	 $session -> cmd("enable $enable_password");
	 @output = $session -> cmd("show mac-address-table address $cisco_mac_addy");
	# $session -> close;
	 return @output;
}

#Well shucks, we made it all the way down here with no errors. Guess we should exit without an error ;)
print color("reset");
exit 0;

