{ accessKeyId, region }:

with (import ./../lib.nix);

let
  instancesPerNode = 10;
  config = import ../config.nix;
  mkNode = publicIP: nodes: index: {
    name = "instance${toString index}";
    value = {
      autoStart = true;
      privateNetwork = false;
      config = { ... }: {
        imports = [ ./common.nix ];
        networking.extraHosts = ''
          ${nodes.relay-1.config.services.cardano-node.publicIP} relay-1
        '';
        networking.nameservers = [ "127.0.0.1" ];
        services.cardano-node = {
          topologyFile = "${../topology-edgenode-3.yaml}";
          enable = true;
          nodeIndex = 50;
          inherit (config) genesisN enableP2P productionMode;
          nodeName = "edgenode";
          type = "edge";
          extraArgs = "--peer-relay ${nodes.relay-1.config.services.cardano-node.publicIP}:3000";
          #inherit publicIP;
        };
      };
    };
  };
in { config, resources, pkgs, nodes, options, ... }:
{
  imports = [ ./amazon-base.nix ./cardano-node-scaling.nix ];
  deployment.ec2.region = mkForce region;
  deployment.ec2.accessKeyId = accessKeyId;
  deployment.ec2.keyPair = resources.ec2KeyPairs.${keypairFor accessKeyId region};
  containers = listToAttrs (map (mkNode config.networking.publicIPv4 nodes) (range 1 instancesPerNode));
  services.dnsmasq.enable = true;
  networking.extraHosts = ''
    ${nodes.relay-1.config.services.cardano-node.publicIP} relay-1.cardano
    127.0.0.1 edgenode.cardano
  '';
}
