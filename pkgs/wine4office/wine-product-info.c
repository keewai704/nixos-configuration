#include <windows.h>
#include "sl.h"

BOOL IsWineProductWithKey(HSLC handle, const SLID *sku);

HRESULT WINAPI WineGetProductSkuInformation(HSLC handle, const SLID *sku,
        PCWSTR name, SLDATATYPE *type, UINT *size, PBYTE *value)
{
    HRESULT result = SLGetProductSkuInformation(handle, sku, name, type, size, value);
    const WCHAR *fallback;
    BYTE *product_name = NULL, *buffer;
    UINT product_name_size = 0, bytes;
    BOOL supported;

    if (result != (HRESULT)0xc004f012 || !name || !size || !value ||
            !IsWineProductWithKey(handle, sku))
        return result;
    if (!lstrcmpiW(name, L"ApplicationBitmap"))
        fallback = L"0x0001F1BB";
    else if (!lstrcmpiW(name, L"UXDifferentiator"))
        fallback = L"TIMEBASED_SUB";
    else
        return result;

    supported = SLGetProductSkuInformation(handle, sku, L"Name", NULL,
            &product_name_size, &product_name) == S_OK && product_name &&
            !lstrcmpiW((WCHAR *)product_name, L"Office 16, O365ProPlusRetail edition");
    LocalFree(product_name);
    if (!supported) return result;

    bytes = (lstrlenW(fallback) + 1) * sizeof(WCHAR);
    if (!(buffer = LocalAlloc(LMEM_FIXED, bytes))) return E_OUTOFMEMORY;
    CopyMemory(buffer, fallback, bytes);
    *value = buffer;
    *size = bytes;
    if (type) *type = SL_DATA_SZ;
    return S_OK;
}
