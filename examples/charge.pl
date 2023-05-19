#!/usr/bin/env perl
use warnings;
use strict;
use feature 'say';
use POSIX;
use Tesla::Vehicle;
use Data::Dumper; $Data::Dumper::Deepcopy=1; $Data::Dumper::Sortkeys=1;
$|=1;

my $TEMPERATURE=23;
my $MINUTES_PER_PERCENT=4.1;
my $MINUTES_PER_PERCENT_AMPS=16;
my $PHASES_DEFAULT=3;
my $OVERHEAD_1PAMPS=1.1; #Amps; FIXME: read voltage for Watts
my $MI_TO_KM=1.609344;
my $KWH_TO_CZK=7.28;

my $car;
my $cmd_ran;
my $opt_n;
sub cmd($@) {
  my($cmd,@args)=@_;
  my $setter=@args||$cmd=~/_(?:on|off|lock|unlock)$/;
  $cmd_ran=1 if $setter&&!$opt_n;
  my %suffixl=("charge_limit_set"=>"%","charge_amps_set"=>"A");
  my %suffixr=("battery_level"=>"%","charge_limit_soc"=>"%");
  my $rhs;
  if ($setter&&$opt_n) {
    $rhs="-n";
  } else {
    $rhs=$car->$cmd(@args);
    $rhs="ok" if $setter&&$rhs&&$rhs eq 1;
    $rhs.=$suffixr{$cmd}//"";
  }
  say join(" ",$cmd,map $_//"undef",@args).($suffixl{$cmd}//"").": $rhs";
}
sub minutes_to_time($) {
  my($minutes)=@_;
  return "none" if !defined $minutes;
  return sprintf "%02d:%02d",$minutes/60,$minutes%60;
}
my $timere=qr/0*(\d+):0*(\d+)/;
sub time_to_minutes($) {
  my($time)=@_;
  return undef if !defined $time;
  my($h,$m)=($time=~/^$timere$/o) or die "$time is not d+:d+";
  die "Hours is not 0..23" if $h<0||$h>23;
  die "Minutes is not 0..59" if $m<0||$m>59;
  return $h*60+$m;
}

my $windows;
sub windows() {
  my $windows_text=join ", ",map {0=>"closed",1=>"venting",2=>"opened"}->{$_},map $car->state->{"${_}_window"},qw(fd fp rd rp);
  $windows=$windows_text=~s/^([^,]+)(?:, \1)+$/all $1/?$car->state->{"fd_window"}:undef;
  say "Windows are $windows_text.";
}
sub doors() {
  my $doors=join ", ",map $_==0?"closed":"open$_",map $car->state->{"${_}"},qw(df pf dr pr);
  $doors=~s/^([^,]+)(?:, \1)+$/all $1/;
  say "Doors are $doors." if $doors ne "all closed";
}
sub phases() {
  return $PHASES_DEFAULT if !defined $car->charger_phases;
  return $car->charger_phases;
}
sub state() {
  cmd "charge_limit_soc";
  cmd "charging_state";
  say "scheduled_charging: ".minutes_to_time $car->scheduled_charging;
  say "preconditioning: ".minutes_to_time $car->preconditioning;
  windows;
  doors;
  if ($car->is_climate_on) {
    say "Car conditioning is on.";
    say "Temperature set to ".$car->temperature_setting_driver." != $TEMPERATURE." if $car->temperature_setting_driver!=$TEMPERATURE;
    say "warning: temperature_setting_passenger ".$car->temperature_setting_passenger." != ".$car->temperature_setting_driver." temperature_setting_driver"
      if $car->temperature_setting_passenger!=$car->temperature_setting_driver;
  }
  if ($car->charge_actual_current) {
    say "Charging ".phases."x".$car->charge_actual_current."A"
      .($car->charge_actual_current==$car->charge_current_request?".":" but requested ".phases."x".$car->charge_current_request."A!!!");
  }
  say "Charger set to ".phases."x".$car->charge_current_request."A of ".phases."x".$car->charge_current_request_max."A!"
    if $car->charge_current_request!=$car->charge_current_request_max;
  say "Both conditioning and preconditioning are set!" if $car->is_climate_on&&$car->preconditioning;
  say "Car is locked." if $car->locked;
  say "Sentry mode is on." if $car->sentry;
  say "Sentry mode is not available!" if !$car->state->{"sentry_mode_available"};
  say "Sentry mode != car lock." if $car->sentry!=$car->locked;
  my $sw=$car->state->{"software_update"};
  say "Firmware: ".join " ",map "$_=".$sw->{$_},sort keys %$sw if $sw->{"status"};
}

my $battery_want;
my $time_want;
my $minutes_want_from;
my $minutes_want_to;
my $precondition;
my $reset;
my $windows_want;
my $auto_wake=1;
my $battery_direct;
my $conditioning;
my $lock;
my $sentry;
my $dump;
my $history;
my $amps;
for my $arg (@ARGV) {
  if ($arg=~/^\d+$/&&$arg>=50&&$arg<=120) {
    if (!defined $battery_want) {
      die "battery $arg > 100" if $arg>100;
      $battery_want=$arg;
    } elsif (!defined $time_want) {
      $time_want=$arg;
    } else {
      die "Excessive battery/time: $arg";
    }
  } elsif ($arg=~/^(@?)($timere)$/o) {
    ($1?$minutes_want_from:$minutes_want_to)=time_to_minutes $2;
  } elsif ($arg=~/^p([01])?$/) { # precondition
    $precondition=$1//1;
  } elsif ($arg eq "r") {
    $reset=1;
  } elsif ($arg eq "s") { # sleep
    $auto_wake=0;
  } elsif ($arg=~/^b([01])?$/) { # battery-on/off
    $battery_direct=$1//1;
  } elsif ($arg=~/^c([01])?$/) { # conditioning-on/off
    $conditioning=$1//1;
  } elsif ($arg=~/^l([01])?$/) { # lock-on/off
    $lock=$1//1;
  } elsif ($arg=~/^s([01])?$/) { # sentry-on/off
    $sentry=$1//1;
  } elsif ($arg=~/^w([012])?$/) { # windows-closed/vent/open
    $windows_want=$1//0;
  } elsif ($arg=~/^([^0]\d*)?a$/i) {
    $amps=$1//-1;
  } elsif ($arg eq "dump") {
    $dump=1;
  } elsif ($arg eq "history") {
    $history=1;
  } elsif ($arg eq "-n") {
    $opt_n=1;
  } else {
    die "Unrecognized arg: $arg";
  }
}
die "No precondition time" if $precondition&&!defined $minutes_want_to;
$car=Tesla::Vehicle->new(auto_wake=>$auto_wake);
if ($history) {
  sub odo($) {
    my($t)=@_;
    my $fn=$ENV{"HOME"}."/c.dump/".strftime("%F",gmtime $t);
    local *F;
    open F,$fn or do { warn "$fn: $!" if $!!=ENOENT; return undef; };
    my $f=do { local $/; <F>; } or die "$fn";
    close F or die "$fn: $!";
    # 'odometer' => '18185.135925',
    my $r=($f=~/^\s*'odometer'\s*=>\s*'([\d.]+)',\s*$/m)[0] or die $f;
    return $r;
  }
  for my $p (@{$history=$car->charge_history()->{"charging_history_graph"}{"data_points"}}) {
    # CEST: %T=07:00:00
    my $daysec=24*60*60;
    my $t=$p->{"timestamp"}{"timestamp"}{"seconds"};
    print strftime("%F",gmtime $t)." ";
    #print $p->{"timestamp"}{"display_string"}." ";
    my @v;
    for my $v (@{$p->{"values"}}) {
      die Dumper $v if !defined $v->{"raw_value"}&&$v->{"value"}//-1!=0;
      push @v,$v->{"raw_value"}//0;
    }
    print Dumper \@v if @v!=4||$v[0]!=$v[1]||$v[2]||$v[3];
    my $whday=$v[0];
    my $miday0=odo $t-$daysec;
    my $miday1=odo $t;
    sub prec($;$) {
      my($n,$p)=@_;
      $p||=1;
      return int($n*$p+0.5)/$p;
    }
    if ($miday0&&$miday1&&$miday0!=$miday1) {
      my $miday=$miday1-$miday0;
      my $kmday=$miday*$MI_TO_KM;
      print "Wh/km=".prec($whday/$kmday)." Wh/mi=".prec($whday/$miday)." km=".prec($kmday,1000)." ";
    }
    print "kWh=".($whday/1000)." CZK=".prec($whday/1000*$KWH_TO_CZK,100)."\n";
  }
  exit 0;
}
print strftime("%T",localtime);
print " ".$car->name;
print " ".int($car->odometer*$MI_TO_KM+0.5)."km"; # POSIX::round not in perl-5.16.3-299.el7_9.x86_64
print " ".($car->state->{"car_version"}=~/^(\S+)/)[0];
print "\n";
cmd "battery_level";
state;
$cmd_ran=0;
print Dumper[$car->data,$car->charge_history()] if $dump;
my($sec,$min,$hour)=localtime;
my $minutes=$min+$hour*60;
$battery_want//=50 if $reset;
my $battery_done=$car->battery_level>=($battery_want||$car->charge_limit_soc);
$battery_want//=50 if $battery_done;
$battery_want//=$car->charge_limit_soc;
# Prevent false warning if Complete and $battery_want is going to set higher SoC.
if (!$battery_want&&$car->charging_state eq "Complete") {
  say "warning: Charging==Complete but SoC=".$car->battery_level." + 3 < $battery_want=want!" if $car->battery_level+3<$battery_want;
  $battery_done||=1;
}
$time_want//=$battery_want;
$minutes_want_to//=$minutes_want_from;
$sentry//=$lock;
$windows_want//=0 if $lock;
$amps  =$car->charge_current_request_max if $amps&&$amps==-1;
$amps||=$car->charge_current_request_max if $reset;
$amps||=$car->charge_current_request;
my $battery_level=$car->battery_level;
my $charging_state=$car->charging_state;
my $preconditioning=$car->preconditioning;
my $is_climate_on=$car->is_climate_on;
my $scheduled_charging=$car->scheduled_charging;
my $charge_limit_soc=$car->charge_limit_soc;
my $charge_current_request=$car->charge_current_request;
cmd "temperatures_set",$TEMPERATURE if ($car->temperature_setting_driver!=$TEMPERATURE||$car->temperature_setting_passenger!=$TEMPERATURE)
  &&($precondition||$conditioning||$reset);
if ($precondition) {
  cmd "preconditioning_set",$minutes_want_to if ($preconditioning//-1)!=$minutes_want_to;
  $preconditioning=$minutes_want_to;
} elsif ($reset||$is_climate_on||defined $minutes_want_to||defined $precondition) {
  cmd "preconditioning_set",undef if defined $preconditioning;
  $preconditioning=undef;
}
if ($amps) {
  cmd "charge_amps_set",$amps if $amps!=$charge_current_request;
  $charge_current_request=$amps;
}
say "warning: Calculating battery time with only ".phases."x${amps}A/".$car->charge_current_request_max."A!" if ($amps&&$amps!=$MINUTES_PER_PERCENT_AMPS)||phases!=$PHASES_DEFAULT;
my $MINUTES_PER_PERCENT_amps=$MINUTES_PER_PERCENT*($MINUTES_PER_PERCENT_AMPS*$PHASES_DEFAULT-$OVERHEAD_1PAMPS)/($amps*phases-$OVERHEAD_1PAMPS);
my    $time_minutes_fullamps;
my $battery_minutes_fullamps;
if ($amps!=$MINUTES_PER_PERCENT_AMPS||phases!=$PHASES_DEFAULT) {
     $time_minutes_fullamps=ceil((   $time_want-$battery_level)*$MINUTES_PER_PERCENT);
  $battery_minutes_fullamps=ceil(($battery_want-$battery_level)*$MINUTES_PER_PERCENT);
}
my    $time_minutes=ceil((   $time_want-$battery_level)*$MINUTES_PER_PERCENT_amps) if    $time_want&&!$battery_done;
my $battery_minutes=ceil(($battery_want-$battery_level)*$MINUTES_PER_PERCENT_amps) if $battery_want&&!$battery_done;
my $battery_minutes_car=$car->minutes_to_full_charge()||undef;
if ($battery_direct||(!defined $minutes_want_to&&($reset||$charging_state eq "Charging"))) {
  cmd "scheduled_charging_set",undef if defined $scheduled_charging;
  $scheduled_charging=undef;
} elsif (defined $minutes_want_to) {
  my $when=$minutes_want_from;
  if (!$when) {
    my $time_left=($minutes_want_to-$minutes)%(24*60);
    $time_left=0 if $time_left>=23*60;
    sub calcwhen($) {
      my($time_minutes)=@_;
      my $tolerance=5;
      return $time_left<$time_minutes+$tolerance?undef:($minutes_want_to-$time_minutes)%(24*60);
    }
    $when=calcwhen $time_minutes;
    if (!defined $when) {
      $battery_direct=1 if !defined $battery_direct;
      cmd "scheduled_charging_set",undef if defined $scheduled_charging;
      my $will_reach=$battery_level+floor($time_left/$MINUTES_PER_PERCENT_amps);
      my $msg="warning: The car will reach only $will_reach% instead of target $time_want%";
      if ($amps!=$MINUTES_PER_PERCENT_AMPS) {
	my $when_fullamps=calcwhen(($minutes_want_to-$minutes-$time_minutes)/($time_minutes_fullamps-$time_minutes)*$time_minutes_fullamps);
	my $will_reach_fullamps=$battery_level+floor($time_left/$MINUTES_PER_PERCENT);
	$msg.=" with ".phases."x${amps}A/".$car->charge_current_request_max."A! Switch to ".phases."x".$car->charge_current_request_max."A"
	  .(!defined $when_fullamps?" immediately to reach $will_reach_fullamps%":" at ".minutes_to_time($when_fullamps));
      }
      say $msg.".";
    }
  }
  if (defined $when) {
    cmd "scheduled_charging_set",$when if ($scheduled_charging//-1)!=$when;
  }
  $scheduled_charging=$when;
}
my $start=$scheduled_charging//$minutes;
if (defined $battery_minutes_car&&(!defined $battery_minutes||5<=abs($battery_minutes_car-$battery_minutes))) {
  say "Battery will".(defined $battery_minutes_fullamps?" ":"")
    ." get charged during ".minutes_to_time($start)." + ".minutes_to_time($battery_minutes_car     )
    ." = ".minutes_to_time(($start+   $battery_minutes_car  )%(24*60))
    ." according to the car.";
}
if ($time_want&&!$battery_done&&$charging_state ne "Disconnected") {
  say "Battery will".(defined $battery_minutes_fullamps?" ":"")
    ." get charged during ".minutes_to_time($start)." + ".minutes_to_time($battery_minutes         )
    .($time_minutes         <=$battery_minutes         ?"":" + ".minutes_to_time($time_minutes         -$battery_minutes         ))
    ." = ".minutes_to_time(($start+   $time_minutes         )%(24*60))
    .($time_minutes         >=$battery_minutes         ?"":" + ".minutes_to_time($battery_minutes      -$time_minutes            ))
    .".";
  say "Battery would"
    ." get charged during ".minutes_to_time($start)." + ".minutes_to_time($battery_minutes_fullamps)
    .($time_minutes_fullamps==$battery_minutes_fullamps?"":" + ".minutes_to_time($time_minutes_fullamps-$battery_minutes_fullamps))
    ." = ".minutes_to_time(($start+$battery_minutes_fullamps)%(24*60))
    ." at 3x".$MINUTES_PER_PERCENT_AMPS."A." if defined $battery_minutes_fullamps;
}
say "warning: Charging is stopped, use 'b' to resume it!" if !$battery_direct&&$charging_state eq "Stopped"&&!defined $scheduled_charging;
say "warning: Battery may get charged up to ".($battery_want+3)."%!" if $battery_want&&$battery_want>87&&$battery_want<=90;
cmd "charge_limit_set",$battery_want//50 if $battery_want&&$battery_want!=$charge_limit_soc; # charge_limit_set only after scheduled_charging_set!
$windows_want=0 if !defined $windows_want&&($conditioning||(defined $preconditioning&&defined $preconditioning&&($preconditioning-$minutes)%(24*60)<3*60));
if (($windows//-3)!=($windows_want//$windows//-3)) {
  if (($windows_want//-2)==2) {
    say "There is no way to open windows!";
  } else {
    cmd "windows_set",$windows_want;
    # 0-1: Windows are venting, venting, closed, closed.
    # 2- : Windows are all closed.
    sleep 2;
  }
}
cmd "climate_".($conditioning?"on":"off") if defined $conditioning||($reset&&$is_climate_on);
cmd "charge_" .($battery_direct?"on":"off") if defined $battery_direct;
cmd "doors_".($lock?"lock":"unlock") if defined $lock;
cmd "sentry_".($sentry?"on":"off") if defined $sentry;
state if $cmd_ran;
