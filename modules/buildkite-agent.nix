{ name, pkgs, ... }:

{
  imports = [
    ./../modules/hydra-slave.nix
  ];

  services.buildkite-agent = {
    enable = true;
    name   = name;
    openssh.privateKey = "/run/keys/buildkite-ssh-private";
    openssh.publicKey  = "/run/keys/buildkite-ssh-public";
    token              = "/run/keys/buildkite-token";
  };

  deployment.keys = {
    buildkite-ssh-private = {
      keyFile = ./. + "/../static/buildkite-ssh";
      user    = "buildkite-agent";
    };
    buildkite-ssh-public = {
      keyFile = ./. + "/../static/buildkite-ssh.pub";
      user    = "buildkite-agent";
    };
    buildkite-token = {
      keyFile = ./. + "/../static/buildkite-token";
      user    = "buildkite-agent";
    };
  };
}
