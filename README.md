To solve public/community RPC availability issues we've built a type of "Layer 2 RPC Stable Access Point" with integrated health-checks.

Current location is at https://publicnexus.xdcchain.xyz

Publicnexus is essentially a load-balancer with all known public RPCs on XDC network set as its origin/backend servers.

It checks each RPC's block height basically in parallel once per minute. If no response, or wrong response, or if the block height is greater than 4 blocks behind highest-block-height result from the cycle, then that RPC is removed from the list of origin/backend servers and no further RPC traffic will be directed there. (So max exposure time to any problematic RPC should be about 1 minute before Publicnexus fixes itself).

Conversely, if an RPC improves to meet criteria again, then it gets re-added to the list of origin/backend servers and will once again commence receiving RPC traffic.

We've added in a throttling mechanism for each IP that accesses it so commercial projects that will need higher transaction throughput won't be able to use it (as they should probably run their own private RPC). That way it is specifically for public/community use as the allowed-rate-per-IP will be adequate for them.

The various rate-limit / throttling settings will also prevent its use for DOS and other malicious activity.

Project is in alpha. Current RPC settings if wanting to test:

Network Name: xdcchain.xyz PublicNexus
RPC URL: https://publicnexus.xdcchain.xyz
Chain ID: 50
Currency Symbol: XDC
Explorer: https://explorer.xinfin.network

Because Publicnexus uses all known public RPCs, it means this access point only supports the xdc prefix at the moment. A secondary access point can be added at a later point specifically for supporting the 0x-prefix if needed)
