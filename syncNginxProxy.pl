#!/usr/bin/perl
# syncNginxProxy -- a tool for manual or Virtualmin automated 
#      NGINX proxy configuration synchronization with Apache.
#
# Copyright (C) 2024 Universal Networks, LLC.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;
use Apache::ConfigFile;
use Template;
use Getopt::Long;
use List::Util qw(any);
use FindBin qw($Bin);
use File::Path qw(make_path);

my $apachePath = {
    'sitesAvailable' => '/etc/apache2/sites-available/',
    'sitesEnabled' => '/etc/apache2/sites-enabled/'
};

my ($enableProxy, $disableProxy, $target, $parentTarget, $targetAll, $rebuild, $clearCache, $create, $delete, $noSSL, $test, $modification, $ipsInUse);

GetOptions ("enable-proxy" 			=> \$enableProxy,
            "disable-proxy" 		=> \$disableProxy,
            "target|t=s" 			=> \$target,
            "target-all|a"          => \$targetAll,
            "rebuild|r"             => \$rebuild,
            "clear-cache|x"         => \$clearCache,
			"create|modify|c|m"     => \$create,
            "delete|d"              => \$delete,
            "no-ssl|u"              => \$noSSL,           
            "test"                  => \$test );

# Add GPL commandline summary.
say STDOUT "syncNginxProxy - Copyright (C) 2024 Universal Networks, LLC. <https://uninetsolutions.com>";
say STDOUT "This program comes with ABSOLUTELY NO WARRANTY. You may redistribute it under the terms of the GNU GPL v. 3.\n";

# Enable or disable proxy.
my $proxyControlMode = ($enableProxy) ? 'enable' : ($disableProxy) ? 'disable' : '';
if ($proxyControlMode) {
    &proxyControl($proxyControlMode, $test);
    exit;
}

if ($clearCache) {
    say STDOUT "Clearing NGINX proxy cache.";
    &clearProxyCache($target);
    exit;
}

# Rebuild all NGINX configuration files by removing all existing NGINX configuration files.
if ($rebuild) {
    &deleteAll;
    $targetAll = 1;
    $create = 1;
}

# Synchronize all NGINX configuration files by running create subroutine over and over.
if ($targetAll) {
    &createAll;
    exit;
}

# Do we have settings from Virtualmin?
if ($ENV{'VIRTUALSERVER_ACTION'}) {
    $delete //= (any { $_ eq $ENV{'VIRTUALSERVER_ACTION'} } qw(DELETE_DOMAIN DISABLE_DOMAIN)) ? 1 : 0;
    $create //= (any { $_ eq $ENV{'VIRTUALSERVER_ACTION'} } qw(CREATE_DOMAIN MODIFY_DOMAIN CLONE_DOMAIN ENABLE_DOMAIN SSL_DOMAIN)) ? 1 : 0;
    $target //= $ENV{'VIRTUALSERVER_DOM'};
    $parentTarget //= $ENV{'PARENT_DOMAIN_DOM'};
}

# If we don't have options set, output help description of options and exit.
unless ($target and ($create or $delete)) {
    say STDOUT "Usage: syncNginxProxy.pl --target <target> [--create|--delete|--test|--clear-cache|]";
    say STDOUT "\nOperational Modes (requires --target):";
    say STDOUT "  --target  -t <target>  The target configuration file to create or delete.";
    say STDOUT "  --create  -c           Create or modify the target configuration file.";
    say STDOUT "  --delete  -d           Delete the target configuration file.";
    say STDOUT "  --no-ssl  -u           Disable SSL on host even if certificate exists.";
    say STDOUT "  --test                 Test the target configuration file.";
    say STDOUT "  --clear-cache -x       Clear the NGINX proxy cache for the target.";
    say STDOUT "\nBulk Operations:";
    say STDOUT "  --target-all -a        Create an NGINX configuration file for all Apache configuration files.";
    say STDOUT "  --rebuild  -r          Remove existing NGINX site configurations and then run target all.";
    say STDOUT "\nProxy Control:";
    say STDOUT "  --enable-proxy         Enable NGINX proxy mode.";
    say STDOUT "  --disable-proxy        Disable NGINX proxy mode.";
    exit;
}

# Require a target.
die "No target specified" unless $target;

# See if file exists.
unless (-e '/etc/apache2/sites-available/' . $target . '.conf') {
    # Do we have a parent target?
    if ($parentTarget) {
        $target = $parentTarget;
        if (-e '/etc/apache2/sites-available/' . $target . '.conf') {
            say STDOUT "Using parent server as target: " . $target;
        }
        else {
            die 'Configuration files for ' . $target . ' and ' . $parentTarget . " don't exist.";
        }
    } 
    else {
        die 'Configuration file for ' . $target . " doesn't exist.";
    }
}

# Core operations.
if ($create) {
    $modification //= &create($target);
}
elsif ($delete) {
    $modification //= &delete($target);
}

# See if we need to restart NGINX
if ($modification) {
    # Clear Proxy Cache
    my $deleteResult = &clearProxyCache($target);

    # Restart NGINX
    &nginxControl('restart');
}

sub create {
    my $target = shift;

    # Open the Apache configuration file for reading
    my $parameters = {};
    $parameters->{'TargetConfig'} = $target;
    $parameters->{'programPath'} = $Bin;

    # Use the Apache::ConfigFile module to parse the Apache configuration file
    my $apacheConfig = Apache::ConfigFile->read('/etc/apache2/sites-enabled/' . $parameters->{'TargetConfig'} . '.conf');

    for my $vh ($apacheConfig->cmd_context('VirtualHost')) {
        $parameters->{'ip'} //= $vh =~ s/:[0-9]+$//r;
        $parameters->{'ipUnderscore'} //= $parameters->{'ip'} =~ s/\./_/gr;
        my $vhost = $apacheConfig->cmd_context('VirtualHost' => $vh);

        # Collect virtual domains
        my @serverNamesArray = $vhost->cmd_config_array('ServerAlias');
        my @serverNames = map { $_->[0] } @serverNamesArray;
        push (@serverNames, $vhost->cmd_config('ServerName'));
        $parameters->{'server_name'} = join(' ', @serverNames);
        $parameters->{'root'} = $vhost->cmd_config('DocumentRoot');

        # SSL Parameters
        unless ($noSSL) {
            $parameters->{'ssl_certificate'} //= $vhost->cmd_config('SSLCertificateFile');
            $parameters->{'ssl_certificate_key'} //= $vhost->cmd_config('SSLCertificateKeyFile');
        }
    } 

    # Produce template
    my $template = Template->new( INCLUDE_PATH => $Bin );
    my $output;

    # Make sure cache directory exists
    my $cachePath = '/var/cache/nginx/proxy/' . $parameters->{'TargetConfig'};
    unless (-d $cachePath) {
        make_path($cachePath) or die "Failed to create path: $cachePath";
    } 

    if ($test) {
        $template->process('nginxProxyTemplate.tt', $parameters, \$output) || die $template->error();
        say STDOUT $output;
        return 0;
    } else {
        # Main template
        $template->process('nginxProxyTemplate.tt', $parameters, '/etc/nginx/sites-available/' . $parameters->{'TargetConfig'} . '.conf') || die $template->error();
        say STDOUT "Nginx configuration file created or modified successfully.";

        # Create symbolic link
        symlink '/etc/nginx/sites-available/' . $parameters->{'TargetConfig'} . '.conf', '/etc/nginx/sites-enabled/' . $parameters->{'TargetConfig'} . '.conf';

        # Save IP proxy config template.
        unless ($ipsInUse->{ $parameters->{'ip'} }) {
            $ipsInUse->{ $parameters->{'ip'} } = 1;
        
            # does the proxy upstream config directory exist?
            my $upstreamConfigPath = '/etc/nginx/upstreamConfig/';
            unless (-d $upstreamConfigPath) {
                make_path($upstreamConfigPath) or die "Failed to create path: $upstreamConfigPath";
            }

            $template->process('nginxProxyUpstreamTemplate.tt', $parameters, $upstreamConfigPath . $parameters->{'ipUnderscore'}) || die $template->error();
        }

        return 1;
    }
}

sub delete {
    my $target = shift;

    if (!-e '/etc/nginx/sites-available/' . $target . '.conf') {
        say STDOUT "Nginx configuration file doesn't exist.";
        return 0;
    }
    elsif ($test) {
        say STDOUT "Nginx configuration file would be deleted successfully.";
        return 0;
    }
    else {
        unlink '/etc/nginx/sites-available/' . $target . '.conf';

        # Delete symbolic link, too.
        if (-e '/etc/nginx/sites-enabled/' . $target . '.conf') {
            unlink '/etc/nginx/sites-enabled/' . $target . '.conf';
        }

        # Remove cache
        &clearProxyCache($target);

        say STDOUT "Nginx configuration file deleted successfully.";
        return 0;
    }
}

sub proxyControl {
    my ($targetState, $test) = @_;
    my $ports = { 'enable' => 81, 'disable' => 80 };
    my $SSLports = { 'enable' => 444, 'disable' => 443 };
    my $targetFile = '/etc/apache2/ports.conf';
 
    # Open the Apache listen configuration file for reading
    my $apacheConfig = Apache::ConfigFile->read($targetFile);

    # Get all Listen directives
    my @listen_directives = $apacheConfig->cmd_config_array("Listen");

    # Test current configuration.
    my $currentlyEnabled = 0;
    my $currentlyDisabled = 0;   
    foreach my $directive (@listen_directives) {
        $currentlyEnabled = 1 if ($directive->[0] =~ /(?:\:|^)(?:81|444)/);
        $currentlyDisabled = 1 if ($directive->[0] =~ /(?:\:|^)(?:80|443)/);
    }

    # If we find both port sets enabled, at least in part, we can't proceed automatically.
    if (($currentlyEnabled and $currentlyDisabled) or (! $currentlyEnabled and ! $currentlyDisabled)) {
        say STDOUT "A mix of proxy port modes are currently enabled. Unable to proceed with automatic proxy configuration.";
        exit;
    }

    # Does present state match requested state?
    my $presentState = ($currentlyEnabled) ? 'enable' : 'disable';   
    if ($targetState eq $presentState) {
        say STDOUT 'Proxy mode is already ' . $targetState . 'd.';
        exit;
    }

    # Create array list of all sites-available from Apache
    opendir(DIR, $apachePath->{'sitesAvailable'}) or die $!;
    my @configurationFilesToUpdate = grep { !/^\./ } readdir(DIR);
    closedir(DIR);

    push (@configurationFilesToUpdate, $targetFile);

    # Modify files.
    foreach my $file (@configurationFilesToUpdate) {
        # Add path if not present.
        $file = $apachePath->{'sitesAvailable'} . $file unless ($file =~ /\//);

        #make Update.
        &updatePort($file, $presentState, $targetState, $ports, $SSLports);
    }

    # Prevent restart of services, etc., if we're in test mode.
    return 1 if ($test);

    # Either disable or enable nginx
    say STDOUT "Proxy mode is being " . $targetState . 'd.';
    if ($targetState eq 'enable') {
        # Clean out any existing NGINX configuration files and build new ones.
        &deleteAll;
        &createAll;

        # Restart processes in proper order.
        system('systemctl restart apache2');
        &nginxControl('enable');
    } 
    else {
        # Stop NGINX and disable it, then return Apache to normal ports.
        &nginxControl('disable');
        system('systemctl restart apache2');
    }

}

sub updatePort {
    my ($targetFile, $presentState, $targetState, $ports, $SSLports) = @_;

    open (my $fh, '+<', $targetFile) or die "Could not open file '$targetFile' $!";
    my $fileContent = do { local $/; <$fh> };
    $fileContent =~ s/((?:Listen|<VirtualHost).*?(?:\:|\b))($ports->{$presentState}|$SSLports->{$presentState})/($2 eq $ports->{$presentState}) ? $1 . $ports->{$targetState} : $1 . $SSLports->{$targetState}/ge;

    if ($test) {
        print "\n\n-----\n\n"  . $fileContent;
    }
    else {
        seek($fh, 0, 0);
        print $fh $fileContent;
        truncate($fh, tell($fh));
    }

    close($fh);
}

# Maintenance 
sub clearProxyCache {
    my $target = shift;
    system('rm -rf /var/cache/nginx/proxy/' . $target . '/*');
    if ($?) {
        &nginxControl('restart');
        return 1;
    } else {
        return 0;
    }

}

sub nginxControl {
    my $command = shift;

    # Check to make sure command is start, stop, or restart.
    if ($command !~ /^(start|stop|restart|reload|disable|enable)$/) {
        say STDOUT "Invalid command requested for NGINX server. Must be start, stop, restart, reload, disable or enable.";
        return 0;
    }

    system('systemctl ' . $command . ' nginx');

    if ($?) {
        $command = ($command eq 'stop') ? 'stopp' : $command;
        say STDOUT "NGINX " . $command . "ed successfully.";

        # For enable/disable also start or stop the service if needed.
        if ($command =~ /^(enable|disable)$/) {
            # Check to see if nginx is running
            my $nginxStatus = `systemctl is-active nginx`;
            
            if (($nginxStatus eq 'active') and ($command eq 'disable')) {
                &nginxControl('stop');
            }
            elsif (($nginxStatus eq 'inactive') and ($command eq 'enable')) {
                &nginxControl('start');
            }
        }

        return 1;
    } 
    else {
        say STDOUT "Failed to " . $command . " NGINX.";
        return 0;
    }
}

# Bulk Subroutines
sub createAll {
    my $directoryTargets = [ '/etc/apache2/sites-enabled/' ];
    &bulkModify($directoryTargets, \&create);
}

sub deleteAll {
    my $directoryTargets = [ '/etc/nginx/sites-enabled/', '/etc/nginx/sites-available/' ];
    &bulkModify($directoryTargets, \&delete);
}

sub bulkModify {
    my $directoryTargets = shift;
    my $subroutine = shift;

    foreach (@{ $directoryTargets }) {
        opendir(DIR, $_) or die $!;
        while (my $file = readdir(DIR)) {
            next if ($file eq '.' or $file eq '..');
            $target = $file =~ s/\.conf$//r;
            &$subroutine($target);
        }
        closedir(DIR);
    }
}