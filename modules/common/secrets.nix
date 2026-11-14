{ inputs, ... }:
{
  imports = [ inputs.agenix.nixosModules.default ];

  age.secrets.opencode-api-key = {
    file = ../../secrets/opencode-api-key.age;
    mode = "0400";
    owner = "keewai";
  };

  age.secrets.tinyfish-api-key = {
    file = ../../secrets/tinyfish-api-key.age;
    mode = "0400";
    owner = "keewai";
  };
}
