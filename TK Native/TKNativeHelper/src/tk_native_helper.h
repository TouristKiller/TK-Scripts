#pragma once

void tknh_log(const char* msg);
void* tknh_main_hwnd();

#if defined(__APPLE__)
bool startFileDragMac(const char* utf8_path);
#elif defined(__linux__)
bool startFileDragLinux(const char* utf8_path);
#endif
