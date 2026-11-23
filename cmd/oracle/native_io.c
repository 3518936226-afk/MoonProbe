/* OS-only bridge. No Schema, generation, adapter, shrink or replay logic. */
#include "moonbit.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#include <direct.h>
#include <io.h>
static wchar_t *wide(const char *s) {
  int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,NULL,0);
  if (!n) return NULL;
  wchar_t *p=malloc((size_t)n*sizeof(wchar_t));
  if (p) MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,p,n);
  return p;
}
static FILE *read_open(const char *s) { wchar_t *p=wide(s); if(!p)return NULL; FILE *f=_wfopen(p,L"rb");free(p);return f; }
static FILE *exclusive_open(const char *s) { wchar_t *p=wide(s);if(!p)return NULL;int fd=_wopen(p,_O_WRONLY|_O_CREAT|_O_EXCL|_O_BINARY,_S_IREAD|_S_IWRITE);free(p);if(fd<0)return NULL;FILE*f=_fdopen(fd,"wb");if(!f)_close(fd);return f; }
#else
#include <unistd.h>
static FILE *read_open(const char *s) { return fopen(s,"rb"); }
static FILE *exclusive_open(const char *s) { int fd=open(s,O_WRONLY|O_CREAT|O_EXCL,0666);if(fd<0)return NULL;FILE*f=fdopen(fd,"wb");if(!f)close(fd);return f; }
#endif
static moonbit_bytes_t status(int n) { moonbit_bytes_t b=moonbit_make_bytes(1,0);b[0]=(uint8_t)n;return b; }
MOONBIT_EXPORT moonbit_bytes_t mp_read_file(moonbit_bytes_t path) {
  FILE *f=read_open((const char*)path);if(!f)return status(1);
  if(fseek(f,0,SEEK_END)){fclose(f);return status(1);}
  long size=ftell(f);if(size<0){fclose(f);return status(1);}
  if(size>1048576){fclose(f);return status(2);}
  rewind(f);moonbit_bytes_t b=moonbit_make_bytes((int32_t)size+1,0);
  size_t read=fread(b+1,1,(size_t)size,f);int error=ferror(f);fclose(f);
  if(read!=(size_t)size||error)b[0]=1;return b;
}
MOONBIT_EXPORT int mp_write_file(moonbit_bytes_t path,moonbit_bytes_t data) {
  FILE*f=exclusive_open((const char*)path);if(!f)return 1;
  int32_t len=Moonbit_array_length(data);
  size_t n=fwrite(data,1,(size_t)len,f);int error=fclose(f);
  return n!=(size_t)len||error;
}
MOONBIT_EXPORT int mp_exists(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t*p=wide((const char*)path);if(!p)return -1;
  DWORD a=GetFileAttributesW(p);free(p);if(a!=INVALID_FILE_ATTRIBUTES)return 1;
  DWORD e=GetLastError();return (e==ERROR_FILE_NOT_FOUND||e==ERROR_PATH_NOT_FOUND)?0:-1;
#else
  struct stat st;if(!stat((const char*)path,&st))return 1;return errno==ENOENT?0:-1;
#endif
}
MOONBIT_EXPORT int mp_mkdirs(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t*p=wide((const char*)path);if(!p)return 1;size_t n=wcslen(p);
  for(size_t i=0;i<=n;i++)if(p[i]==L'/'||p[i]==L'\\'||!p[i]){
    if(i==0||(i==2&&p[1]==L':'))continue;
    wchar_t saved=p[i];p[i]=0;int r=_wmkdir(p);if(r&&errno!=EEXIST){free(p);return 1;}p[i]=saved;
  }free(p);return 0;
#else
  char*p=strdup((const char*)path);if(!p)return 1;size_t n=strlen(p);
  for(size_t i=1;i<=n;i++)if(p[i]=='/'||!p[i]){char saved=p[i];p[i]=0;if(mkdir(p,0777)&&errno!=EEXIST){free(p);return 1;}p[i]=saved;}free(p);return 0;
#endif
}
