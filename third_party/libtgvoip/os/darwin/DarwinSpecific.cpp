//
// libtgvoip is free and unencumbered public domain software.
// For more information, see http://unlicense.org or the UNLICENSE file
// you should have received with this source code distribution.
//

#include "DarwinSpecific.h"

#include <string.h>
#include <sys/utsname.h>

using namespace tgvoip;

/* local patch: the original is Objective-C++ and asks the process info for a version string that only lands in the call log; the kernel
   release from uname does the same job without a second language in the build */
void DarwinSpecific::GetSystemName(char* buf, size_t len){
	struct utsname name;
	if(len==0)
		return;
	if(uname(&name)!=0){
		strncpy(buf, "unknown", len-1);
		buf[len-1]=0;
		return;
	}
	strncpy(buf, name.release, len-1);
	buf[len-1]=0;
}
