#!/usr/bin/perl

use 5.008007;
use warnings;
use strict;

use DBI;
use SQL::Beautify;

my $cfg;
my $hhmmss;

BEGIN
{

	print "++++++++++++++++++++++++++++++++++\n";
	print "Turn 18 Report begin";
	my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = localtime(time);
	$hhmmss = sprintf "%.2d:%.2d:%.2d", $hour, $min, $sec;
	print " at ".$hhmmss."...\n";

	use Config::Simple;
	
	$cfg = new Config::Simple('turn18.cfg');
	
	my $sierra_modules = ( defined $cfg->param("SierraModulesLocation") ) ? $cfg->param("SierraModulesLocation") : "/home/plchuser/Modules";
	print " + We're using modules from: " . $sierra_modules . "\n";
	
	#usually either '/home/plchuser/Modules' or '/home/plchuser/Testing/Modules'
	push(@INC,$sierra_modules);
}

use Sierra::PatronUpdate qw( change_patron_field );
use Sierra::DB qw ( sierra_db_query );
use Sierra::SoapApi;
use Sierra::PatronSoap;

my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = localtime(time);
my $today = sprintf  "%.4d%.2d%.2d", $year+1900, $mon+1, $mday;
my $today_slashes = sprintf  "%.2d/%.2d/%.4d", $mon+1, $mday, $year+1900;

#------------------------------------------------------------------------------------------------------------------------
# DB Query
 
my $db_host = ( defined $cfg->param("DatabaseHost") ) ? $cfg->param("DatabaseHost") : "sierra-train.plch.net";
my $db_port = $cfg->param("DatabasePort");
my $db_user = $cfg->param("DatabaseUser");
my $db_pass = $cfg->param("DatabasePass");

print " + We're connecting to ".$db_host." for SQL query...\n";
my $dbh = DBI->connect("DBI:Pg:dbname=iii;host=".$db_host.";port=".$db_port."",$db_user,$db_pass,{'RaiseError'=>0});


my $sql_query 	 = "SELECT ";
	$sql_query .= "sierra_view.patron_view.record_num, ";
	$sql_query .= "sierra_view.patron_view.ptype_code, ";
	$sql_query .= "to_char( sierra_view.patron_view.expiration_date_gmt , 'YYYYMMDD' ) as e_date, ";
	$sql_query .= "sierra_view.patron_view.barcode ";
	$sql_query .= "FROM sierra_view.patron_view ";
	
	#certain ptypes only
	$sql_query .= "WHERE sierra_view.patron_view.ptype_code IN ( 0 , 1 , 2 , 5 , 6 , 7 , 30 , 31 , 32 ) ";
	$sql_query .= "      AND sierra_view.patron_view.birth_date_gmt + interval '18 years' = current_date ";
	# per LL, expired cards should not be excluded. 20160126
	#$sql_query .= "      AND sierra_view.patron_view.expiration_date_gmt > '".$today."' ";
	
	$sql_query .= ";";

my $s = SQL::Beautify->new;
$s->query($sql_query);
my $nice_sql = $s->beautify;
print $nice_sql."\n";

my $sth = sierra_db_query( $dbh , $sql_query );

#------------------------------------------------------------------------------------------------------------------------


#------------------------------------------------------------------------------------------------------------------------
# Process results

my $patron_api_host = ( defined $cfg->param("PatronAPIHost") ) ? $cfg->param("PatronAPIHost") : "sierra-train.plch.net";
my $patron_api_user = $cfg->param("PatronAPIUser");
my $patron_api_pass = $cfg->param("PatronAPIPass");
print "connecting to " . $patron_api_host . " for PatronAPI...\n";

my $api = Sierra::SoapApi->new( $patron_api_host, $patron_api_user, $patron_api_pass );

my $num_failed = 0;
my $num_succeeded = 0;

while( my $patron_info = $sth->fetchrow_hashref() )
{
	my $record_num =	( defined $patron_info->{'record_num'}		) ? $patron_info->{'record_num'}	: '';
	my $ptype =		( defined $patron_info->{'ptype_code'}		) ? $patron_info->{'ptype_code'}	: '';
	my $barcode =		( defined $patron_info->{'barcode'}			) ? $patron_info->{'barcode'}		: '';
	my $current_expdate=( defined $patron_info->{'e_date'}			) ? $patron_info->{'e_date'}		: '';

	print "updating patron: " . $record_num . " " . $barcode . "\n";

	my $new_expdate = "";

	if (( grep {$_ eq $ptype} ('0','1','2','5','6','7') ) && ( $current_expdate >= $today ))
	{
		# new expdate equals today
		$new_expdate = $today . "040000";
	}
	else
	{
		#just keep the same expiration date
		$new_expdate = $current_expdate . "040000";
	}
	print "setting expdate to " . $new_expdate . "...\n";		

	my $num_errors = 0;

	my $patron = $api->search_patron(".p".$record_num."a");

	# change patron field( 43=expdate ) and add message
	$patron->alter_fields( {'43' => $new_expdate } );
	$patron->add_message( $today_slashes." User turned 18.  Need agreement signed." );

	$api->update_patron($patron);

	if ( $num_errors > 0 )
	{
		$num_failed++;
	}
	else
	{
		$num_succeeded++;
	}
	print "\n";    
}

#print "failed: ".$num_failed."\n";
#print "succeeded: ".$num_succeeded."\n";
#------------------------------------------------------------------------------------------------------------------------

print "++++++++++++++++++++++++++++++\n";
print "Turn 18 Report done.\n";
( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = localtime(time);
$hhmmss = sprintf "%.2d:%.2d:%.2d", $hour, $min, $sec;
print "script finish at ".$hhmmss."...\n";
print "++++++++++++++++++++++++++++++\n";
