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
say STDERR "Proxy control mode: $proxyControlMode";
if ($proxyControlMode) {
    &proxyControl($proxyControlMode);
    exit;
}

# Rebuild all NGINX configuration files by removing all existing NGINX configuration files.
if ($rebuild) {
    my $directoryTargets = [ '/etc/nginx/sites-enabled/', '/etc/nginx/sites-available/' ];

    say STDOUT "Removing existing NGINX configuration files.";
    
    foreach (@{ $directoryTargets }) {
        opendir(DIR, $_) or die $!;
        while (my $file = readdir(DIR)) {
            $target = $file =~ s/\.conf$//r;
            &delete($target);
        }
        closedir(DIR);
    }

    $targetAll = 1;
    $create = 1;
}

if ($clearCache) {
    say STDOUT "Clearing NGINX proxy cache.";
    &clearProxy($target);
    exit;
}

# Synchronize all NGINX configuration files by running create subroutine over and over.
if ($targetAll) {
    opendir(DIR, '/etc/apache2/sites-enabled/') or die $!;
    while (my $file = readdir(DIR)) {
        next if ($file eq '.' or $file eq '..');
        $target = $file =~ s/\.conf$//r;
        &create($target);
    }
    closedir(DIR);
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
unless ($target and ($create or $delete or $test)) {
    say STDOUT "Usage: syncNginxProxy.pl --target <target> [--create|--delete|--test|--clear-cache|]";
    say STDOUT "  --target  -t <target>  The target configuration file to create or delete.";
    say STDOUT "  --target-all -a        Create an NGINX configuration file for all Apache configuration files.";
    say STDOUT "  --rebuild  -r          Remove existing NGINX site configurations and then run target all.";
    say STDOUT "  --create  -c           Create or modify the target configuration file.";
    say STDOUT "  --delete  -d           Delete the target configuration file.";
    say STDOUT "  --no-ssl  -u           Disable SSL on host even if certificate exists.";
    say STDOUT "  --test                 Test the target configuration file.";
    say STDOUT "  --clear-cache -x        Clear the NGINX proxy cache for the target.";
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

if ($create) {
    $modification //= &create($target);
}
elsif ($delete) {
    $modification //= &delete($target);
}

# See if we need to restart NGINX
if ($modification) {
    # Clear Proxy Cache
    my $deleteResult = &clearProxy($target);

    # Restart NGINX
    my $result = system('service nginx restart');

    if ($result == 0) {
        say STDOUT "NGINX restarted successfully.";
    } else {
        say STDOUT "Failed to restart NGINX.";
    }
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

        say STDOUT "Nginx configuration file deleted successfully.";
        return 0;
    }
}

sub clearProxy {
    my $target = shift;
    return system('rm -rf /var/cache/nginx/proxy/' . $target . '/*');
}

sub proxyControl {
    my $state = shift;
    my $presentState = ($state eq 'enable') ? 'disable' : 'enable';
    my $ports = { 'enable' => 81, 'disable' => 80 };
    my $SSLports = { 'enable' => 444, 'disable' => 443 };
 
    # Open the Apache listen configuration file for reading
    my $apacheConfig = Apache::ConfigFile->read('/etc/apache2/ports.conf');

    # Get all Listen directives
    my @listen_directives = $apacheConfig->cmd_config("Listen");

    # Print all Listen directives
    foreach my $directive (@listen_directives) {
        print "Listen directive: $directive\n";
    }
    exit;

    # Replace 80 with 81, 443 with 444 in the file

}