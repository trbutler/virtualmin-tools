# virtualmin-tools
Tools to extend Virtualmin for easing migration from cPanel/WHM

## syncNginxProxy.pl
This tool is designed to be run every time Virtualmin modifies or creates a server in order to keep NGINX updated as a reverse proxy. It can also be run manually to recreate one or all proxy records for NGINX.

The script accepts the following command-line options for direct operation:

- `--enable-proxy` 
- `--target <target>` or `-t <target>`: Specifies the target configuration file to create or delete.
- `--target-all` or `-a`: Creates an NGINX configuration file for all Apache configuration files.
- `--rebuild` or `-r`: Removes existing NGINX site configurations and then runs the equivalent of `--target-all`.
- `--create` or `-c`: Creates or modifies the target configuration file.
- `--delete` or `-d`: Deletes the target configuration file.
- `--no-ssl` or `-u`: Disables SSL on the host even if a certificate exists.
- `--test`: Tests the target configuration file.

To enable automatic operation in Virtualmin upon creation or modification of a server, syncNginxProxy can be invoked from "Virtualmin Configuration" --> "Actions upon server and user configuration" --> "Command to run after making changes to a server."

The command to enter into that box will vary depending on where you pulled this repository to. For example, if you placed the repository in `/opt/`, the path would be `/opt/virtualmin-tools/syncNginxProxy.pl`. 

## Apache and NGINX configuration

- Install NGINX on your server

    - Add `include /etc/nginx/upstreamConfig/*;` to your NGINX http block in `/etc/nginx/nginx.conf`.

- Adjust Apache to list on ports 81 and 444 (these ports should **not** be opened on your firewall, these are purely for NGINX to access).

- Under Virtualmin -> Server Templates -> Default Settings -> Website for domain, modify "Port number for virtual hosts" to 81 and "Port number for SSL virtual hosts" to 444.

## Errata 

- The script does not yet respond to being invoked specifically for alias modification. It does seem to be updating as the parent server is changed to reflect alias modifications, so perhaps adding it to "Command to run after making changes to an alias" is unnecessary?

- A function to completely disable the proxy when trying to create SSL certificates from Let's Encrypt may be necessary. Still trying to determine if this is necessary.

- The cache key setting may need to be tweaked.

- The Virtualmin webapp installer and other parts of the interface link to the ports (that should be inaccessible externally) 81 and 444, rather than the proxied ports 80 and 443.

## Donations

Is this tool helpful to you? It is free to use, but a donation to the non-profit I serve at, which is also the primary user that makes development of this script possible, FaithTree Christian Fellowship, Inc., is certainly appreciated. FaithTree is a 501(C)(3) organization and donations are tax deductable in the United States. You can donate here: https://faithtree.com/sa805 . Thank you!

## License

Copyright (C) 2004 Universal Networks, LLC. This program comes with ABSOLUTELY NO WARRANTY; for details see the file LICENSE. This is free software, and you are welcome to redistribute it under the conditions in the LICENSE file.