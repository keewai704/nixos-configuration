let
  tailnetHostname = "citrus.tail1e65cd.ts.net";
in
{
  inherit tailnetHostname;

  hostName = "citrus";
  tailnetOrigin = "https://" + tailnetHostname;
  nginxPort = 8000;
  t3codePort = 3773;
}
