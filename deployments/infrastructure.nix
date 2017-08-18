{ ... }:

with (import ./../lib.nix);

let
  mkHydraBuildSlave = { config, pkgs, ... }: {
    imports = [
      ./../modules/hydra-slave.nix
      ./../modules/common.nix
    ];
  };
in {
  hydra = { config, pkgs, ... }: {
    # On first setup:

    # Locally: $ ssh-keygen -C "hydra@hydra.example.org" -N "" -f static/id_buildfarm
    # On Hydra: $ /run/current-system/sw/bin/hydra-create-user alice --full-name 'Alice Q. User' --email-address 'alice@example.org' --password foobar --role admin

    imports = [
      ./../modules/hydra-slave.nix
      ./../modules/hydra-master.nix
      ./../modules/common.nix
    ];
  };

  hydra-build-slave-1 = mkHydraBuildSlave;
  hydra-build-slave-2 = mkHydraBuildSlave;

  cardano-deployer = { config, pkgs, ... }: {
    imports = [
      ./../modules/common.nix
    ];

    users = {
      users.staging = {
        description     = "cardano staging";
        group           = "staging";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = devKeys;
      };
      groups.staging = {};

      users.production = {
        description     = "cardano production";
        group           = "production";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = [];  # this account is obsolete
      };
      groups.production = {};

      users.live-production = {
        description     = "cardano live-production";
        group           = "live-production";
        createHome      = true;
        isNormalUser = true;
        openssh.authorizedKeys.keys = devOpsKeys;
      };
      groups.live-production = {};
    };

    services.tarsnap = {
      enable = true;
      keyfile = "/var/lib/keys/tarsnap";
      archives.cardano-deployer = {
        directories = [
          "/home/staging/.ec2-keys"
          "/home/staging/.aws"
          "/home/staging/.nixops"
          "/home/live-production/.ec2-keys"
          "/home/live-production/.aws"
          "/home/live-production/.nixops"
          "/etc/"
        ];
      };
    };

    networking.firewall.allowedTCPPortRanges = [
      { from = 24962; to = 25062; }
    ];
  };
}
