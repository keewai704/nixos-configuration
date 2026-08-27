let
  orange = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZZNqAbOWLZSN5OSe2NjcDuUZLxgSxDAMm+1GkcQQHu root@nixos";
in
{
  "discord-webhook.age".publicKeys = [ orange ];
}
