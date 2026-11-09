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

  sttPort = 8010;
  sttClients = [
    "100.65.216.48"
    "fd7a:115c:a1e0::832c:d831"
    "100.84.156.95"
    "fd7a:115c:a1e0::433a:9c5f"
    "100.99.205.86"
    "fd7a:115c:a1e0::5f2c:cd57"
    "100.107.8.87"
    "fd7a:115c:a1e0::8d3a:857"
    "100.85.28.79"
    "fd7a:115c:a1e0::953a:1c50"
  ];

  plamoPort = 8020;
  plamoIdleSeconds = 600;
  plamoClients = [
    "100.65.216.48"
    "fd7a:115c:a1e0::832c:d831"
    "100.84.156.95"
    "fd7a:115c:a1e0::433a:9c5f"
    "100.99.205.86"
    "fd7a:115c:a1e0::5f2c:cd57"
    "100.107.8.87"
    "fd7a:115c:a1e0::8d3a:857"
    "100.85.28.79"
    "fd7a:115c:a1e0::953a:1c50"
  ];

  immichMachineLearningPort = 3003;
  immichMachineLearningClients = [
    "100.85.28.79"
    "fd7a:115c:a1e0::953a:1c50"
  ];
}
