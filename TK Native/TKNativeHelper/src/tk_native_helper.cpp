#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef WDL_NO_DEFINE_MINMAX
#define WDL_NO_DEFINE_MINMAX
#endif

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <string>

#ifdef _WIN32
#include <windows.h>
#include <shlobj.h>
#include <ole2.h>
#endif

#include "reaper_plugin.h"
#include "tk_native_helper.h"

namespace
{
reaper_plugin_info_t* g_rec = nullptr;

using ShowConsoleMsgFn = void (*)(const char*);
ShowConsoleMsgFn g_showConsoleMsg = nullptr;

using GetMainHwndFn = void* (*)();
GetMainHwndFn g_getMainHwnd = nullptr;

#ifdef _WIN32
void logMsg(const char* text)
{
    if (g_showConsoleMsg) g_showConsoleMsg(text);
}

void logMsgf(const char* fmt, ...)
{
    if (!g_showConsoleMsg) return;
    char buffer[1024];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    g_showConsoleMsg(buffer);
}

class TKDropSource : public IDropSource
{
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override
    {
        if (riid == IID_IUnknown || riid == IID_IDropSource)
        {
            *ppv = static_cast<IDropSource*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&ref_)); }

    ULONG STDMETHODCALLTYPE Release() override
    {
        LONG c = InterlockedDecrement(&ref_);
        if (c == 0) delete this;
        return static_cast<ULONG>(c);
    }

    HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escapePressed, DWORD keyState) override
    {
        if (escapePressed) return DRAGDROP_S_CANCEL;
        if (!(keyState & (MK_LBUTTON | MK_RBUTTON))) return DRAGDROP_S_DROP;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }

private:
    LONG ref_ = 1;
};

std::wstring normalizePath(const char* utf8_path)
{
    int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, nullptr, 0);
    if (wlen <= 0) return std::wstring();
    std::wstring wpath(static_cast<size_t>(wlen), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8_path, -1, &wpath[0], wlen);
    while (!wpath.empty() && wpath.back() == L'\0') wpath.pop_back();
    for (auto& ch : wpath)
    {
        if (ch == L'/') ch = L'\\';
    }
    return wpath;
}

bool startFileDragWin(const char* utf8_path)
{
    if (!utf8_path || !*utf8_path)
    {
        logMsg("[TKNativeHelper] leeg pad\n");
        return false;
    }

    std::wstring wpath = normalizePath(utf8_path);
    if (wpath.empty())
    {
        logMsg("[TKNativeHelper] pad-conversie faalde\n");
        return false;
    }

    PIDLIST_ABSOLUTE pidl = nullptr;
    HRESULT hr = SHParseDisplayName(wpath.c_str(), nullptr, &pidl, 0, nullptr);
    if (FAILED(hr) || !pidl)
    {
        logMsgf("[TKNativeHelper] SHParseDisplayName faalde hr=0x%08X\n", static_cast<unsigned>(hr));
        return false;
    }

    bool dropped = false;
    IShellFolder* parent = nullptr;
    PCUITEMID_CHILD child = nullptr;
    hr = SHBindToParent(pidl, IID_IShellFolder, reinterpret_cast<void**>(&parent), &child);
    if (SUCCEEDED(hr) && parent)
    {
        IDataObject* dataObject = nullptr;
        hr = parent->GetUIObjectOf(nullptr, 1, &child, IID_IDataObject, nullptr,
                                   reinterpret_cast<void**>(&dataObject));
        if (SUCCEEDED(hr) && dataObject)
        {
            TKDropSource* source = new TKDropSource();
            DWORD effect = 0;
            HRESULT dres = DoDragDrop(dataObject, source, DROPEFFECT_COPY | DROPEFFECT_LINK, &effect);
            dropped = (dres == DRAGDROP_S_DROP && effect != DROPEFFECT_NONE);
            if (!dropped)
                logMsgf("[TKNativeHelper] DoDragDrop hr=0x%08X effect=%u\n",
                        static_cast<unsigned>(dres), static_cast<unsigned>(effect));
            source->Release();
            dataObject->Release();
        }
        else
        {
            logMsgf("[TKNativeHelper] GetUIObjectOf faalde hr=0x%08X\n", static_cast<unsigned>(hr));
        }
        parent->Release();
    }
    else
    {
        logMsgf("[TKNativeHelper] SHBindToParent faalde hr=0x%08X\n", static_cast<unsigned>(hr));
    }
    CoTaskMemFree(pidl);
    return dropped;
}
#endif

bool TK_StartFileDrag(const char* file_path)
{
#if defined(_WIN32)
    return startFileDragWin(file_path);
#elif defined(__APPLE__)
    return startFileDragMac(file_path);
#elif defined(__linux__)
    return startFileDragLinux(file_path);
#else
    (void)file_path;
    return false;
#endif
}

void* __vararg_TK_StartFileDrag(void** arglist, int numparms)
{
    const char* path = (numparms >= 1 && arglist) ? static_cast<const char*>(arglist[0]) : nullptr;
    return reinterpret_cast<void*>(static_cast<intptr_t>(TK_StartFileDrag(path) ? 1 : 0));
}

const char __def_TK_StartFileDrag[] =
    "bool\0const char*\0file_path\0"
    "Starts a native OS file drag-and-drop for the given file path so it can be dropped onto external plugin windows "
    "(Windows OLE, macOS NSDraggingSession, Linux XDND). Returns true when the file was dropped on a target.";

bool registerApi(reaper_plugin_info_t* rec)
{
    if (!rec->Register("API_TK_StartFileDrag", reinterpret_cast<void*>(TK_StartFileDrag))) return false;
    if (!rec->Register("APIvararg_TK_StartFileDrag", reinterpret_cast<void*>(__vararg_TK_StartFileDrag)))
    {
        rec->Register("-API_TK_StartFileDrag", reinterpret_cast<void*>(TK_StartFileDrag));
        return false;
    }
    rec->Register("APIdef_TK_StartFileDrag", const_cast<char*>(__def_TK_StartFileDrag));
    return true;
}

void unregisterApi()
{
    if (!g_rec) return;
    g_rec->Register("-API_TK_StartFileDrag", reinterpret_cast<void*>(TK_StartFileDrag));
    g_rec->Register("-APIvararg_TK_StartFileDrag", reinterpret_cast<void*>(__vararg_TK_StartFileDrag));
}
}

void tknh_log(const char* msg)
{
    if (g_showConsoleMsg) g_showConsoleMsg(msg);
}

void* tknh_main_hwnd()
{
    return g_getMainHwnd ? g_getMainHwnd() : nullptr;
}

extern "C"
{
REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t* rec)
{
    if (!rec)
    {
        unregisterApi();
        g_rec = nullptr;
        return 0;
    }

    if (rec->caller_version != REAPER_PLUGIN_VERSION || !rec->Register || !rec->GetFunc) return 0;

    g_showConsoleMsg = reinterpret_cast<ShowConsoleMsgFn>(rec->GetFunc("ShowConsoleMsg"));
    g_getMainHwnd = reinterpret_cast<GetMainHwndFn>(rec->GetFunc("GetMainHwnd"));

    g_rec = rec;
    if (!registerApi(rec))
    {
        g_rec = nullptr;
        return 0;
    }

    return 1;
}
}
