#define UNICODE
#define _UNICODE
#include <windows.h>
#include <wchar.h>
int WINAPI wWinMain(HINSTANCE a,HINSTANCE b,PWSTR c,int d){
  wchar_t root[MAX_PATH],command[4096];
  if(!GetModuleFileNameW(NULL,root,MAX_PATH))return 1;
  for(int i=0;i<3;i++){wchar_t*p=wcsrchr(root,L'\\');if(!p)return 1;*p=0;}
  _snwprintf(command,4096,L"pwsh.exe -NoProfile -STA -File \"%ls\\scripts\\demo-window.ps1\"",root);
  STARTUPINFOW si={0};si.cb=sizeof(si);PROCESS_INFORMATION pi={0};
  if(!CreateProcessW(NULL,command,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,root,&si,&pi))return 2;
  CloseHandle(pi.hThread);CloseHandle(pi.hProcess);return 0;
}
