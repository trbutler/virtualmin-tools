#!/usr/bin/perl

use strict;
use warnings;

# Open the Apache configuration file for reading
my $apacheFile = shift @ARGV;

# Use the Apache::ConfigFile module to parse the Apache configuration file
use Apache::ConfigFile;
my $apacheConfig = Apache::ConfigFile->read('/etc/apache2/sites-available/' . $apacheFile . '.conf');

use Data::Dumper;

for my $vh ($apacheConfig->cmd_context('VirtualHost')) {
    my $vhost = $apacheConfig->cmd_context('VirtualHost' => $vh);
    print $vhost->cmd_config('ServerName');
    
    # Collect virtual domains
    for my $vhost ($apacheConfig->cmd_context('ServerName')) {
        print $vhost . "\n";
    }

   # my $vhost_server_name = $vh->cmd_config('ServerName');
   # my $vhost_doc_root    = $vh->cmd_config('DocumentRoot');
} 

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