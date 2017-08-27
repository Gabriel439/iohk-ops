{ accessKeyId, deployerIP
, topologyFile ? ./../topology.nix
, systemStart
, environment
, ... }:

with (import ./../lib.nix);

let topologySpec  = (builtins.fromJSON (builtins.readFile topologyFile));
    # WARNING: this sort order is key in a number of things:
    #          - relay numbering
    #          - DNS naming
    topologyList  = builtins.sort (l: r: l.name < r.name)
                                   (mapAttrsToList (k: v: { name = k; value = v; }) topologySpec);
    regionList    = unique (map (n: n.value.region) topologyList);
    globalArgs    = {
      inherit allNames environment firstRelayIndex nRelays systemStart;
    };
    indexed       = imap (n: x:
           let spec = x.value; in
           { name = x.name; value = globalArgs // rec {
                                        inherit (spec) region type kademlia peers;
                                i = n - 1;
                       relayIndex = if type == "relay" then i - firstRelayIndex else null;
                             name = x.name; # This is an important identity, let's not break it.
                                    ## For the SG definitions look below in this file:
                          sgNames = if      spec.type == "core"  then
                                      [ "allow-deployer-ssh-${region}"
                                        "allow-cardano-static-peers-${name}-${region}" ]
                                    else if spec.type == "relay" then
                                      [ "allow-deployer-ssh-${region}"
                                        "allow-kademlia-public-udp-${region}"
                                        "allow-cardano-public-tcp-${region}" ]
                                    else throw "While computing EC2 SGs: unhandled cardano-node type: '${type}', must be either 'core' or 'relay'";
                             }; } ) topologyList;
    byName        = name: let xs = filter (n: n.name == name) indexed;
                          in if xs != [] then builtins.elemAt xs 0
                             else throw "No indexedNode by name '${name}'.";
    # Canonical node parameter format is:
    #   i             :: Int
    #   region        :: String
    #   type          :: String               -- one of: 'core', 'relay'
    #   static-routes :: [['nodeId, 'nodeId]] -- here we go, TupleList..
    #
    # WARNING: this depends on the sort order, as explained above.
    firstRelay      = findFirst (x: x.value.type == "relay") (throw "No relays in topology, it's sad we can't live..") indexed;
    nRelays         = length relays;
    firstRelayIndex = firstRelay.value.i;
    allNames        = map (x: x.name) indexed;
    cores           = filter (x: x.value.type == "core")  indexed;
    relays          = filter (x: x.value.type == "relay") indexed;
    canonical       = builtins.listToAttrs (cores ++ relays);
    ##
    ##
    regionSGNames = region:
        [ "allow-deployer-ssh-${region}"
          "allow-kademlia-public-udp-${region}"
          "allow-cardano-public-tcp-${region}"
        ];
    regionSGs      = nodePort: region: {
        "allow-deployer-ssh-${region}" = {
          inherit region accessKeyId;
          description = "SSH";
          rules = [{
            protocol = "tcp"; # TCP
            fromPort = 22; toPort = 22;
            sourceIp = deployerIP + "/32";
          }];
        };
        "allow-kademlia-public-udp-${region}" = {
          inherit region accessKeyId;
          description = "Kademlia UDP public";
          rules = [{
            protocol = "udp"; # UDP
            sourceIp = "0.0.0.0/0";
            fromPort = 1024; toPort = 65535;
          }];
        };
        "allow-cardano-public-tcp-${region}" = {
          inherit region accessKeyId;
          description = "Cardano TCP public (+WWW)";
          rules = [{
            protocol = "tcp"; # TCP
            fromPort = nodePort; toPort = nodePort;
            sourceIp = "0.0.0.0/0";
          }{
            protocol = "tcp";
            fromPort = 8080; toPort = 8080;
            sourceIp = "0.0.0.0/0";
          }];
        };
      };
    coreSGNames = core:
        [ "allow-cardano-static-peers-${core.name}-${core.value.region}" ];
    coreSGs     = nodePort: ips: core:
      let neighbourNames = traceSF (p: "${core.name} peers: " + concatStringsSep ", " core.value.peers) core.value.peers;
          neighbours = map byName neighbourNames;
          neigh'rule =
          neigh:
          let
            ip = ips."${toString neigh.value.name}-ip";
          in {
              fromPort = nodePort; toPort = nodePort;
              sourceIp = ip;
            };
      in {
        "allow-cardano-static-peers-${core.name}-${core.value.region}" = {
          inherit accessKeyId;
          region = core.value.region;
          description = "Cardano TCP static peers of ${core.name}";
          rules = map neigh'rule neighbours;
        };
      };
    globalSGNames = centralRegion:
        [ "allow-to-explorer-${centralRegion}"
          "allow-to-report-server-${centralRegion}" ];
    globalSGs = centralRegion:
      let region = centralRegion;
      in [{
        "allow-to-explorer-${region}" = {
          inherit region accessKeyId;
          description = "Access Cardano Explorer";
          rules = [{
            protocol = "tcp";
            fromPort = 80; toPort = 80;
            sourceIp = "0.0.0.0/0";
          }];
        };
        "allow-to-report-server-${region}" = {
          inherit region accessKeyId;
          description = "Access Cardano report server";
          rules = [{
            protocol = "tcp";
            fromPort = 8080; toPort = 8080;
            sourceIp = "0.0.0.0/0";
          }];
        };
      }];
    centralRegion      = "eu-central-1";
    securityGroupNames =
     (    concatMap  regionSGNames                             regionList
      ++  concatMap  coreSGNames                               cores
      ++            (globalSGNames centralRegion)
     );
    elasticIPsSecurityGroups =
     elasticIPs:
     (fold (x: y: x // y) {}
     (    map       (regionSGs     cconf.nodePort)             regionList
      ++  map       (coreSGs       cconf.nodePort elasticIPs)  cores
      ++            (globalSGs     centralRegion)
     ));
in
{
  nodeArgs           = canonical;
  globalArgs         = globalArgs;
  cores              = cores;
  relays             = relays;
  securityGroupNames = securityGroupNames;
  securityGroups     = elasticIPsSecurityGroups;
}
