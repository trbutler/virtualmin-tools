#!/usr/bin/perl

use strict;
use warnings;
use Apache::ConfigFile;
use Template;

# Open the Apache configuration file for reading
my $parameters = {};
$parameters->{'VirtualminServer'} = shift @ARGV;

# Use the Apache::ConfigFile module to parse the Apache configuration file
my $apacheConfig = Apache::ConfigFile->read('/etc/apache2/sites-available/' . $parameters->{'VirtualminServer'} . '.conf');

use Data::Dumper;

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
$template->process('conditional.tt', $parameters, \$output) || die $template->error();

print $output;

# # Access the parameters in the Apache configuration file
# my $hostname = $apacheConfig->cmd_config('ServerName');
# my $doc_root = $apacheConfig->cmd_config('DocumentRoot');

# my $directive = $config->directive;
# my $value = $config->value;

# # Perform your conversion logic using the directive and value variables

# # Example conversion logic: Convert "Listen" directive to "listen" directive
# if ($directive eq 'Listen') {
#     $directive = 'listen';
# }




# # Open the NGINX configuration file for writing
# open(my $nginx_fh, '>', 'nginx.conf') or die "Failed to open NGINX configuration file: $!";

#     # Write the converted line to the NGINX configuration file
#     print $nginx_fh "$directive $value;\n";

#     # Write the converted line to the NGINX configuration file
#     print $nginx_fh $line;
# }

# # Close the file handles
# close($nginx_fh);

# print "Conversion completed successfully!\n";