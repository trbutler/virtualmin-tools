#!/usr/bin/perl

use strict;
use warnings;
use Apache::ConfigFile;
use Template;
use Getopt::Long;

my ($target, $create, $delete, $test, $modification);

GetOptions ("target|t=s" 			=> \$target,
			"create|modify|c|m"     => \$create,
            "delete|d"              => \$delete,
            "test"                  => \$test );

# Do we have settings from Virtualmin?
if ($ENV{'VIRTUALSERVER_ACTION'}) {
    $delete //= (any { $_ eq $ENV{'VIRTUALSERVER_ACTION'} } [ 'DELETE_DOMAIN', 'DISABLE_DOMAIN' ]) ? 1 : 0;
    $create //= (any { $_ eq $ENV{'VIRTUALSERVER_ACTION'} } [ 'CREATE_DOMAIN', 'MODIFY_DOMAIN', 'CLONE_DOMAIN', 'ENABLE_DOMAIN' ]) ? 1 : 0;

    $target //= $ENV{'VIRTUALSERVER_DOM'};
}

say STDERR "Target: $target; Create: $create; Delete: $delete; Test: $test";

# If we don't have options set, output help description of options and exit.
unless ($target and ($create or $delete)) {
    say STDOUT "Usage: syncNginxProxy.pl --target <target> [--create|--delete|--test]";
    say STDOUT "  --target <target>  The target configuration file to create or delete.";
    say STDOUT "  --create           Create or modify the target configuration file.";
    say STDOUT "  --delete           Delete the target configuration file.";
    say STDOUT "  --test             Test the target configuration file.";
    exit;
}

# Require a target.
die "No target specified" unless $target;

# See if file exists.
unless (-e '/etc/apache2/sites-available/' . $target . '.conf') {
    die "Configuration file doesn't exist.";
}

if ($create) {
    # Open the Apache configuration file for reading
    my $parameters = {};
    $parameters->{'TargetConfig'} = $target;

    # Use the Apache::ConfigFile module to parse the Apache configuration file
    my $apacheConfig = Apache::ConfigFile->read('/etc/apache2/sites-available/' . $parameters->{'TargetConfig'} . '.conf');

    for my $vh ($apacheConfig->cmd_context('VirtualHost')) {
        my $vhost = $apacheConfig->cmd_context('VirtualHost' => $vh);
        
        # Collect virtual domains
        my @serverNames = $vhost->cmd_config('ServerAlias');
        push (@serverNames, $vhost->cmd_config('ServerName'));
        $parameters->{'server_name'} = join(' ', @serverNames);
        $parameters->{'root'} = $vhost->cmd_config('DocumentRoot');

        # SSL Parameters
        $parameters->{'ssl_certificate'} = $vhost->cmd_config('SSLCertificateFile');
        $parameters->{'ssl_certificate_key'} = $vhost->cmd_config('SSLCertificateKeyFile');

        # foreach (@serverNames) {
        #     print $_ . "\n";
        # }

    # my $vhost_server_name = $vh->cmd_config('ServerName');
    # my $vhost_doc_root    = $vh->cmd_config('DocumentRoot');
    } 

    # Produce template
    my $template = Template->new();
    my $output;

    if ($test) {
        $template->process('nginxProxyTemplate.tt', $parameters, \$output) || die $template->error();
        say STDOUT $output;
        exit;
    } else {
        $template->process('nginxProxyTemplate.tt', $parameters, '/etc/nginx/sites-available/' . $parameters->{'TargetConfig'}) || die $template->error();
        say STDOUT "Nginx configuration file created or modified successfully.";
        $modification = 1;
    }
}

if ($delete) {
    if ($test) {
        say STDOUT "Nginx configuration file would be deleted successfully.";
        exit;
    }
    else {
        unlink '/etc/nginx/sites-available/' . $target;
        say STDOUT "Nginx configuration file deleted successfully.";
        $modification = 1;
    }
}

# See if we need to restart NGINX
if ($modification) {
    my $result = system('service nginx restart');

    if ($result == 0) {
        say STDOUT "NGINX restarted successfully.";
    } else {
        say STDOUT "Failed to restart NGINX.";
    }
}