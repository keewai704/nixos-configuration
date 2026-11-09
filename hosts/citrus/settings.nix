let
  tailnetHostname = "citrus.tail1e65cd.ts.net";
in
{
  inherit tailnetHostname;

  hostName = "citrus";
  tailnetOrigin = "https://" + tailnetHostname;
  nginxPort = 8000;
  t3codePort = 3773;

  lanInterface = "eno1";
  lanMac = "bc:fc:e7:3a:3d:23";

  immichMachineLearningPort = 3003;
  immichMachineLearningClients = [
    "100.85.28.79"
    "fd7a:115c:a1e0::953a:1c50"
  ];
}
