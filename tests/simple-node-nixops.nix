let
  nodeArgs = import ./cardano-node-simple-config.nix;
in
import <nixpkgs/nixos/tests/make-test.nix> ({ pkgs, ... }: {
  name = "boot";
  nodes = {
    machine = { config, pkgs, ... }: {
      imports = [ (import ../modules/cardano-node-config.nix (nodeArgs.machine)) <nixops/nix/options.nix> <nixops/nix/resource.nix> ];
      services.cardano-node = {
        autoStart = true;
        initialKademliaPeers = [];
        neighbours = [];
      };
    };
  };
  testScript = ''
    startAll
    $machine->waitForUnit("cardano-node.service");
    # TODO, implement sd_notify?
    $machine->waitForOpenPort(3000);
  '';
})
