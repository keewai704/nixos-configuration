let
  orange = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZZNqAbOWLZSN5OSe2NjcDuUZLxgSxDAMm+1GkcQQHu root@nixos";
  citrus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII65ZLvXUd+eN82MkMTY2waQL+hFjITwKt010l4fYHbc root@citrus";
in
{
  "discord-webhook.age".publicKeys = [ orange ];
  "opencode-api-key.age".publicKeys = [
    orange
    citrus
  ];
}
