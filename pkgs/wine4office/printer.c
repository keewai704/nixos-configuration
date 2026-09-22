#include <windows.h>
#include <winspool.h>
#include <stdio.h>

int wmain(int argc, WCHAR **argv)
{
    WCHAR name[256];
    DWORD length = sizeof(name) / sizeof(name[0]);
    DRIVER_INFO_3W driver = {0};
    PRINTER_INFO_2W printer = {0};
    HANDLE handle;

    if (argc != 2) return 2;
    if (GetDefaultPrinterW(name, &length)) return 0;

    driver.cVersion = 3;
    driver.pName = L"Wine PostScript";
    driver.pEnvironment = L"Windows x64";
    driver.pDriverPath = L"C:\\windows\\system32\\wineps.drv";
    driver.pConfigFile = driver.pDriverPath;
    driver.pDataFile = argv[1];
    driver.pDefaultDataType = L"RAW";

    if (!AddPrinterDriverExW(NULL, 3, (BYTE *)&driver,
            APD_COPY_ALL_FILES | APD_COPY_FROM_DIRECTORY)) {
        fwprintf(stderr, L"AddPrinterDriverEx: %lu\n", GetLastError());
        return 1;
    }

    printer.pPrinterName = L"Wine PostScript (FILE)";
    printer.pPortName = L"FILE:";
    printer.pDriverName = driver.pName;
    printer.pPrintProcessor = L"WinPrint";
    printer.pDatatype = L"RAW";
    printer.Attributes = PRINTER_ATTRIBUTE_LOCAL;
    if (!(handle = AddPrinterW(NULL, 2, (BYTE *)&printer))) {
        fwprintf(stderr, L"AddPrinter: %lu\n", GetLastError());
        return 1;
    }
    ClosePrinter(handle);
    if (!SetDefaultPrinterW(printer.pPrinterName)) {
        fwprintf(stderr, L"SetDefaultPrinter: %lu\n", GetLastError());
        return 1;
    }
    length = sizeof(name) / sizeof(name[0]);
    if (!GetDefaultPrinterW(name, &length)) return 1;
    wprintf(L"Default printer: %ls\n", name);
    return 0;
}
