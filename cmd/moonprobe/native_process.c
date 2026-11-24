/* Windows-only OS transport. No shell or contract logic. The child is trusted,
   not sandboxed. Delete-on-close files under explicit D cwd avoid pipe deadlock. */
#include "moonbit.h"
#include <windows.h>
#include <wchar.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define MP_LIMIT 1048576

static wchar_t *mp_wide(const char *s) {
  int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,NULL,0);
  if(!n)return NULL;
  wchar_t *p=malloc((size_t)n*sizeof(wchar_t));
  if(p)MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,p,n);
  return p;
}
/* CRT argv quoting, including embedded quotes, empty arguments and trailing \. */
static int mp_quote(wchar_t *out,size_t *pos,const wchar_t *arg) {
  size_t n=wcslen(arg),slashes=0;
  if(*pos+2*n+4>=32767)return 0;
  out[(*pos)++]=L'"';
  for(size_t i=0;i<n;i++) {
    if(arg[i]==L'\\'){slashes++;continue;}
    if(arg[i]==L'"') {
      for(size_t j=0;j<2*slashes+1;j++)out[(*pos)++]=L'\\';
    } else for(size_t j=0;j<slashes;j++)out[(*pos)++]=L'\\';
    out[(*pos)++]=arg[i];slashes=0;
  }
  for(size_t j=0;j<2*slashes;j++)out[(*pos)++]=L'\\';
  out[(*pos)++]=L'"';out[*pos]=0;return 1;
}
static HANDLE mp_temp(const wchar_t *cwd,unsigned tag) {
  size_t n=wcslen(cwd)+100;
  wchar_t *p=malloc(n*sizeof(wchar_t));
  if(!p)return INVALID_HANDLE_VALUE;
  SECURITY_ATTRIBUTES sa={sizeof(sa),NULL,TRUE};
  HANDLE h=INVALID_HANDLE_VALUE;
  for(unsigned k=0;k<32&&h==INVALID_HANDLE_VALUE;k++) {
    swprintf(p,n,L"%ls\\.moonprobe-%lu-%llu-%u-%u.tmp",cwd,
      GetCurrentProcessId(),(unsigned long long)GetTickCount64(),tag,k);
    h=CreateFileW(p,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_DELETE,
      &sa,CREATE_NEW,FILE_ATTRIBUTE_TEMPORARY|FILE_FLAG_DELETE_ON_CLOSE,NULL);
    if(h==INVALID_HANDLE_VALUE&&GetLastError()!=ERROR_FILE_EXISTS)break;
  }
  free(p);return h;
}
MOONBIT_EXPORT moonbit_bytes_t mp_process(moonbit_bytes_t exe,
  moonbit_bytes_t argv,moonbit_bytes_t cwd,moonbit_bytes_t input,int timeout) {
  int code=1; moonbit_bytes_t result=NULL;
  wchar_t *wexe=mp_wide((const char*)exe),*wcwd=mp_wide((const char*)cwd);
  wchar_t *cmd=calloc(32768,sizeof(wchar_t));size_t pos=0;
  HANDLE in=INVALID_HANDLE_VALUE,out=INVALID_HANDLE_VALUE,err=INVALID_HANDLE_VALUE,job=NULL;
  STARTUPINFOEXW si;PROCESS_INFORMATION pi;SIZE_T attrsize=0;
  memset(&si,0,sizeof(si));memset(&pi,0,sizeof(pi));
  if(!wexe||!wcwd||!cmd||timeout<10||timeout>5000)goto done;
  if((wcwd[0]!=L'D'&&wcwd[0]!=L'd')||wcwd[1]!=L':')goto done;
  if(!mp_quote(cmd,&pos,wexe))goto done;
  int32_t len=Moonbit_array_length(argv);
  for(int32_t offset=0;offset<len;) {
    size_t n=strlen((const char*)argv+offset);
    if(n>=(size_t)(len-offset))goto done;
    wchar_t *warg=mp_wide((const char*)argv+offset);if(!warg)goto done;
    cmd[pos++]=L' ';int ok=mp_quote(cmd,&pos,warg);free(warg);
    if(!ok)goto done;offset+=(int32_t)n+1;
  }
  in=mp_temp(wcwd,0);out=mp_temp(wcwd,1);err=mp_temp(wcwd,2);
  if(in==INVALID_HANDLE_VALUE||out==INVALID_HANDLE_VALUE||err==INVALID_HANDLE_VALUE)goto done;
  DWORD wrote=0;int32_t input_size=Moonbit_array_length(input);
  if(input_size>MP_LIMIT||!WriteFile(in,input,(DWORD)input_size,&wrote,NULL)||wrote!=(DWORD)input_size)goto done;
  SetFilePointer(in,0,NULL,FILE_BEGIN);
  job=CreateJobObjectW(NULL,NULL);if(!job)goto done;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;memset(&limits,0,sizeof(limits));
  limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if(!SetInformationJobObject(job,JobObjectExtendedLimitInformation,&limits,sizeof(limits)))goto done;
  si.StartupInfo.cb=sizeof(si);si.StartupInfo.dwFlags=STARTF_USESTDHANDLES;
  si.StartupInfo.hStdInput=in;si.StartupInfo.hStdOutput=out;si.StartupInfo.hStdError=err;
  InitializeProcThreadAttributeList(NULL,1,0,&attrsize);
  si.lpAttributeList=malloc(attrsize);if(!si.lpAttributeList)goto done;
  if(!InitializeProcThreadAttributeList(si.lpAttributeList,1,0,&attrsize)){
    free(si.lpAttributeList);si.lpAttributeList=NULL;goto done;
  }
  HANDLE handles[3]={in,out,err};
  if(!UpdateProcThreadAttribute(si.lpAttributeList,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
    handles,sizeof(handles),NULL,NULL))goto done;
  if(!CreateProcessW(wexe,cmd,NULL,NULL,TRUE,
    CREATE_NO_WINDOW|CREATE_SUSPENDED|EXTENDED_STARTUPINFO_PRESENT,NULL,wcwd,&si.StartupInfo,&pi))goto done;
  if(!AssignProcessToJobObject(job,pi.hProcess))goto done;
  if(ResumeThread(pi.hThread)==(DWORD)-1)goto done;
  ULONGLONG start=GetTickCount64();
  for(;;) {
    DWORD state=WaitForSingleObject(pi.hProcess,10);
    LARGE_INTEGER a,b;
    if(!GetFileSizeEx(out,&a)||!GetFileSizeEx(err,&b))goto done;
    if(a.QuadPart>MP_LIMIT||b.QuadPart>MP_LIMIT){code=3;goto done;}
    if(state==WAIT_OBJECT_0)break;
    if(state!=WAIT_TIMEOUT)goto done;
    if(GetTickCount64()-start>=(ULONGLONG)timeout){code=2;goto done;}
  }
  DWORD exitcode;
  if(!GetExitCodeProcess(pi.hProcess,&exitcode))goto done;
  if(exitcode){code=4;goto done;}
  /* Close the job before reading, stopping any descendants holding output open. */
  CloseHandle(job);job=NULL;
  LARGE_INTEGER size;if(!GetFileSizeEx(out,&size))goto done;
  if(size.QuadPart>MP_LIMIT){code=3;goto done;}
  result=moonbit_make_bytes((int32_t)size.QuadPart+1,0);
  SetFilePointer(out,0,NULL,FILE_BEGIN);DWORD got=0;
  if(!ReadFile(out,result+1,(DWORD)size.QuadPart,&got,NULL)||got!=(DWORD)size.QuadPart){result[0]=1;}
  goto done;
done:
  if(job)CloseHandle(job);
  if(pi.hProcess){TerminateProcess(pi.hProcess,1);WaitForSingleObject(pi.hProcess,5000);CloseHandle(pi.hProcess);}
  if(pi.hThread)CloseHandle(pi.hThread);
  if(si.lpAttributeList){DeleteProcThreadAttributeList(si.lpAttributeList);free(si.lpAttributeList);}
  if(in!=INVALID_HANDLE_VALUE)CloseHandle(in);
  if(out!=INVALID_HANDLE_VALUE)CloseHandle(out);
  if(err!=INVALID_HANDLE_VALUE)CloseHandle(err);
  free(wexe);free(wcwd);free(cmd);
  if(!result){result=moonbit_make_bytes(1,0);result[0]=(uint8_t)code;}
  return result;
}
