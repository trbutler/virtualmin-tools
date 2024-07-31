# virtualmin-tools
Tools to extend Virtualmin for easing migration from cPanel/WHM

## syncNginxProxy.pl
This tool is designed to be run every time Virtualmin modifies or creates a server in order to keep NGINX updated as a reverse proxy. It can also be run manually to recreate one or all proxy records for NGINX.

The script accepts the following command-line options for direct operation:

### Setup Modes
- `--enable-proxy`:  Enable this tool's proxying setup.
- `--disable-proxy`: Enable this tool's proxying setup.

### Operational Modes
*These options require `--target` to be specified in order to operate.*

- `--target <target>` or `-t <target>`: Specifies the target configuration file to create or delete.
- `--create` or `-c`: Creates or modifies the target configuration file.
- `--delete` or `-d`: Deletes the target configuration file.
- `--no-ssl` or `-u`: Disables SSL on the host even if a certificate exists.
- `--test`: Tests the target configuration file.

### Bulk Operational Modes
*Note: these options do not take a target, rather they apply to all virtual hosts.*

- `--target-all` or `-a`: Creates an NGINX configuration file for all Apache configuration files.
- `--rebuild` or `-r`: Removes existing NGINX site configurations and then runs the equivalent of `--target-all`.


To enable automatic operation in Virtualmin upon creation or modification of a server, syncNginxProxy can be invoked from "Virtualmin Configuration" --> "Actions upon server and user configuration" --> "Command to run after making changes to a server."

The command to enter into that box will vary depending on where you pulled this repository to. For example, if you placed the repository in `/opt/`, the path would be `/opt/virtualmin-tools/syncNginxProxy.pl`. 

## Recommended System 

- Debian 12 ("Bookworm") - the tool may work out of the box with other distributions using similar configuration file layout, but has only been tested with Debian. Further distribution support should be added in the future.

- Virtualmin with LAMP install - if you intend to use the tool with Virtualmin, start with the LAMP version of Virtualmin, not the LEMP version. 

- NGINX installed directly from the distribution after Virtualmin installation.

## Apache and NGINX configuration

- Install NGINX on your server

    - Add `include /etc/nginx/upstreamConfig/*;` to your NGINX http block in `/etc/nginx/nginx.conf`.

- Run `syncNginxProxy.pl --enable-proxy` to initialize configuration, including moving Apache to private ports accessible to NGINX, but not to the public. *Note: if you are already using non-standard ports, you must complete this step manually instead, see "Manually Apache Configuration" below.*

- Under Virtualmin -> Server Templates -> Default Settings -> Website for domain, modify "Port number for virtual hosts" to 81 and "Port number for SSL virtual hosts" to 444.

## Manual Apache Configuration

You should ordinarily use `syncNginxProxy.pl --enable-proxy` to accomplish the following, but if there are non-standard configuration elements hindering the automated process, here are the steps for preparing Apache for the proxy configuration:

- Adjust Apache to listen on ports 81 and 444 by replacing the `Listen` directives in `/etc/apache2/ports.conf` for 80 and 443 to 81 and 444, respectively. (These ports should **not** be opened on your firewall, these are purely for NGINX to access).

- In each existing virtual host configuration in `/etc/apache2/sites-available`, modify the `<VirtualHost>` directives, changing port 80 to 81 and 443 to 444.

- Restart Apache using `systemctl restart apache2`.

- Build the NGINX proxy configuration for all sites using `syncNginxProxy.pl -a`.

- Start NGINX using `systemctl start nginx`. 

- Enable NGINX for subsequent reboots by typing `systemctl enable nginx`.

## Templates
Configuration for each virtual server is handled by a series of templates in the `templates/` directory. Further, standard configuration settings are in the `includes/` directory, including optimizations for serving certain static content (such as images) directly via NGINX rather than proxying to Apache.

### Per-Site Configuration
The default template looks in `/etc/nginx/sites-enabled/[server name]/` for any `.conf` files that coudl be included. One should expect the main configuration for each virtual server (e.g. `/etc/nginx/sites-enabled/[server name].conf`) will be overwritten on a regular basis, so site specific changes not appropriate for changing the global templates, should go in files placed in that subdirectory.

### Image Optimizations
You can further optimize image serving using these standard templates by placing your site's images into an `images` subdirectory and alternate, optimized image forms within `images/.optimized` directory. If a WebP or more highly optimized JPEG image is placed into that latter directory with the requested image's name *plus* the appropriate extension, NGINX will serve the optimized version to compatible clients.

For example: if the user requests `/images/logo.gif` and `/images/.optimized/logo.gif.webp` exists, the server will provide the latter to any client that supports WebP. 

Using a script to regularly scan `/images/` directories and create the optimized forms in that hidden subfolder is an efficient way to utilize this functionality. Such a script may be included in a future version of this tool distribution and is included in the upcoming rerelease of our free and open source CMS platform.

## Errata 

- The script does not yet respond to being invoked specifically for alias modification. It does seem to be updating as the parent server is changed to reflect alias modifications, so perhaps adding it to "Command to run after making changes to an alias" is unnecessary?

- A function to completely disable the proxy when trying to create SSL certificates from Let's Encrypt may be necessary. Still trying to determine if this is necessary.

- The cache key setting may need to be tweaked.

- The Virtualmin webapp installer and other parts of the interface link to the ports (that should be inaccessible externally) 81 and 444, rather than the proxied ports 80 and 443.

## Donations

Is this tool helpful to you? It is free to use, but if you'd like to say "thank you" and support further development, sending a few bucks to @faithtree on Venmo, timothy.butler@faithtree.com on PayPal, or [making a donation on the FaithTree web site](https://faithtree.com/sa805) is deeply appreciated. Anything you send will be tax deductible in the United States as a gift to FaithTree Christian Fellowship, Inc., an IRS 501(c)(3) non-profit organization.

## License

Copyright (C) 2024 Universal Networks, LLC. This program comes with ABSOLUTELY NO WARRANTY; for details see the file LICENSE. This is free software, and you are welcome to redistribute it under the conditions in the LICENSE file.