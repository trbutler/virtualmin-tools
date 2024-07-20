#!/usr/bin/perl

use strict;
use warnings;
use Apache::ConfigFile;
use Template;
use Getopt::Long;
use List::Util qw(any);
use FindBin qw($Bin);
use File::Path qw(make_path);

my ($target, $targetAll, $rebuild, $create, $delete, $noSSL, $test, $modification, $ipsInUse);

GetOptions ("target|t=s" 			=> \$target,
            "target-all|a"          => \$targetAll,
            "rebuild|r"             => \$rebuild,
			"create|modify|c|m"     => \$create,
            "delete|d"              => \$delete,
            "no-ssl|u"              => \$noSSL,           
            "test"                  => \$test );

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
}

# If we don't have options set, output help description of options and exit.
unless ($target and ($create or $delete)) {
    say STDOUT "Usage: syncNginxProxy.pl --target <target> [--create|--delete|--test]";
    say STDOUT "  --target  -t <target>  The target configuration file to create or delete.";
    say STDOUT "  --target-all -a        Create an NGINX configuration file for all Apache configuration files.";
    say STDOUT "  --rebuild  -r          Remove existing NGINX site configurations and then run target all.";
    say STDOUT "  --create  -c           Create or modify the target configuration file.";
    say STDOUT "  --delete  -d           Delete the target configuration file.";
    say STDOUT "  --no-ssl  -u           Disable SSL on host even if certificate exists.";
    say STDOUT "  --test                 Test the target configuration file.";
    exit;
}

# Require a target.
die "No target specified" unless $target;

# See if file exists.
unless (-e '/etc/apache2/sites-available/' . $target . '.conf') {
    die "Configuration file doesn't exist.";
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
    my $deleteResult = system('rm -rf /var/cache/nginx/proxy/' . $target . '/');

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
        $template->process('nginxProxyTemplate.tt', $parameters, '/etc/nginx/sites-available/' . $parameters->{'TargetConfig'}) . '.conf' || die $template->error();
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